extends "res://comun/ros/sensor_base.gd"

const Util = preload("res://comun/ros/util_ros.gd")

@export var ruido_aceleracion := 0.02
@export var ruido_giroscopio := 0.002
@export var gravedad := Util.GRAVEDAD_GODOT

var _msg: RosMsg
var _vel_anterior := Vector3.ZERO
var _primera := true
var _dt_real := 0.0


func _init() -> void:
	topic = "/imu/data"
	tipo = "sensor_msgs/msg/Imu"
	frame_id = "imu_link"
	hz = 50.0
	hz_vita = 30.0
	hz_xrce = 10.0


func _sensor_listo() -> void:
	_msg = RosMsg.from_type(tipo)
	_msg.header.frame_id = frame_id
	_msg.orientation_covariance = Util.diagonal(0.0001)
	_msg.angular_velocity_covariance = Util.diagonal(ruido_giroscopio * ruido_giroscopio)
	_msg.linear_acceleration_covariance = Util.diagonal(ruido_aceleracion * ruido_aceleracion)


func _actualizar_sensor(dt: float) -> void:
	_dt_real += dt


func _publicar() -> void:
	# R2-M1: derivar con el tiempo REAL desde la última muestra, no con 1/hz (con huecos de 1 y 5 ticks la
	# aceleración dinámica salía escalada).
	var dt := maxf(_dt_real, 1e-4)
	_dt_real = 0.0
	var velocidad := Vector3.ZERO
	var angular := Vector3.ZERO
	if robot != null and robot.has_method("velocidad_lineal_ros"):
		velocidad = Util.vector_godot(robot.call("velocidad_lineal_ros"))
		angular = Util.vector_godot(robot.call("velocidad_angular_ros"))
	else:
		velocidad = Vector3.ZERO
	var aceleracion := -gravedad   # la primera muestra ya incluye la gravedad (R2-B4)
	if not _primera:
		aceleracion = (velocidad - _vel_anterior) / dt - gravedad
	_primera = false
	_vel_anterior = velocidad
	var inversa := global_basis.orthonormalized().inverse()
	var acel_local := inversa * aceleracion
	var gyro_local := inversa * angular
	acel_local += Vector3(randfn(0.0, ruido_aceleracion), randfn(0.0, ruido_aceleracion), randfn(0.0, ruido_aceleracion))
	gyro_local += Vector3(randfn(0.0, ruido_giroscopio), randfn(0.0, ruido_giroscopio), randfn(0.0, ruido_giroscopio))
	_sellar_y_fijar_frame(_msg)
	Util.escribir_quat(_msg.orientation, Util.quat_ros(global_basis.get_rotation_quaternion()))
	Util.escribir_vector(_msg.angular_velocity, Util.vector_ros(gyro_local))
	Util.escribir_vector(_msg.linear_acceleration, Util.vector_ros(acel_local))
	pub.publish(_msg)
