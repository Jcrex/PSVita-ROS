extends "res://comun/visor/display_ros_2d.gd"
## Pose en planta (V3; doc 36a §4.2.3 y §4.3.1): triángulo orientado por el yaw (patrón validado en
## `godot/g6-hmi/main.gd:182` y en el minimapa del G1) y, opcional, rastro con `draw_polyline`.
##   PC   : `topic` con `geometry_msgs/PoseStamped` o `nav_msgs/Odometry` (también PoseWithCovarianceStamped:
##          se usa `pose.pose`) → `_procesar`.
##   Vita : `<p>/pose2d` (Float32MultiArray `[x, y, yaw, vx, vy, wz]`, 40 B, 30 Hz, de `/odom`) →
##          `VitaRelay.pose2d`. Odometry son 724 B y no cabe en best effort (docs/27:80).
## Dato intermedio común: Vector3(x, y, yaw) en metros y radianes del marco del mensaje (compacto: marco fijo).
## Planta 2D = defecto en la Vita para lo que vive en el suelo (D7). Cupo: 1 + `max_rastro` *quads*.

const VitaRelay = preload("res://comun/vita_relay.gd")

@export var lado_px := 10.0
@export var color := Color(1.0, 0.1, 0.0)
@export var max_rastro := 100                           # 0 = sin rastro
@export var tol_pos := 0.1                              # m: el rastro solo crece si la pose se aleja esto

var pose := Vector3.ZERO                                 # último dato (x, y, yaw)
var recibida := false
var _rastro := PackedVector2Array()                      # en metros
var _rastro_px := PackedVector2Array()


static func nombre_display() -> String:
	return "Pose"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["geometry_msgs/msg/PoseStamped", "nav_msgs/msg/Odometry",
			"geometry_msgs/msg/PoseWithCovarianceStamped"])


func _init() -> void:
	hz = 30.0
	topic_vita = "pose2d"
	tipo_vita = "std_msgs/msg/Float32MultiArray"


func _procesar(msg):
	var p = msg.pose
	if "covariance" in p:                                 # Odometry / PoseWithCovariance(Stamped): pose.pose
		p = p.pose
	var o = p.orientation
	var x: float = o.x
	var y: float = o.y
	var z: float = o.z
	var w: float = o.w
	var r := Vector3(p.position.x, p.position.y, atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z)))
	return r if r.is_finite() else null                   # NaN/Inf (EKF sin iniciar): ignorar (T2, revisión V1)


func _procesar_compacto(msg):
	var d: Dictionary = VitaRelay.pose2d(msg)
	if d.is_empty():
		return null
	var r := Vector3(d["pos"].x, d["pos"].y, d["yaw"])
	return r if r.is_finite() else null


func _pintar(d) -> void:
	pose = d
	recibida = true
	var q := Vector2(pose.x, pose.y)
	var limite := max_rastro
	if visor != null and visor.en_vita:
		limite = mini(max_rastro, maxi(cupo - 1, 0))        # cupo en quads: 1 del triángulo + el rastro
	if limite > 0 and (_rastro.is_empty() or _rastro[-1].distance_to(q) > tol_pos):
		_rastro.append(q)
		while _rastro.size() > limite:
			_rastro.remove_at(0)
	_rastro_px.resize(_rastro.size())
	for i in _rastro.size():
		_rastro_px[i] = px(_rastro[i])
	queue_redraw()


func _draw() -> void:
	if not recibida:
		return
	if _rastro_px.size() > 1:
		draw_polyline(_rastro_px, Color(color, 0.6), 2.0)
	var c := px(Vector2(pose.x, pose.y))
	var f := Vector2(cos(pose.z), -sin(pose.z))           # yaw de ROS en la planta (y de pantalla hacia abajo)
	var l := Vector2(-f.y, f.x)
	draw_colored_polygon(PackedVector2Array([c + f * lado_px, c - f * lado_px * 0.6 + l * lado_px * 0.6,
			c - f * lado_px * 0.6 - l * lado_px * 0.6]), color)


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 1 + max_rastro}
