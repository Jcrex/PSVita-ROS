extends "res://comun/visor/display_ros_2d.gd"
## Path (V3; doc 36a §4.3.2): `nav_msgs/Path` en la planta 2D como UNA polilínea (`draw_polyline`), transformada
## al marco fijo una vez por mensaje (como RViz).
##   PC   : `topic` (Path) → `_procesar`. Un Path de 100 poses son 7 228 B: no cabe en la Vita (docs/27:67).
##   Vita : `<p>/path_compacto` (Float32MultiArray `[n, x0, y0, …]`, Douglas-Peucker ε 5 cm, ≤ 57 puntos, 476 B,
##          2 Hz; `docker/scripts/vita_relay.py` `empaquetar_path`) → `VitaRelay.path_puntos`.
## Dato intermedio común: PackedVector2Array en METROS del marco del mensaje (compacto: marco fijo).
## Cupo (doc 36 §7.2): ≤ 112 *quads* de «sensores_2d»; en la Vita se dibujan como mucho `cupo` puntos.
## `nav_msgs/Path` no está en el esquema de `visor-ros` (en la Vita no hace falta); en el host con ros2_vita el
## camino estándar queda «sin esquema» hasta V5 (TIPOS_VISOR). Con rclgd en el PC funciona.

const VitaRelay = preload("res://comun/vita_relay.gd")

@export var color := Color(0.1, 1.0, 0.0)               # color por defecto del Path de RViz
@export var ancho_px := 2.0

var puntos_dibujados := 0
var _pts := PackedVector2Array()


static func nombre_display() -> String:
	return "Path"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["nav_msgs/msg/Path"])


func _init() -> void:
	hz = 2.0
	topic_vita = "path_compacto"
	tipo_vita = "std_msgs/msg/Float32MultiArray"


func _procesar(msg):
	var out := PackedVector2Array()
	for ps in msg.poses:
		var p = ps.pose.position
		out.append(Vector2(p.x, p.y))
	return out


func _procesar_compacto(msg):
	return VitaRelay.path_puntos(msg)


func _pintar(pts) -> void:
	var n: int = pts.size()
	if visor != null and visor.en_vita:
		n = mini(n, cupo)
	_pts.resize(n)
	for i in n:
		_pts[i] = px(pts[i])
	puntos_dibujados = n
	queue_redraw()


func _draw() -> void:
	if _pts.size() > 1:
		draw_polyline(_pts, color, ancho_px)


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 112}
