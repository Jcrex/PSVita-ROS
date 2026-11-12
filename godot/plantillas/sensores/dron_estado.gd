extends "res://comun/ros/sensor_base.gd"

const Util = preload("res://comun/ros/util_ros.gd")

@export var topic_rotores := "/drone/rotors"
@export var topic_flujo := "/drone/optical_flow"

var _pub_rotores: RosPublisher
var _pub_flujo: RosPublisher
var _rotores: RosMsg
var _flujo: RosMsg


func _init() -> void:
	hz = 20.0
	hz_vita = 10.0
	hz_xrce = 5.0


func _sensor_listo() -> void:
	_rotores = RosMsg.from_type("std_msgs/msg/Float32MultiArray")
	_flujo = RosMsg.from_type("geometry_msgs/msg/TwistStamped")
	_pub_rotores = contexto.publicador(topic_rotores, "std_msgs/msg/Float32MultiArray", true)
	_pub_flujo = contexto.publicador(topic_flujo, "geometry_msgs/msg/TwistStamped", true)


func _publicar() -> void:
	_rotores.data = robot.call("angulos_rotores")
	_pub_rotores.publish(_rotores)
	contexto.sello(_flujo.header)
	_flujo.header.frame_id = frame_id
	Util.escribir_vector(_flujo.twist.linear, robot.call("velocidad_local_ros"))
	Util.escribir_vector(_flujo.twist.angular, robot.call("velocidad_angular_ros"))
	_pub_flujo.publish(_flujo)
