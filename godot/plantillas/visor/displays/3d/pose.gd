extends "res://comun/visor/display_ros_3d.gd"
## Pose 3D (V3; doc 36a §4.2.3): flecha (o ejes) de `PrimitivasViz` en la pose, escalada por `largo` (RViz:
## *Shaft Length* 1 + *Head* 0,3). Una instancia (capa «poses»: HMI 4, Viz 16; D7).
##   PC   : `topic` con `PoseStamped`, `Odometry` o `PoseWithCovarianceStamped` → `_procesar`.
##   Vita : `<p>/pose2d` (`[x, y, yaw, vx, vy, wz]`) → `_procesar_compacto` (z = 0, solo yaw).
## Dato intermedio común: Transform3D (ejes de Godot) de la pose en el marco del mensaje (compacto: marco fijo).
## En la Vita la planta 2D (`displays/2d/pose.gd`) es el defecto (D7); este display cabe si la escena lo pone.

const Prim = preload("res://comun/visor/primitivas_viz.gd")
const VitaRelay = preload("res://comun/vita_relay.gd")

@export_enum("flecha", "ejes") var forma := "flecha"
@export var largo := 1.0
@export var color := Color(1.0, 0.1, 0.0)

var _vis: MeshInstance3D


static func nombre_display() -> String:
	return "Pose3D"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["geometry_msgs/msg/PoseStamped", "nav_msgs/msg/Odometry",
			"geometry_msgs/msg/PoseWithCovarianceStamped"])


func _init() -> void:
	capa = "poses"
	hz = 30.0
	topic_vita = "pose2d"
	tipo_vita = "std_msgs/msg/Float32MultiArray"


func conectar(v) -> void:
	super.conectar(v)
	if cupo > 0 and _vis == null:
		_vis = Prim.instancia(Prim.FLECHA if forma == "flecha" else Prim.EJES, color)
		_vis.visible = false                            # hasta el primer mensaje
		add_child(_vis)                                 # sin owner: no se guarda en la escena (doc 35)


func _procesar(msg):
	var p = msg.pose
	if "covariance" in p:                               # Odometry / PoseWithCovariance(Stamped): pose.pose
		p = p.pose
	return Prim.pose_godot(p)


func _procesar_compacto(msg):
	var d: Dictionary = VitaRelay.pose2d(msg)
	if d.is_empty():
		return null
	var pos: Vector2 = d["pos"]
	var q := Quaternion(Vector3(0, 0, 1), float(d["yaw"]))      # giro en Z de ROS
	return Transform3D(Basis(rclgd.ros_to_godot_quat(q)), rclgd.ros_to_godot_vector(Vector3(pos.x, pos.y, 0.0)))


func _pintar(t) -> void:
	if _vis == null:
		return
	_vis.transform = (t as Transform3D).scaled_local(Vector3.ONE * largo)
	_vis.visible = true


func _coste() -> Dictionary:
	return {"instancias": 1, "triangulos": Prim.TRIANGULOS[Prim.FLECHA if forma == "flecha" else Prim.EJES], "quads": 0}
