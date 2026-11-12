extends "res://comun/ros/sensor_base.gd"

const Util = preload("res://comun/ros/util_ros.gd")

@export var odom_frame := "odom"
@export var base_frame := "base_footprint"
@export var topic_compacto := ""
@export var publicar_estandar_en_vita := false
@export var publicar_tf := true

var _msg: RosMsg
var _compacto: RosMsg
var _tf: RosMsg
var _pub_compacto: RosPublisher
var _pub_tf: RosPublisher


func _init() -> void:
	topic = "/odom"
	tipo = "nav_msgs/msg/Odometry"
	frame_id = "odom"
	hz = 30.0
	hz_vita = 20.0
	hz_xrce = 5.0
	best_effort = false


func _usa_publicador_estandar() -> bool:
	return not _en_vita or publicar_estandar_en_vita


func _sensor_listo() -> void:
	_msg = RosMsg.from_type(tipo)
	_msg.header.frame_id = odom_frame
	_msg.child_frame_id = base_frame
	_msg.pose.covariance = Util.covarianza_6d(0.0025, 0.0004)
	_msg.twist.covariance = Util.covarianza_6d(0.01, 0.0025)
	if topic_compacto != "":
		_compacto = RosMsg.from_type("std_msgs/msg/Float32MultiArray")
		_pub_compacto = contexto.publicador(topic_compacto, "std_msgs/msg/Float32MultiArray", true)
	if publicar_tf:
		_tf = RosMsg.from_type("tf2_msgs/msg/TFMessage")
		# /tf FIABLE: tf2 (tf2_echo, RViz, robot_state_publisher) se suscribe en reliable y no casa con un
		# publicador best effort (revisión R2-C2). Un TFMessage de un transform ocupa ~100 B: no se fragmenta.
		_pub_tf = contexto.publicador("/tf", "tf2_msgs/msg/TFMessage", false)


func _publicar() -> void:
	if not _en_vita or publicar_estandar_en_vita:
		_publicar_estandar()
	if _pub_compacto != null:
		var p: Vector3 = robot.call("posicion_base_ros")
		var q: Quaternion = robot.call("orientacion_base_ros")
		var v: Vector3 = robot.call("velocidad_local_ros")
		var w: Vector3 = robot.call("velocidad_angular_ros")
		_compacto.data = PackedFloat32Array([p.x, p.y, Util.yaw_de_quat(q), v.x, v.y, w.z])
		_pub_compacto.publish(_compacto)
	if _pub_tf != null:
		_publicar_tf()


func _publicar_estandar() -> void:
	_sellar_y_fijar_frame(_msg)
	_msg.header.frame_id = odom_frame
	# Pose del marco base (base_frame), no del origen del CharacterBody3D: en el G1 la pelvis está a ~0,79 m,
	# no a la altura de los pies (revisión R2-A5).
	Util.escribir_vector(_msg.pose.pose.position, robot.call("posicion_base_ros"))
	Util.escribir_quat(_msg.pose.pose.orientation, robot.call("orientacion_base_ros"))
	Util.escribir_vector(_msg.twist.twist.linear, robot.call("velocidad_local_ros"))
	Util.escribir_vector(_msg.twist.twist.angular, robot.call("velocidad_angular_ros"))
	pub.publish(_msg)


func _publicar_tf() -> void:
	var t = RosMsg.from_type("geometry_msgs/msg/TransformStamped")
	contexto.sello(t.header)
	t.header.frame_id = odom_frame
	t.child_frame_id = base_frame
	Util.escribir_vector(t.transform.translation, robot.call("posicion_base_ros"))   # R2-A5
	Util.escribir_quat(t.transform.rotation, robot.call("orientacion_base_ros"))
	_tf.transforms = [t]
	_pub_tf.publish(_tf)
