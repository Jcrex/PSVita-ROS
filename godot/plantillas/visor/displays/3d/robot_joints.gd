extends "res://comun/visor/display_ros_3d.gd"
## RobotModel (V3; doc 36a §4.3.5): escena del robot horneada en el PC por `tools/urdf2godot` (ADR 0009) +
## `sensor_msgs/JointState` → `set_joints(nombres, posiciones)` (cinemática local, sin TF de links; p. ej.
## `godot/g1-unitree/robot/urdf_robot.gd:80`). Capa «robot» (40 instancias; D7).
##   PC   : `topic` (JointState) → `_procesar`. La base se coloca con TF (`frame_id`, p. ej. "base_link").
##   Vita : `<p>/joints` (Float32MultiArray en el orden de `<p>/joints_orden`, String F+TL; 25 Hz, ≤ 118 juntas)
##          → `_procesar_compacto`. JointState del G1 son 1 668 B y no cabe (docs/27:76-77). Sin TF en la Vita
##          (sin TfLigero), la base se coloca con `<p>/pose2d` (x, y, yaw en el suelo); con TfLigero, ver «V9».
## Dato intermedio común: [PackedStringArray nombres, posiciones (PackedFloat64Array o PackedFloat32Array)].
##
## Decisiones de V3 (las más conservadoras):
##   - Callbacks auxiliares (`joints_orden`, `pose2d`) con métodos del display, no lambdas (en ros2_vita una
##     lambda como callback está sin comprobar, ficha geom#16 [I]).
##   - `pose2d` solo coloca el robot si `visor.tf` es null (si hay TF del PC, manda TF y no se suma dos veces).
##     Mueve el nodo del robot en el plano (conserva la altura propia de su base).
##   - Sin `escena_robot`: se dibujan unos EJES (1 instancia) en la base para ver al menos dónde está.
##   - `instancias` (40) es lo que se reserva; si la escena tiene más mallas se avisa una vez (no se recorta).
## V9 (TfLigero, doc 36 §2.9.6): los links de `escena_robot` se registran en `visor.tf` (fuente «por nodo», 0 B) y,
##   si `frame_id` es un marco (p. ej. "base_link" = `VisorRos.marco_base`), la base se coloca con
##   `visor.transformada(frame_id)` en cada pose2d (el display entero, no el hijo: así no se suma dos veces). Con
##   `frame_id` vacío o el fijo, pose2d mueve el hijo como en V3.

const Prim = preload("res://comun/visor/primitivas_viz.gd")
const VitaRelay = preload("res://comun/vita_relay.gd")

@export var escena_robot: PackedScene                 # LOD de la Vita o del PC (se instancia SIN owner, doc 35)
@export var link_raiz := "base_link"
@export var instancias := 40                          # cupo pedido en la capa «robot»

var robot: Node3D                                     # la escena instanciada (o los ejes de respaldo)
var orden := PackedStringArray()                      # nombres de <p>/joints_orden (camino compacto)
var poses_base := 0                                   # pose2d aplicadas (pruebas)
var _subs: Array = []                                 # suscripciones auxiliares: guardarlas las mantiene vivas


static func nombre_display() -> String:
	return "RobotModel"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["sensor_msgs/msg/JointState"])


func _init() -> void:
	capa = "robot"
	hz = 25.0
	frame_id = "base_link"
	topic_vita = "joints"
	tipo_vita = "std_msgs/msg/Float32MultiArray"


func conectar(v) -> void:
	super.conectar(v)
	if cupo <= 0:
		return
	if robot == null:
		if escena_robot != null:
			robot = escena_robot.instantiate()
			var mallas := robot.find_children("*", "MeshInstance3D", true, false).size()
			if v.en_vita and mallas > cupo:
				push_warning("RobotModel %s: la escena tiene %d mallas y el cupo «robot» es %d" % [name, mallas, cupo])
		else:
			robot = Prim.instancia(Prim.EJES)
			robot.scale = Vector3.ONE * 0.5
		add_child(robot)                                  # sin owner: no se guarda en la escena (doc 35)
		if escena_robot != null and v.has_method("es_tf_ligero") and v.es_tf_ligero():
			v.tf.registrar_robot(robot, link_raiz)        # V9: marcos de los links sin tráfico (D3)
	if estado == "ok" and canal.compacto:
		var n = v.contexto.nodo
		var pre: String = v.prefijo_compacto.trim_suffix("/")
		_subs.append(n.create_subscription(pre + "/joints_orden", "std_msgs/msg/String", _al_orden,
				v.contexto.qos(false, 1, true)))
		_subs.append(n.create_subscription(pre + "/pose2d", "std_msgs/msg/Float32MultiArray", _al_pose2d,
				v.contexto.qos(true, 1, false)))


func desconectar() -> void:
	_subs.clear()
	super.desconectar()


func _al_orden(m) -> void:
	orden = String(m.data).split(",", false)


func _al_pose2d(m) -> void:
	if visor == null or robot == null:
		return
	var ligero: bool = visor.has_method("es_tf_ligero") and visor.es_tf_ligero()
	if visor.tf != null and not ligero:
		return                                            # RosTfListener: manda TF
	if ligero and frame_id != "" and frame_id != visor.marco_fijo:
		# V9: el mismo valor que mete VisorRos (idempotente; el orden de los dos callbacks no está garantizado).
		visor.tf.desde_pose2d(m.data, visor.marco_mundo_pose2d(), visor.marco_base)
		var tb = visor.transformada(frame_id)
		if tb != null:
			marco = tb
			transform = tb
			poses_base += 1
		return
	var d: Dictionary = VitaRelay.pose2d(m)
	if d.is_empty():
		return
	var pos: Vector2 = d["pos"]
	if not (pos.is_finite() and is_finite(float(d["yaw"]))):
		return
	var q := Quaternion(Vector3(0, 0, 1), float(d["yaw"]))
	var t := Transform3D(Basis(rclgd.ros_to_godot_quat(q)), rclgd.ros_to_godot_vector(Vector3(pos.x, pos.y, 0.0)))
	t.origin.y = robot.transform.origin.y                 # el plano: la altura de la base es la de la escena
	# Conservar la escala propia (revisión V1: los EJES de respaldo van a 0,5 y `transform = t` los dejaba a 1).
	robot.transform = t.scaled_local(robot.scale)
	poses_base += 1


func _procesar(msg):
	return [PackedStringArray(msg.name), msg.position]


func _procesar_compacto(msg):
	if orden.is_empty():
		return null                                       # sin orden aún no se sabe qué junta es cada valor
	return [orden, msg.data]


func _pintar(d) -> void:
	if robot != null and robot.has_method("set_joints"):
		robot.set_joints(d[0], d[1])


func _coste() -> Dictionary:
	if escena_robot == null:
		return {"instancias": 1, "triangulos": Prim.TRIANGULOS[Prim.EJES], "quads": 0}
	return {"instancias": instancias, "triangulos": 12000, "quads": 0}
