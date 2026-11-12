extends "res://comun/robots/base_mecanum.gd"

const BrazoTrajectory = preload("res://comun/robots/brazo_trajectory.gd")

const RUEDAS := ["robot_front_left_wheel_joint", "robot_front_right_wheel_joint",
	"robot_back_left_wheel_joint", "robot_back_right_wheel_joint"]

var nombres_brazo := PackedStringArray()
var _pos_brazo := PackedFloat64Array()
var _obj_brazo := PackedFloat64Array()
var _modelo: Node3D
var _brazo: Node


func inicializar_modelo(config: Dictionary) -> void:
	nombres_brazo = PackedStringArray(config.get("arm_joints", []))
	_pos_brazo.resize(nombres_brazo.size())
	_pos_brazo.fill(0.0)
	_obj_brazo = _pos_brazo.duplicate()
	_modelo = get_node_or_null("Modelo")


func configurar_ros(nombre: String, espacio: String, transporte: String) -> int:
	var err := super.configurar_ros(nombre, espacio, transporte)
	if err == OK:
		_brazo = BrazoTrajectory.new()
		_brazo.contexto = contexto
		_brazo.robot = self
		add_child(_brazo)
	return err


func nombres_joints() -> PackedStringArray:
	var n := PackedStringArray(RUEDAS)
	n.append_array(nombres_brazo)
	return n


func fijar_objetivos_joints(nombres, posiciones) -> void:
	if emergencia:
		return
	for i in mini(nombres.size(), posiciones.size()):
		var indice := nombres_brazo.find(nombres[i])
		if indice >= 0:
			_obj_brazo[indice] = posiciones[i]


func posiciones_joints(nombres: PackedStringArray) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	for nombre in nombres:
		var rueda := RUEDAS.find(nombre)
		var brazo := nombres_brazo.find(nombre)
		if rueda >= 0:
			r.append(angulos_ruedas[rueda])
		elif brazo >= 0:
			r.append(_pos_brazo[brazo])
		else:
			r.append(0.0)
	return r


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	for i in _pos_brazo.size():
		_pos_brazo[i] = move_toward(_pos_brazo[i], _obj_brazo[i], 1.5 * dt)
	if _modelo != null and _modelo.has_method("set_joints"):
		_modelo.call("set_joints", nombres_joints(), posiciones_joints(nombres_joints()))
