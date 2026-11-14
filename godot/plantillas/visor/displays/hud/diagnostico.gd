extends "res://comun/visor/display_ros_hud.gd"
## Diagnóstico (doc 36a §4.8.1, ficha hmi#7; tarea V6): `diagnostic_msgs/msg/DiagnosticArray` en la pestaña
## Diagnóstico, como rqt_robot_monitor: cuadro de color + nivel + nombre + mensaje, de PEOR a mejor; cada fila pasa a
## STALE si lleva `caducidad_fila_s` (10 s, `timeline.py:161-163`) sin noticias; filtro «solo problemas».
##
## PC: `/diagnostics` directo (fiable, profundidad 1: no cabe en un datagrama best effort; doc 36 §6).
## Vita: relay `<p>/diagnostics` (VC/1 rev. 2, módulo `diag`) = el MISMO tipo con UN estado por mensaje, ≤ 3 pares,
## textos ≤ 40 car.; primero los que cambian y repaso a 1 Hz por estado, best effort ≤ 10 Hz. Por eso el canal
## entrega TODOS los mensajes (`coalescer = false`): cada uno trae una fila distinta.
##
## Presupuesto (⚖ D6): pestaña Diagnóstico = **8 filas × 30 *quads*** = 240: cuadro de color (1) + texto ≤ 29
## caracteres [decisión V6: el «× 30 caracteres» de D6 más el cuadro daba 248 > 240, así que el cuadro entra en los
## 30]. «Solo problemas» por defecto en la Vita. Mismos números en el PC. Gate G-W13-H0 antes de fijar filas.
##
## Nivel: `byte` en ROS 2 (0 OK, 1 WARN, 2 ERROR, 3 STALE); según el binding llega como entero o como bytes [I] →
## `_nivel()` defensivo. datos = true (las filas viven en `filas`).

const TEXTO := ["OK", "WARN", "ERROR", "STALE"]
const MAX_FILAS_GUARDADAS := 64                # memoria: nombres distintos que se recuerdan (el más viejo sale)

@export var max_filas := 8
@export var ancho_max := 30                    # quads por fila: cuadro (1) + texto (ancho_max − 1)
@export var caducidad_fila_s := 10.0
@export var solo_problemas := false            # en la Vita se fuerza a true (D6)
@export var alto_fila := 14.0

var filas := {}                                # nombre -> [nivel, mensaje, t_ms]
var _proxima_caducidad := -1                   # ms en que alguna fila pasará a STALE (-1 = ninguna)


static func nombre_display() -> String:
	return "Diagnostico"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["diagnostic_msgs/msg/DiagnosticArray"])


func _init() -> void:
	topic = "/diagnostics"
	tipo = "diagnostic_msgs/msg/DiagnosticArray"
	topic_vita = "diagnostics"
	tipo_vita = "diagnostic_msgs/msg/DiagnosticArray"
	caducidad_s = 0.0                          # caduca por fila, no el widget entero


func conectar(v) -> void:
	canal.coalescer = false                    # cada estado del relay llega en su mensaje
	canal.max_pendientes = 32
	if v.en_vita:
		solo_problemas = true
	# Directo (PC, o Vita sin relay): fiable y profundidad 1 (doc 36 §6). Por el relay: best effort (AUTO).
	if fiabilidad == 0 and not (v.usa_compactos() and topic_vita != ""):
		fiabilidad = 2
		profundidad = 1
	super.conectar(v)


static func _nivel(l) -> int:
	if l is PackedByteArray:
		return int(l[0]) if l.size() > 0 else 3
	if l is String:
		return l.unicode_at(0) if l.length() > 0 else 3
	return int(l)


func _procesar(msg):
	var ahora := Time.get_ticks_msec()
	for st in msg.get_member("status"):
		var nombre := String(st.get_member("name"))
		if not filas.has(nombre) and filas.size() >= MAX_FILAS_GUARDADAS:
			_olvidar_la_mas_vieja()
		filas[nombre] = [clampi(_nivel(st.get_member("level")), 0, 3), String(st.get_member("message")), ahora]
	return true                                # _pintar → _draw recalcula la próxima caducidad


func _olvidar_la_mas_vieja() -> void:
	var vieja := ""
	var t := 1 << 62
	for k in filas:
		if filas[k][2] < t:
			t = filas[k][2]
			vieja = k
	filas.erase(vieja)


## Las filas caducan sin que llegue nada: redibujar cuando toque (la próxima la calcula `filas_visibles`).
func _process(dt: float) -> void:
	super._process(dt)
	if _proxima_caducidad >= 0 and Time.get_ticks_msec() >= _proxima_caducidad:
		_proxima_caducidad = -1
		queue_redraw()


## Nivel efectivo de una fila: STALE (3) si lleva más de `caducidad_fila_s` sin noticias.
func nivel_fila(nombre: String, ahora: int) -> int:
	var f: Array = filas[nombre]
	if caducidad_fila_s > 0.0 and ahora - int(f[2]) > caducidad_fila_s * 1000.0:
		return 3
	return int(f[0])


## Nombres a pintar: de peor a mejor (y por nombre a igualdad), sin los OK si `solo_problemas`, ≤ max_filas.
func filas_visibles() -> Array:
	var ahora := Time.get_ticks_msec()
	var lista := []
	_proxima_caducidad = -1
	for k in filas:
		var n := nivel_fila(k, ahora)
		var t_cad := int(filas[k][2]) + int(caducidad_fila_s * 1000.0) + 1
		if caducidad_fila_s > 0.0 and t_cad > ahora and (_proxima_caducidad < 0 or t_cad < _proxima_caducidad):
			_proxima_caducidad = t_cad
		if solo_problemas and n == 0:
			continue
		lista.append([n, k])
	lista.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	return lista.slice(0, max_filas)


func _dibujar() -> bool:
	var vis := filas_visibles()
	if vis.is_empty():
		texto(Vector2(4, alto_fila), "diag: sin problemas" if (solo_problemas and not filas.is_empty()) else "diag ...",
				color_estado(COLOR_OK if not filas.is_empty() else COLOR_CADUCADO), ancho_max - 1)
		return true
	var cuadro := [COLOR_OK, COLOR_AVISO, COLOR_ERROR, Paleta.STALE]       # STALE: el azul de rqt, solo en el cuadro
	var letra := [COLOR_TEXTO, COLOR_AVISO, COLOR_ERROR, COLOR_CADUCADO]   # texto legible (revisión V1: gris, no STALE)
	var y := alto_fila
	for f in vis:
		var n: int = f[0]
		rect(Rect2(2, y - 10, 10, 10), cuadro[n])
		texto(Vector2(16, y), "%s %s: %s" % [TEXTO[n], f[1], filas[f[1]][1]], letra[n], ancho_max - 1)
		y += alto_fila
	return true


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": max_filas * ancho_max}
