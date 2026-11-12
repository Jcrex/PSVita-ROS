extends "res://comun/ros/sensor_base.gd"

const Util = preload("res://comun/ros/util_ros.gd")
const WGS84_A := 6378137.0
const WGS84_E2 := 0.00669437999014

@export var origen_latitud := 42.8125
@export var origen_longitud := -1.6458
@export var origen_altitud := 450.0
@export var error_horizontal := 0.5
@export var error_vertical := 1.2
@export var correlacion_s := 5.0

var _msg: RosMsg
var _error := Vector3.ZERO
var _tiene_error := false


func _init() -> void:
	topic = "/gps/fix"
	tipo = "sensor_msgs/msg/NavSatFix"
	frame_id = "gps_link"
	hz = 10.0
	hz_vita = 5.0
	hz_xrce = 2.0


func _sensor_listo() -> void:
	_msg = RosMsg.from_type(tipo)
	_msg.header.frame_id = frame_id
	_msg.status.status = 0
	_msg.status.service = 1
	_msg.position_covariance = PackedFloat64Array([
		error_horizontal * error_horizontal, 0.0, 0.0,
		0.0, error_horizontal * error_horizontal, 0.0,
		0.0, 0.0, error_vertical * error_vertical])
	_msg.position_covariance_type = 2


func _publicar() -> void:
	var dt := 1.0 / hz
	var decaimiento := exp(-dt / correlacion_s) if _tiene_error and correlacion_s > 0.0 else 0.0
	var innovacion := Vector3(randfn(0.0, error_horizontal), randfn(0.0, error_horizontal), randfn(0.0, error_vertical))
	_error = _error * decaimiento + innovacion * sqrt(1.0 - decaimiento * decaimiento)
	_tiene_error = true
	var enu := Util.vector_ros(global_position) + _error
	var phi := deg_to_rad(origen_latitud)
	var den := sqrt(1.0 - WGS84_E2 * sin(phi) * sin(phi))
	var m := WGS84_A * (1.0 - WGS84_E2) / (den * den * den)
	var n := WGS84_A / den
	_sellar_y_fijar_frame(_msg)
	_msg.latitude = origen_latitud + rad_to_deg(enu.y / m)
	_msg.longitude = origen_longitud + rad_to_deg(enu.x / (n * cos(phi)))
	_msg.altitude = origen_altitud + enu.z
	pub.publish(_msg)
