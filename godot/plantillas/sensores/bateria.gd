extends "res://comun/ros/sensor_base.gd"

@export var capacidad_ah := 5.0
@export var voltaje_nominal := 24.0
@export var consumo_base_a := 0.8

var _msg: RosMsg
var _carga := 1.0


func _init() -> void:
	topic = "/battery_state"
	tipo = "sensor_msgs/msg/BatteryState"
	frame_id = "battery_link"
	hz = 1.0
	hz_vita = 0.2


func _sensor_listo() -> void:
	_msg = RosMsg.from_type(tipo)
	_msg.header.frame_id = frame_id
	_msg.design_capacity = capacidad_ah
	_msg.capacity = capacidad_ah
	_msg.power_supply_status = 2
	_msg.power_supply_health = 1
	_msg.power_supply_technology = 3
	_msg.present = true
	_msg.location = "pack_simulado"
	_msg.cell_voltage = PackedFloat32Array()
	_msg.cell_temperature = PackedFloat32Array()


func _publicar() -> void:
	var corriente := consumo_base_a
	if robot != null and robot.get("orden_actual") != null:
		var orden: Vector3 = robot.get("orden_actual")
		# R2-B9: no mezclar m/s y rad/s en una norma: lineal (x, y) y giro por separado.
		corriente += 0.5 * Vector2(orden.x, orden.y).length() + 0.2 * absf(orden.z)
	_carga = maxf(0.0, _carga - corriente * (1.0 / hz) / (capacidad_ah * 3600.0))
	_sellar_y_fijar_frame(_msg)
	_msg.voltage = voltaje_nominal * (0.9 + 0.1 * _carga)
	_msg.current = -corriente
	_msg.charge = capacidad_ah * _carga
	_msg.percentage = _carga
	_msg.temperature = 25.0 + 2.0 * corriente
	pub.publish(_msg)
