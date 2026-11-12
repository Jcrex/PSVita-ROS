extends "res://comun/ros/sensor_base.gd"

const Util = preload("res://comun/ros/util_ros.gd")

@export var topic_compacto := "/g1/estado"
@export var publicar_propietarios_pc := true

var _pub_compacto: RosPublisher
var _compacto: RosMsg
var _low: RosMsg
var _sport: RosMsg
var _lidar: RosMsg
var _wireless: RosMsg
var _pub_low: RosPublisher
var _pub_low_lf: RosPublisher
var _pub_sport: RosPublisher
var _pub_sport_lf: RosPublisher
var _pub_lidar: RosPublisher
var _pub_wireless: RosPublisher
var _cuenta := 0


func _init() -> void:
	hz = 25.0
	hz_vita = 25.0
	hz_xrce = 10.0


func _sensor_listo() -> void:
	_compacto = RosMsg.from_type("std_msgs/msg/Float32MultiArray")
	_pub_compacto = contexto.publicador(topic_compacto, "std_msgs/msg/Float32MultiArray", true)
	if _en_vita or not publicar_propietarios_pc:
		return
	_low = RosMsg.from_type("unitree_hg/msg/LowState")
	_sport = RosMsg.from_type("unitree_go/msg/SportModeState")
	_lidar = RosMsg.from_type("unitree_go/msg/LidarState")
	_wireless = RosMsg.from_type("unitree_go/msg/WirelessController")
	_pub_low = contexto.publicador("/lowstate", "unitree_hg/msg/LowState", false)
	_pub_low_lf = contexto.publicador("/lf/lowstate", "unitree_hg/msg/LowState", false)
	_pub_sport = contexto.publicador("/sportmodestate", "unitree_go/msg/SportModeState", true)
	_pub_sport_lf = contexto.publicador("/lf/sportmodestate", "unitree_go/msg/SportModeState", true)
	_pub_lidar = contexto.publicador("/utlidar/lidar_state", "unitree_go/msg/LidarState", true)
	_pub_wireless = contexto.publicador("/wirelesscontroller", "unitree_go/msg/WirelessController", true)


func _publicar() -> void:
	_cuenta += 1
	_publicar_compacto()
	if _pub_low == null:
		return
	var nombres: PackedStringArray = robot.call("nombres_joints")
	var q: PackedFloat32Array = robot.call("posiciones_joints", nombres)
	for i in mini(_low.motor_state.size(), q.size()):
		_low.motor_state[i].q = q[i]
		_low.motor_state[i].dq = 0.0
		_low.motor_state[i].tau_est = 0.0
	_low.tick = _cuenta
	_rellenar_imu(_low.imu_state)
	_pub_low.publish(_low)
	if _cuenta % 5 == 0:
		_pub_low_lf.publish(_low)
		_pub_sport_lf.publish(_sport)
		_rellenar_lidar()
	if _cuenta % 4 == 0:
		_rellenar_sport(q)
		_pub_sport.publish(_sport)
		_pub_wireless.publish(_wireless)


func _rellenar_imu(imu) -> void:
	var q: Quaternion = robot.call("orientacion_ros")
	var w: Vector3 = robot.call("velocidad_angular_ros")
	imu.quaternion = PackedFloat32Array([q.w, q.x, q.y, q.z])
	imu.gyroscope = PackedFloat32Array([w.x, w.y, w.z])
	imu.accelerometer = PackedFloat32Array([0.0, 0.0, 9.80665])
	imu.rpy = PackedFloat32Array([0.0, 0.0, Util.yaw_de_quat(q)])
	imu.temperature = 35


func _publicar_compacto() -> void:
	var p: Vector3 = robot.call("posicion_ros")
	var q: Quaternion = robot.call("orientacion_ros")
	var datos := PackedFloat32Array([p.x, p.y, p.z + 0.78, q.x, q.y, q.z, q.w])
	var nombres: PackedStringArray = robot.call("nombres_joints")
	var pos := PackedStringArray(marcha_nombres())
	var valores: PackedFloat32Array = robot.call("posiciones_joints", pos)
	datos.append_array(valores)
	_compacto.data = datos
	_pub_compacto.publish(_compacto)


func marcha_nombres() -> Array:
	return ["left_hip_pitch_joint", "left_hip_roll_joint", "left_hip_yaw_joint", "left_knee_joint",
		"left_ankle_pitch_joint", "left_ankle_roll_joint", "right_hip_pitch_joint", "right_hip_roll_joint",
		"right_hip_yaw_joint", "right_knee_joint", "right_ankle_pitch_joint", "right_ankle_roll_joint"]


func _rellenar_sport(q: PackedFloat32Array) -> void:
	var p: Vector3 = robot.call("posicion_ros")
	var v: Vector3 = robot.call("velocidad_local_ros")
	var w: Vector3 = robot.call("velocidad_angular_ros")
	_sport.position = PackedFloat32Array([p.x, p.y, p.z])
	_sport.velocity = PackedFloat32Array([v.x, v.y, v.z])
	_sport.yaw_speed = w.z
	_sport.body_height = 0.78
	_sport.mode = 1
	_sport.gait_type = 1
	_rellenar_imu(_sport.imu_state)
	var posiciones_pie := PackedFloat32Array()
	posiciones_pie.resize(12)
	posiciones_pie.fill(0.0)
	var velocidades_pie := PackedFloat32Array()
	velocidades_pie.resize(12)
	velocidades_pie.fill(0.0)
	_sport.foot_position_body = posiciones_pie
	_sport.foot_speed_body = velocidades_pie


func _rellenar_lidar() -> void:
	_lidar.stamp = Time.get_unix_time_from_system()
	_lidar.firmware_version = "sim-godot"
	_lidar.software_version = "1"
	_lidar.sdk_version = "unitree_ros2"
	_lidar.cloud_frequency = 5.0
	_lidar.imu_frequency = 50.0
	_lidar.imu_rpy = PackedFloat32Array([0.0, 0.0, 0.0])
	_pub_lidar.publish(_lidar)
