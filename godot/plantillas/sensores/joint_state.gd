extends "res://comun/ros/sensor_base.gd"

@export var nombres := PackedStringArray()
@export var topic_compacto := ""
@export var publicar_estandar_en_vita := false

var _msg: RosMsg
var _compacto: RosMsg
var _pub_compacto: RosPublisher


func _init() -> void:
	topic = "/joint_states"
	tipo = "sensor_msgs/msg/JointState"
	hz = 30.0
	hz_vita = 20.0
	hz_xrce = 5.0
	best_effort = false


func _sensor_listo() -> void:
	if nombres.is_empty() and robot != null and robot.has_method("nombres_joints"):
		nombres = robot.call("nombres_joints")
	_msg = RosMsg.from_type(tipo)
	_msg.name = nombres
	if topic_compacto != "":
		_compacto = RosMsg.from_type("std_msgs/msg/Float32MultiArray")
		_pub_compacto = contexto.publicador(topic_compacto, "std_msgs/msg/Float32MultiArray", true)


func _publicar() -> void:
	var posiciones := PackedFloat32Array()
	if robot != null and robot.has_method("posiciones_joints"):
		posiciones = robot.call("posiciones_joints", nombres)
	else:
		posiciones.resize(nombres.size())
		posiciones.fill(0.0)
	if not _en_vita or publicar_estandar_en_vita:
		contexto.sello(_msg.header)
		_msg.header.frame_id = ""
		var p64 := PackedFloat64Array()
		for p in posiciones:
			p64.append(p)
		_msg.position = p64
		_msg.velocity = PackedFloat64Array()
		_msg.effort = PackedFloat64Array()
		pub.publish(_msg)
	if _pub_compacto != null:
		_compacto.data = posiciones
		_pub_compacto.publish(_compacto)
