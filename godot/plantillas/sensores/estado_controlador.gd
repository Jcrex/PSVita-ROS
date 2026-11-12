extends "res://comun/ros/sensor_base.gd"

var _msg: RosMsg
var _nombres := PackedStringArray()


func _init() -> void:
	topic = "/joint_trajectory_controller/controller_state"
	tipo = "control_msgs/msg/JointTrajectoryControllerState"
	hz = 10.0
	hz_vita = 5.0
	hz_xrce = 2.0
	best_effort = false


func _sensor_listo() -> void:
	_msg = RosMsg.from_type(tipo)
	if robot.has_method("nombres_joints"):
		var todos: PackedStringArray = robot.call("nombres_joints")
		for nombre in todos:
			if "_arm_" in nombre:
				_nombres.append(nombre)
	_msg.joint_names = _nombres


func _publicar() -> void:
	var q: PackedFloat32Array = robot.call("posiciones_joints", _nombres)
	var q64 := PackedFloat64Array()
	var ceros := PackedFloat64Array()
	for valor in q:
		q64.append(valor)
		ceros.append(0.0)
	contexto.sello(_msg.header)
	_msg.header.frame_id = ""
	_msg.speed_scaling_factor = 1.0
	for campo in ["reference", "feedback", "error", "output"]:
		var punto = _msg.get_member(campo)
		punto.positions = q64
		punto.velocities = ceros
		punto.accelerations = ceros
		punto.effort = ceros
		_msg.set_member(campo, punto)
	pub.publish(_msg)
