extends Node3D
## Robot importado desde un URDF con tools/urdf2godot/urdf2godot.py (modo solo visual/cinemático).
##
## Los nodos conservan los nombres del URDF: cada joint es un Node3D con metadata `urdf_*` (tipo, eje,
## origen, límites, mimic). Por eso un /joint_states de ROS se aplica tal cual, por nombre.
## Todo lo que cuelga de `RosFrame` está en ejes de ROS (REP-103, Z arriba); `RosFrame` gira a Godot.
## Sin física: funciona igual en el PC y en la Vita (Jolt está desactivado en el port, detect.py:83).

## Si es true, las posiciones se recortan a los límites del URDF (revolute/prismatic).
@export var respetar_limites := true

var _joints := {}        # nombre URDF -> Node3D del joint
var _mimicos := []       # joints con <mimic>
var _base: Node3D


func _ready() -> void:
	_base = get_node("RosFrame/Base")
	for n in find_children("*", "Node3D", true, false):
		if n.has_meta("urdf_joint"):
			_joints[n.get_meta("urdf_joint")] = n
			if n.has_meta("urdf_mimic"):
				_mimicos.append(n)


## Nombres de los joints que se pueden mover (no fijos), en el orden del URDF.
func nombres_joints_movibles() -> PackedStringArray:
	var r := PackedStringArray()
	for nombre in _joints:
		var t: String = _joints[nombre].get_meta("urdf_type")
		if t != "fixed" and not _joints[nombre].has_meta("urdf_mimic"):
			r.append(nombre)
	return r


## Pone un joint en la posición `q` (rad para revolute/continuous, m para prismatic).
func set_joint(nombre: String, q: float) -> void:
	var j: Node3D = _joints.get(nombre)
	if j == null:
		return
	_aplicar(j, q)


## Aplica un sensor_msgs/JointState (o dos arrays paralelos): nombres -> posiciones.
func set_joints(nombres, posiciones) -> void:
	var n := mini(nombres.size(), posiciones.size())
	for i in n:
		var j: Node3D = _joints.get(nombres[i])
		if j != null:
			_aplicar(j, posiciones[i])
	for j in _mimicos:
		var maestro: Node3D = _joints.get(j.get_meta("urdf_mimic"))
		if maestro != null and maestro.has_meta("q"):
			_aplicar(j, maestro.get_meta("q") * j.get_meta("urdf_mimic_k") + j.get_meta("urdf_mimic_off"))


## Pose del link raíz en el marco del mundo de ROS (p. ej. odom -> pelvis): posición en m y cuaternión de ROS.
func set_base_pose_ros(posicion: Vector3, orientacion: Quaternion) -> void:
	_base.transform = Transform3D(Basis(orientacion.normalized()), posicion)


func _aplicar(j: Node3D, q: float) -> void:
	var tipo: String = j.get_meta("urdf_type")
	if respetar_limites and j.has_meta("urdf_lower") and j.get_meta("urdf_lower") < j.get_meta("urdf_upper"):
		q = clampf(q, j.get_meta("urdf_lower"), j.get_meta("urdf_upper"))
	j.set_meta("q", q)
	var origen: Transform3D = j.get_meta("urdf_origin")
	var eje: Vector3 = j.get_meta("urdf_axis").normalized()
	match tipo:
		"revolute", "continuous":
			j.transform = origen * Transform3D(Basis(eje, q), Vector3.ZERO)
		"prismatic":
			j.transform = origen * Transform3D(Basis.IDENTITY, eje * q)
