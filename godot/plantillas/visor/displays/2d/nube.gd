extends "res://comun/visor/display_ros_2d.gd"
## Nube (V10; doc 36a §4.5.3; sentencia W13 D5): nube de puntos en la planta 2D, color por banda de altura (16
## colores, como el «Axis color» de RViz). UN lote por trozo (`canvas_item_add_triangle_array`, un triángulo por
## punto), redibujado solo al llegar datos (H16–H17).
##   Vita : `<p>/nube2d` (Int16 cm, best effort, 5 Hz × ≤ 3 trozos de ≤ 76 puntos, vóxel 10 cm, ≤ 228 puntos, YA en
##          el marco fijo). Todos los trozos cuentan (`coalescer = false`). Un `seq` nuevo empieza nube; la anterior
##          se sigue viendo hasta que la nueva está completa, o hasta que empieza otra (entonces se enseña lo que
##          llegó: un trozo perdido no deja la nube congelada).
##   PC   : `sensor_msgs/PointCloud2` directo: x, y, z FLOAT32 por `fields[].offset` con `to_float32_array()` (sin
##          `decode_float` por punto si todo está alineado a 4 B), NaN/Inf fuera, diezmado uniforme hasta
##          `max_puntos_pc`; color por la z del marco del sensor. *Big endian* se rechaza (T28) [decisión V10].
## Dato intermedio común: [seq, trozo, n_trozos, PackedVector2Array vértices (px), PackedColorArray].
## Cupo `sensores_2d` (doc 36 §7.2): ≤ 228 *quads* (= puntos); en la Vita se dibujan como mucho `cupo` puntos.

const Vc1 = preload("res://comun/ros/vc1.gd")

@export var alturas := Vector2(-0.2, 2.0)     # z (m) del primer y del último color
@export var lado_px := 2.0
@export var max_puntos_pc := 4000

var puntos_dibujados := 0
var trozos_recibidos := 0
var nubes_completas := 0
var us_ultimo_trozo := 0                      # µs de `_procesar_compacto` del último trozo (gate V10: ≤ 2 ms)
var us_max_trozo := 0
var rechazadas := 0
var motivo := ""
var _lut := PackedColorArray()
var _seq_pend := -1
var _pend := {}                               # trozo → [v, c] de la nube en curso
var _mostrar := {}                            # trozo → [v, c] de la que se ve
var _idx := {}                                # nº de vértices → PackedInt32Array 0..n-1 (caché)


static func nombre_display() -> String:
	return "Nube"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["sensor_msgs/msg/PointCloud2"])


func _init() -> void:
	tipo = "sensor_msgs/msg/PointCloud2"
	topic_vita = "nube2d"
	tipo_vita = "std_msgs/msg/Int16MultiArray"
	hz = 10.0
	caducidad_s = 2.0
	for k in 16:
		_lut.append(Color.from_hsv(0.66 * (1.0 - k / 15.0), 1.0, 1.0))   # azul (bajo) → rojo (alto)


func conectar(v) -> void:
	if v.usa_compactos() and topic_vita != "":
		canal.coalescer = false                      # cada trozo cuenta
		canal.max_pendientes = 3 * Vc1.MAX_TROZOS_NUBE
	super.conectar(v)


func _color_z(z: float) -> Color:
	var esc := 15.0 / maxf(alturas.y - alturas.x, 0.01)
	return _lut[clampi(int((z - alturas.x) * esc), 0, 15)]


func _tri(v: PackedVector2Array, c: PackedColorArray, k: int, p: Vector2, col: Color) -> void:
	v[3 * k] = p + Vector2(0, -lado_px)
	v[3 * k + 1] = p + Vector2(lado_px, lado_px)
	v[3 * k + 2] = p + Vector2(-lado_px, lado_px)
	c[3 * k] = col
	c[3 * k + 1] = col
	c[3 * k + 2] = col


func _procesar_compacto(msg):
	var t0 := Time.get_ticks_usec()
	var d = msg.data                                   # int16[] llega como PackedInt32Array (T6)
	var cab := Vc1.cabecera(d)
	if cab.is_empty():
		return null
	@warning_ignore("integer_division")
	var n := mini(int(cab.n), (d.size() - 4) / 3)
	var v := PackedVector2Array()
	var c := PackedColorArray()
	v.resize(3 * n)
	c.resize(3 * n)
	var k := px_por_m_local()
	for i in n:
		var b := 4 + 3 * i
		_tri(v, c, i, Vector2(d[b], -d[b + 1]) * k, _color_z(d[b + 2] / 100.0))
	us_ultimo_trozo = Time.get_ticks_usec() - t0
	us_max_trozo = maxi(us_max_trozo, us_ultimo_trozo)
	trozos_recibidos += 1
	return [int(cab.seq), int(cab.trozo), int(cab.n_trozos), v, c]


## px por cm de la planta (cm del relay → px).
func px_por_m_local() -> float:
	return (visor.px_por_m if visor != null else 1.0) / 100.0


func _procesar(msg):
	if bool(msg.is_bigendian):
		return _rechazar("big endian (T28)")
	var off := {}
	for f in msg.fields:
		if String(f.name) in ["x", "y", "z"] and int(f.datatype) == 7:   # FLOAT32
			off[String(f.name)] = int(f.offset)
	if off.size() != 3:
		return _rechazar("sin x, y, z FLOAT32")
	var paso := int(msg.point_step)
	var w := int(msg.width)
	var h := int(msg.height)
	var data: PackedByteArray = msg.data
	var total := w * h
	if paso <= 0 or total <= 0 or data.size() < int(msg.row_step) * (h - 1) + w * paso:
		return _rechazar("tamaños no válidos")
	var salto := maxi(1, ceili(float(total) / maxi(max_puntos_pc, 1)))
	var v := PackedVector2Array()
	var c := PackedColorArray()
	var maximo := ceili(float(total) / salto)
	v.resize(3 * maximo)
	c.resize(3 * maximo)
	var k: float = visor.px_por_m if visor != null else 1.0
	var alineado: bool = paso % 4 == 0 and int(msg.row_step) == w * paso and off.x % 4 == 0 and off.y % 4 == 0 and off.z % 4 == 0
	var f32 := data.to_float32_array() if alineado else PackedFloat32Array()
	var q := paso / 4
	var n := 0
	var i := 0
	while i < total:
		var x: float
		var y: float
		var z: float
		if alineado:
			x = f32[i * q + off.x / 4]
			y = f32[i * q + off.y / 4]
			z = f32[i * q + off.z / 4]
		else:
			@warning_ignore("integer_division")
			var base := (i / w) * int(msg.row_step) + (i % w) * paso
			x = data.decode_float(base + off.x)
			y = data.decode_float(base + off.y)
			z = data.decode_float(base + off.z)
		if is_finite(x) and is_finite(y) and is_finite(z):
			_tri(v, c, n, Vector2(x, -y) * k, _color_z(z))
			n += 1
		i += salto
	v.resize(3 * n)
	c.resize(3 * n)
	return [-1, 0, 1, v, c]


func _rechazar(m: String):
	rechazadas += 1
	motivo = m
	estado = "rechazada: " + m
	return null


func _pintar(t) -> void:
	var seq: int = t[0]
	if seq != _seq_pend:
		if not _pend.is_empty():
			_mostrar = _pend                           # empieza otra nube: lo que llegó de la anterior se ve
		_pend = {}
		_seq_pend = seq
	_pend[t[1]] = [t[3], t[4]]
	if _pend.size() >= int(t[2]):
		_mostrar = _pend
		_pend = {}
		nubes_completas += 1
	queue_redraw()


func _indices(n: int) -> PackedInt32Array:
	if not _idx.has(n):
		var a := PackedInt32Array()
		a.resize(n)
		for i in n:
			a[i] = i
		_idx[n] = a
	return _idx[n]


func _draw() -> void:
	puntos_dibujados = 0
	var tope := cupo if (visor != null and visor.en_vita) else 1 << 30
	var ci := get_canvas_item()
	for k in _mostrar.keys():
		var v: PackedVector2Array = _mostrar[k][0]
		var c: PackedColorArray = _mostrar[k][1]
		var n := mini(v.size() / 3, tope - puntos_dibujados)
		if n <= 0:
			continue
		if n * 3 < v.size():
			v = v.slice(0, 3 * n)
			c = c.slice(0, 3 * n)
		RenderingServer.canvas_item_add_triangle_array(ci, _indices(3 * n), v, c)
		puntos_dibujados += n


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": Vc1.MAX_NUBE}
