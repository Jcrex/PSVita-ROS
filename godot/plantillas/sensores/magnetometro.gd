extends "res://comun/ros/sensor_base.gd"

## Campo terrestre en el marco del mundo ENU (REP-103/105, el mismo del GNSS: x = Este, y = Norte, z = arriba):
## componente horizontal hacia el Norte (+y) y vertical hacia abajo. Antes (21, 0, −43) ponía el norte en +x y
## discrepaba 90° del GNSS (revisión R2-M2). Sin declinación.
@export var campo_local_ut := Vector3(0.0, 21.0, -43.0)
@export var ruido_ut := 0.1

var _msg: RosMsg


func _init() -> void:
	topic = "/magnetic_field"
	tipo = "sensor_msgs/msg/MagneticField"
	frame_id = "magnetometer_link"
	hz = 20.0
	hz_vita = 10.0
	hz_xrce = 5.0


func _sensor_listo() -> void:
	_msg = RosMsg.from_type(tipo)
	_msg.header.frame_id = frame_id
	var varianza := ruido_ut * ruido_ut * 1e-12
	_msg.magnetic_field_covariance = PackedFloat64Array([varianza, 0.0, 0.0,
		0.0, varianza, 0.0, 0.0, 0.0, varianza])


func _publicar() -> void:
	var q: Quaternion = rclgd.godot_to_ros_quat(global_basis.get_rotation_quaternion())
	var local := q.inverse() * (campo_local_ut * 1e-6)
	local += Vector3(randfn(0.0, ruido_ut * 1e-6), randfn(0.0, ruido_ut * 1e-6), randfn(0.0, ruido_ut * 1e-6))
	_sellar_y_fijar_frame(_msg)
	_msg.magnetic_field.x = local.x
	_msg.magnetic_field.y = local.y
	_msg.magnetic_field.z = local.z
	pub.publish(_msg)
