extends "res://comun/visor/display_ros_2d.gd"
## PoseArray en planta (V9; doc 36a §4.2.4, V geom#4 → relay `poses`, ⚖ D5): un triángulo por pose en UNA llamada
## `canvas_item_add_triangle_array` (H16–H17), redibujado solo al llegar mensaje.
##   PC   : `geometry_msgs/PoseArray` o `nav2_msgs/ParticleCloud` (la nube de AMCL en Jazzy, con pesos) → `_procesar`.
##   Vita : `<p>/poses` = cabecera común + [x, y, yaw]·n, n ≤ 36 diezmado, 2 Hz (464 B) → `_procesar_compacto`.
##          PoseArray directo solo cabe con n ≤ 8 (28 + 56·n B): por eso el relay.
## Dato intermedio común: PackedVector3Array (x, y, yaw) en m y rad del marco del mensaje (en el compacto, `frame_id`
## o el marco fijo). Cupo: 100 *quads* («poses y odometría ≤ 100», doc 36 §7.2); se dibujan como mucho `cupo` poses.

const VC1 = preload("res://comun/ros/vc1.gd")

@export var lado_px := 6.0
@export var color := Color(1.0, 0.1, 0.0)
@export var max_poses := 100

var poses_dibujadas := 0                         # pruebas y HUD
var datos := PackedVector3Array()                # último dato intermedio
var _v := PackedVector2Array()
var _c := PackedColorArray()
var _idx := PackedInt32Array()


static func nombre_display() -> String:
	return "PoseArray"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["geometry_msgs/msg/PoseArray", "nav2_msgs/msg/ParticleCloud"])


func _init() -> void:
	hz = 2.0
	tipo_vita = "std_msgs/msg/Float32MultiArray"


static func _yaw(o) -> float:
	return atan2(2.0 * (o.w * o.z + o.x * o.y), 1.0 - 2.0 * (o.y * o.y + o.z * o.z))


func _procesar(msg):
	var lista = msg.poses if "poses" in msg else msg.particles
	var out := PackedVector3Array()
	for e in lista:
		var p = e.pose if "pose" in e else e      # ParticleCloud: particles[i].pose (+ weight)
		var q := Vector3(p.position.x, p.position.y, _yaw(p.orientation))
		if q.is_finite():                          # T2
			out.append(q)
	return out


func _procesar_compacto(msg):
	if not ("data" in msg):
		return null
	var d: PackedFloat32Array = msg.data
	if VC1.cabecera(d).is_empty():
		return null
	return VC1.leer_poses(d)                       # n ≤ 36 cabe en un trozo: sin ensamblar


func _pintar(poses) -> void:
	datos = poses
	var n := mini(poses.size(), max_poses)
	if cupo > 0:
		n = mini(n, cupo)
	_v.resize(3 * n)
	_c.resize(3 * n)
	for i in n:
		var q: Vector3 = poses[i]
		var p := px(Vector2(q.x, q.y))
		var f := Vector2(cos(q.z), -sin(q.z)) * lado_px
		var l := Vector2(-f.y, f.x) * 0.5
		_v[3 * i] = p + f
		_v[3 * i + 1] = p - f * 0.5 + l
		_v[3 * i + 2] = p - f * 0.5 - l
		_c[3 * i] = color
		_c[3 * i + 1] = color
		_c[3 * i + 2] = color
	if _idx.size() != _v.size():
		_idx.resize(_v.size())
		for k in _idx.size():
			_idx[k] = k
	poses_dibujadas = n
	queue_redraw()


func _draw() -> void:
	if _v.size() >= 3:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx, _v, _c)


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": mini(max_poses, 100)}
