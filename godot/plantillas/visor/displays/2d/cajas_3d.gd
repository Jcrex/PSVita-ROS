extends "res://comun/visor/display_ros_2d.gd"
## Cajas 3D (V10; doc 36a §4.8.5; sentencia W13 D12): detecciones 3D como cajas de alambre SUPERPUESTAS al 3D
## (`en_pantalla`): las 12 aristas de cada caja proyectadas con la cámara del visor y pintadas en UN
## `draw_multiline_colors` (H17), idéntico en PC y Vita (no hay líneas 3D sin *shaders*: no se ocultan tras el
## robot, `docs/31` §3). Etiqueta «clase 87%» en el centro con TextoSuperpuesto (D11; tope de 40 glifos en la Vita).
##   PC   : `vision_msgs/Detection3DArray` directo (FIABLE, profundidad 1; 1 detección ≈ 505 B), `bbox.center` (Pose)
##          y `bbox.size` (m) en `header.frame_id`; la mejor hipótesis.
##   Vita : `<p>/detecciones3d` (Float32 BE 5 Hz; cab. común + [clase, score, x, y, z, yaw, sx, sy, sz]·n, n ≤ 12) en
##          el marco fijo + `<p>/det_clases` (ClasesDeteccion).
## Dato intermedio común: Array de [PackedVector3Array 8 esquinas (ejes Godot, marco del mensaje), etiqueta (String o
## índice), score]. Reproyección a ≤ `hz_reproyeccion` (20 Hz), no cada fotograma (12 cajas × 8 `unproject`).
## Cupo `resto_2d`: 12 *quads* por caja (una por arista); en la Vita, ⌊cupo / 12⌋ cajas.

const Clases = preload("res://comun/visor/clases_deteccion.gd")
const Prim = preload("res://comun/visor/primitivas_viz.gd")
const Vc1 = preload("res://comun/ros/vc1.gd")
## Aristas de la caja (índices de esquina; esquina k = signos de x, y, z por bits 0, 1, 2).
const ARISTAS := [0, 1, 2, 3, 4, 5, 6, 7, 0, 2, 1, 3, 4, 6, 5, 7, 0, 4, 1, 5, 2, 6, 3, 7]

@export var umbral_score := 0.3
@export var max_cajas := 12
@export var hz_reproyeccion := 20.0
@export var etiquetas := true
@export var max_car := 8
@export var topic_vita_clases := "det_clases"

var clases = Clases.new()
var cajas_dibujadas := 0
var quads_dibujados := 0
var _cajas := []
var _claves_texto := {}
var _t_redibujo := 0
var _cambios_clases := 0


static func nombre_display() -> String:
	return "Cajas3D"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["vision_msgs/msg/Detection3DArray"])


func _init() -> void:
	capa = "resto_2d"
	en_pantalla = true
	tipo = "vision_msgs/msg/Detection3DArray"
	topic_vita = "detecciones3d"
	tipo_vita = "std_msgs/msg/Float32MultiArray"
	hz = 10.0
	hz_vita = 5.0
	caducidad_s = 1.0


func conectar(v) -> void:
	if fiabilidad == Canal.AUTO and not (v.usa_compactos() and topic_vita != ""):
		fiabilidad = Canal.FIABLE                       # directo: no cabe en 488 B (doc 36 §6)
		profundidad = 1
	super.conectar(v)
	if canal.compacto and canal.abierto() and topic_vita_clases != "":
		clases.abrir(v, topic_vita_clases)


func desconectar() -> void:
	clases.cerrar()
	_quitar_textos()
	super.desconectar()


## Caja (centro en ejes Godot, tamaño ROS) → 8 esquinas en ejes Godot.
static func esquinas(t: Transform3D, tam_ros: Vector3) -> PackedVector3Array:
	var e := Vector3(absf(tam_ros.y), absf(tam_ros.z), absf(tam_ros.x)) * 0.5   # ROS X = −Z, Y = −X, Z = +Y
	var out := PackedVector3Array()
	for k in 8:
		out.append(t * Vector3(e.x if k & 1 else -e.x, e.y if k & 2 else -e.y, e.z if k & 4 else -e.z))
	return out


func _procesar(msg):
	var cajas := []
	for d in msg.detections:
		var etiqueta := String(d.get_member("id"))
		var score := 1.0
		var primera := true
		for r in d.results:
			var h = r.hypothesis
			if primera or float(h.score) > score:
				etiqueta = String(h.class_id)
				score = float(h.score)
				primera = false
		var s = d.bbox.size
		var tam := Vector3(s.x, s.y, s.z)
		if score >= umbral_score and tam.is_finite():
			var t := Prim.pose_godot(d.bbox.center)
			if t.origin.is_finite():
				cajas.append([esquinas(t, tam), etiqueta, score])
	cajas.sort_custom(func(a, b): return a[2] > b[2])
	return cajas.slice(0, max_cajas)


func _procesar_compacto(msg):
	var cajas := []
	for e in Vc1.leer_det3d(msg.data):
		if e[1] < umbral_score or cajas.size() >= max_cajas:
			continue
		var t := Transform3D(Basis(Vector3.UP, e[5]), rclgd.ros_to_godot_vector(Vector3(e[2], e[3], e[4])))
		cajas.append([esquinas(t, Vector3(e[6], e[7], e[8])), int(e[0]), float(e[1])])
	return cajas


func _pintar(cajas) -> void:
	_cajas = cajas
	_poner_textos()
	queue_redraw()


func _process(dt: float) -> void:
	super._process(dt)
	clases.bombear()
	if clases.cambios != _cambios_clases:
		_cambios_clases = clases.cambios
		_poner_textos()
	var ahora := Time.get_ticks_msec()
	if visible and not _cajas.is_empty() and ahora - _t_redibujo >= 1000.0 / maxf(hz_reproyeccion, 0.1):
		_t_redibujo = ahora
		queue_redraw()                                  # la cámara se mueve: reproyectar


func _tope_cajas() -> int:
	var tope := max_cajas
	if visor != null and visor.en_vita:
		tope = mini(tope, cupo / 12)
	return tope


func _etiqueta(e) -> String:
	return e if e is String else clases.nombre(int(e))


func _poner_textos() -> void:
	var t = visor.texto if visor != null else null
	var vistas := {}
	if t != null and etiquetas:
		for i in mini(_cajas.size(), _tope_cajas()):
			var c: Array = _cajas[i]
			var centro := Vector3.ZERO
			for p in (c[0] as PackedVector3Array):
				centro += p
			var k := "cajas3d/%s/%d" % [name, i]
			t.poner(k, marco * (centro / 8.0), "%s %d%%" % [_etiqueta(c[1]).left(max_car), roundi(c[2] * 100.0)],
					Clases.color_clase(_etiqueta(c[1])))
			vistas[k] = true
	for k in _claves_texto:
		if not vistas.has(k) and t != null:
			t.quitar(k)
	_claves_texto = vistas


func _quitar_textos() -> void:
	var t = visor.texto if visor != null else null
	if t != null:
		for k in _claves_texto:
			t.quitar(k)
	_claves_texto = {}


func _caducar() -> void:
	super._caducar()
	_quitar_textos()


func _camara() -> Camera3D:
	if visor != null and visor.camara != null:
		return visor.camara
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


func _draw() -> void:
	cajas_dibujadas = 0
	quads_dibujados = 0
	var cam := _camara()
	if cam == null or _cajas.is_empty():
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in mini(_cajas.size(), _tope_cajas()):
		var c: Array = _cajas[i]
		var p2 := PackedVector2Array()
		var detras := false
		for p in (c[0] as PackedVector3Array):
			var w := marco * p
			if cam.is_position_behind(w):
				detras = true
				break
			p2.append(cam.unproject_position(w))
		if detras:
			continue
		var col := Clases.color_clase(_etiqueta(c[1]))
		for a in range(0, ARISTAS.size(), 2):
			pts.append(p2[ARISTAS[a]])
			pts.append(p2[ARISTAS[a + 1]])
			cols.append(col)
		cajas_dibujadas += 1
		quads_dibujados += 12
	if not pts.is_empty():
		draw_multiline_colors(pts, cols, -1.0)


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 12 * max_cajas}
