extends "res://comun/robots/robot_ros.gd"

const POSE_DEFECTO := {
	"left_hip_pitch_joint": -0.1, "left_knee_joint": 0.3, "left_ankle_pitch_joint": -0.2,
	"right_hip_pitch_joint": -0.1, "right_knee_joint": 0.3, "right_ankle_pitch_joint": -0.2,
}
const MOTORES := [
	"left_hip_pitch_joint", "left_hip_roll_joint", "left_hip_yaw_joint", "left_knee_joint",
	"left_ankle_pitch_joint", "left_ankle_roll_joint", "right_hip_pitch_joint", "right_hip_roll_joint",
	"right_hip_yaw_joint", "right_knee_joint", "right_ankle_pitch_joint", "right_ankle_roll_joint",
	"waist_yaw_joint", "waist_roll_joint", "waist_pitch_joint", "left_shoulder_pitch_joint",
	"left_shoulder_roll_joint", "left_shoulder_yaw_joint", "left_elbow_joint", "left_wrist_roll_joint",
	"left_wrist_pitch_joint", "left_wrist_yaw_joint", "right_shoulder_pitch_joint", "right_shoulder_roll_joint",
	"right_shoulder_yaw_joint", "right_elbow_joint", "right_wrist_roll_joint", "right_wrist_pitch_joint",
	"right_wrist_yaw_joint",
]

var marcha: RefCounted
var _modelo: Node3D
var _nombres := PackedStringArray()
var _posiciones := PackedFloat32Array()


func inicializar_modelo(_config: Dictionary) -> void:
	_modelo = get_node("Modelo")
	_nombres = _modelo.call("nombres_joints_movibles")
	_posiciones.resize(_nombres.size())
	for i in _nombres.size():
		_posiciones[i] = POSE_DEFECTO.get(_nombres[i], 0.0)
	var script_marcha: Script = load("res://marcha.gd")
	marcha = script_marcha.new()
	if not marcha.cargar("res://anim/g1_marcha.json"):
		push_error("No se pudo cargar la marcha del G1")


func _clip() -> String:
	var o := orden_actual
	if o.x > 0.85: return "correr"
	if o.x > 0.05: return "andar"
	if o.x < -0.05: return "atras"
	if o.z > 0.05: return "girar_izq"
	if o.z < -0.05: return "girar_der"
	if o.y > 0.05: return "izquierda"
	if o.y < -0.05: return "derecha"
	return "quieto"


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	if marcha == null:
		return
	marcha.pedir(_clip())
	marcha.avanzar(dt, func(_p): return true)
	var pose: Array = marcha.pose_base()
	var q_local: Quaternion = Quaternion(Vector3(0.0, 0.0, 1.0), -marcha.yaw) * pose[1]
	_modelo.call("set_base_pose_ros", Vector3(0.0, 0.0, pose[0].z), q_local)
	var q_piernas: PackedFloat32Array = marcha.q_joints()
	for i in mini(marcha.joints.size(), q_piernas.size()):
		var indice := _nombres.find(marcha.joints[i])
		if indice >= 0:
			_posiciones[indice] = q_piernas[i]
	_modelo.call("set_joints", _nombres, _posiciones)


func nombres_joints() -> PackedStringArray:
	return _nombres


func posiciones_joints(nombres: PackedStringArray) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	for nombre in nombres:
		var i := _nombres.find(nombre)
		r.append(_posiciones[i] if i >= 0 else 0.0)
	return r


func fijar_motor(indice: int, q: float) -> void:
	if emergencia:
		return
	if indice < 0 or indice >= MOTORES.size():
		return
	var i := _nombres.find(MOTORES[indice])
	if i >= 0:
		_posiciones[i] = q


func sensores_listos(lista: Dictionary) -> void:
	var montajes := {"d435": "d435_link", "mid360": "mid360_link", "imu_pelvis": "imu_in_pelvis", "imu_torso": "imu_in_torso"}
	for nombre in montajes:
		if not lista.has(nombre):
			continue
		var link := _modelo.find_child(montajes[nombre], true, false)
		if link != null:
			var sensor: Node3D = lista[nombre]
			sensor.reparent(link, false)
			sensor.position = Vector3.ZERO
			sensor.basis = Basis.IDENTITY
