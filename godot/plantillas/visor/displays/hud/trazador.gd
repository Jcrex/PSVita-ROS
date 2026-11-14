extends "res://comun/visor/display_ros_hud.gd"
## Trazador de series (doc 36a §4.1.4, ficha nucleo#8; tarea V12; ≈ rqt_plot / Foxglove Plot) en la pestaña
## Gráficas. Hasta 3 series = rutas de campo del MISMO topic, en búferes circulares `PackedVector2Array` de (t, y) en
## unidades de datos.
##
## Dibujo SIN bucles por punto en GDScript (doc 36 §7; H17): `draw_set_transform` hace el mapeo datos → píxeles en el
## C++ del lienzo y cada serie es UNA `draw_polyline(..., -1)` = 1 comando. Con 3 series: 3 comandos de series
## (`comandos_series`) + marco, línea del cero y 2 etiquetas en coordenadas de pantalla. Gate de V12 en hardware:
## pestaña Gráficas con 3 series → `draws` +≤ 3 y `avg_canvas_us` +≤ 300 [I hasta medirlo: que la polilínea fina siga
## siendo de 1 px con la transformada escalada y que el port la meta en un lote].
##
## Rutas (`campos`) con la sintaxis de Foxglove relativa al mensaje: `twist.twist.linear.x`, `poses[0].position.x`,
## `data[3]`. Si una empieza por «/» (`/odom.twist.twist.linear.x`) y `topic` está vacío, el topic sale de ahí
## (el punto no puede ir en un nombre de topic). Camino compacto (Vita, relay): `campos_vita` sobre `topic_vita`/
## `tipo_vita` (p. ej. `pose2d` con `data[3]` = vx), vacío = los mismos `campos`.
##
## Presupuesto (⚖ D6): **3 series × 64 puntos** en la Vita (se recorta aunque la escena pida más). El canal entrega
## TODAS las muestras (`coalescer = false`) con tope `capacidad` de pendientes (pestaña oculta = no bombea).
## Tiempo relativo a `conectar` (float32: ≈ 0,25 ms de resolución a 1 h, [I]).

const Intro = preload("res://comun/visor/introspeccion_ros.gd")

const SERIES_MAX := 3
const CAPACIDAD_VITA := 64

@export var campos: PackedStringArray = ["twist.twist.linear.x", "twist.twist.angular.z"]
@export var campos_vita: PackedStringArray = []
@export var ventana_s := 10.0
@export var capacidad := 64
@export var colores := PackedColorArray([COLOR_ACENTO, COLOR_INFO, COLOR_OK])
@export var margen := 4.0
## Separación mínima entre muestras guardadas (s). −1 = automática (`ventana_s / capacidad`: la ventana entera cabe en
## el búfer); 0 = todas. Revisión V3: con `/odom` (o `<p>/pose2d`) a 30 Hz y 64 puntos el búfer cubría 2,1 s de los
## 10 s de la ventana y la gráfica ocupaba solo la quinta parte derecha del panel.
@export var paso_min_s := -1.0

var series: Array = []                      # {ruta: PackedStringArray, nombre, pts: PackedVector2Array, cab, n}
var y_min := INF
var y_max := -INF
var comandos := 0                           # comandos de dibujo del último _draw (todas las primitivas)
var comandos_series := 0                    # de ellos, polilíneas de series (1 por serie)
var puntos_dibujados := PackedInt32Array()  # puntos de cada polilínea del último _draw
var _t0 := 0
var _t_ultima := -INF                       # instante de la última muestra guardada (diezmado por tiempo)


static func nombre_display() -> String:
	return "Trazador"


func _init() -> void:
	caducidad_s = 0.0                         # una gráfica parada sigue siendo legible


func conectar(v) -> void:
	if v != null and v.en_vita:
		capacidad = mini(capacidad, CAPACIDAD_VITA)
	capacidad = maxi(capacidad, 2)
	if topic == "" and campos.size() > 0 and campos[0].begins_with("/"):
		topic = Intro.partir_ruta(campos[0])["topic"]
	canal.coalescer = false                   # el trazador necesita todas las muestras
	canal.max_pendientes = capacidad
	super.conectar(v)
	preparar(campos_vita if (canal.compacto and campos_vita.size() > 0) else campos)


## (Re)crea las series a partir de rutas (máximo 3). También para las pruebas, sin ROS.
func preparar(rutas: PackedStringArray) -> void:
	series.clear()
	y_min = INF
	y_max = -INF
	_t_ultima = -INF
	_t0 = Time.get_ticks_msec()
	for c in rutas.slice(0, SERIES_MAX):
		var trozos: PackedStringArray = Intro.partir_ruta(c)["campos"]
		var pts := PackedVector2Array()
		pts.resize(capacidad)
		series.append({"ruta": trozos, "nombre": ".".join(trozos), "pts": pts, "cab": 0, "n": 0})


func _procesar(msg):
	return anadir_muestra(msg, (Time.get_ticks_msec() - _t0) * 0.001)


## Añade una muestra en el instante t (s). true si alguna serie tenía un número en su ruta.
func anadir_muestra(msg, t: float):
	var paso := paso_min_s if paso_min_s >= 0.0 else ventana_s / maxi(capacidad, 1)
	if t >= _t_ultima and t - _t_ultima < paso * 0.95:
		return null                             # diezmado por tiempo (revisión V3)
	var hubo := false
	for s in series:
		var v = Intro.leer_ruta(msg, s.ruta)
		if not (v is float or v is int or v is bool):
			continue
		var y := float(v)
		if is_nan(y) or is_inf(y):
			continue                            # trampa T2: NaN = «no medido»
		s.pts[s.cab] = Vector2(t, y)
		s.cab = (s.cab + 1) % capacidad
		s.n = mini(s.n + 1, capacidad)
		y_min = minf(y_min, y)
		y_max = maxf(y_max, y)
		hubo = true
	if hubo:
		_t_ultima = t
	return true if hubo else null


## Puntos de la serie k en orden temporal (dos `slice` en C++, sin bucle GDScript por punto).
func ordenados(k: int) -> PackedVector2Array:
	var s: Dictionary = series[k]
	if s.n < capacidad:
		return s.pts.slice(0, s.n)
	return s.pts.slice(s.cab) + s.pts.slice(0, s.cab)


func _dibujar() -> bool:
	comandos = 0
	comandos_series = 0
	puntos_dibujados = PackedInt32Array()
	var r := Rect2(Vector2.ZERO, size)
	marco(r, color_estado(COLOR_CADUCADO))
	comandos += 1
	if y_max < y_min:
		texto(Vector2(margen, 14), (topic if topic != "" else "trazador") + " ...", color_estado(COLOR_CADUCADO), 30)
		comandos += 1
		return true
	# Escala de datos a píxeles: x = últimos `ventana_s` segundos; y = [y_min, y_max] con margen.
	var t_fin := -INF
	for s in series:
		if s.n > 0:
			t_fin = maxf(t_fin, s.pts[(s.cab - 1 + capacidad) % capacidad].x)
	var rango := maxf(y_max - y_min, 1e-3)
	var y_bajo := y_min - (rango - (y_max - y_min)) * 0.5   # rango plano: centrado
	var alto := maxf(size.y - 2.0 * margen, 1.0)
	var esc := Vector2(size.x / maxf(ventana_s, 1e-3), -alto / rango)
	var org := Vector2(size.x - t_fin * esc.x, size.y - margen - y_bajo * esc.y)
	if y_bajo < 0.0 and y_bajo + rango > 0.0:
		linea(Vector2(0, org.y), Vector2(size.x, org.y), color_estado(COLOR_CADUCADO))   # cero
		comandos += 1
	draw_set_transform(org, 0.0, esc)
	for k in series.size():
		var pts := ordenados(k)
		if pts.size() > 1:
			polilinea(pts, color_estado(colores[k % colores.size()]))
			comandos += 1
			comandos_series += 1
			puntos_dibujados.append(pts.size())
	draw_set_transform_matrix(Transform2D.IDENTITY)
	texto(Vector2(margen, 12), num(y_max, "%.2f"), color_estado(COLOR_TEXTO), 10)
	texto(Vector2(margen, size.y - margen), num(y_min, "%.2f"), color_estado(COLOR_TEXTO), 10)
	comandos += 2
	return true


func _coste() -> Dictionary:
	# 3 polilíneas de (capacidad − 1) segmentos + marco 4 + cero 1 + 2 etiquetas × 10 car. [I] hasta G-W13-H0.
	return {"instancias": 0, "triangulos": 0, "quads": SERIES_MAX * (capacidad - 1) + 25}
