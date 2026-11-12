extends "res://comun/ros/sensor_base.gd"

const Util = preload("res://comun/ros/util_ros.gd")

@export var presion_nivel_mar := 101325.0
@export var ruido_pa := 2.0
## Altitud del origen del mundo sobre el nivel del mar, la misma que `origen_altitud` del GNSS (revisión R2-M3:
## antes el barómetro decía ~0 m y el GNSS ~451 m).
@export var origen_altitud := 450.0

var _msg: RosMsg


func _init() -> void:
	topic = "/barometer"
	tipo = "sensor_msgs/msg/FluidPressure"
	frame_id = "barometer_link"
	hz = 20.0
	hz_vita = 10.0
	hz_xrce = 5.0


func _sensor_listo() -> void:
	_msg = RosMsg.from_type(tipo)
	_msg.header.frame_id = frame_id
	_msg.variance = ruido_pa * ruido_pa


func _publicar() -> void:
	var altitud := origen_altitud + Util.vector_ros(global_position).z
	_sellar_y_fijar_frame(_msg)
	_msg.fluid_pressure = presion_nivel_mar * pow(1.0 - 2.25577e-5 * altitud, 5.25588) + randfn(0.0, ruido_pa)
	pub.publish(_msg)
