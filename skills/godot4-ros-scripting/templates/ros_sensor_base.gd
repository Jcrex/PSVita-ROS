@abstract
class_name RosSensorBase
extends Node3D
## Plantilla: base de sensores simulados (nodo ROS propio, TF de montaje, muestreo, QoS de sensor).
## Adaptado de roomba_ws/addons/rclgd-sensors/ros_sensor.gd (c) 2026 Miguel Oroz Zubasti, MIT.
## SIN EJECUTAR en este repo.

@export var ros_namespace: String = ""
@export var frame_id: String = ""                 # vacío => "~<nombre_en_snake_case>"
@export var parent_frame_id: String = "~base_link"

var _node: RosNode
var _tf: RosTfBroadcaster
var _frame: String
var _timer: RosTimer


func _ready() -> void:
	_node = RosNode.new()
	_node.init(name.to_snake_case(), ros_namespace.to_snake_case())
	_tf = _node.create_tf_broadcaster()
	var f := frame_id if not frame_id.is_empty() else "~" + name.to_snake_case()
	_frame = _node.resolve_frame(f)
	_tf.send_transform(transform, f, parent_frame_id, true)  # montaje rígido => estático
	_sensor_ready()


## Las subclases crean aquí sus publishers con _advertise()
func _sensor_ready() -> void:
	pass


## Una muestra; llamada a la frecuencia de _start_sampling()
func _sample() -> void:
	pass


func _start_sampling(rate_hz: float) -> void:
	var interval := 1.0 / rate_hz
	await get_tree().create_timer(randf() * interval).timeout  # fase aleatoria
	_timer = _node.create_timer(interval, _sample)


## QoS de datos de sensor: BEST_EFFORT, KEEP_LAST 5, VOLATILE (el suscriptor debe ser BEST_EFFORT)
func _advertise(topic: String, type: String) -> RosPublisher:
	var qos := RosQoS.new()
	qos.set_reliability(RosQoS.BEST_EFFORT)
	qos.set_history(RosQoS.KEEP_LAST)
	qos.set_depth(5)
	qos.set_durability(RosQoS.VOLATILE)
	return _node.create_publisher(topic, type, qos)
