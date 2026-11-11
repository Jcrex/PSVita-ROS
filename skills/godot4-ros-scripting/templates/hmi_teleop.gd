extends Control
## Plantilla: HMI de teleoperación (botones -> /cmd_vel, estado de /odom, servicio con await).
## Adaptado de roomba_ws/src/roomba_hmi/main.gd (c) 2026 Miguel Oroz Zubasti, MIT.
## Nodos esperados con nombre único (%): Forward, Back, Left, Right (Button), Speed (HSlider),
## Status y Message (Label). SIN EJECUTAR en este repo.

@export var turn_speed: float = 1.5

@onready var _forward: Button = %Forward
@onready var _back: Button = %Back
@onready var _left: Button = %Left
@onready var _right: Button = %Right
@onready var _speed: HSlider = %Speed
@onready var _status: Label = %Status
@onready var _message: Label = %Message

var _node: RosNode
var _cmd_pub: RosPublisher
var _odom_sub: RosSubscriber
var _dock_client: RosClient
var _timer: RosTimer
var _cmd: RosMsg  # se crea en _ready (portable a ros2_vita)
var _driving := false


func _ready() -> void:
	_node = RosNode.new()
	_node.init("hmi")
	_cmd_pub = _node.create_publisher("/cmd_vel", "geometry_msgs/msg/Twist")
	_odom_sub = _node.create_subscription("/odom", "nav_msgs/msg/Odometry", _on_odom)
	_dock_client = _node.create_client("/robot/dock", "std_srvs/srv/Trigger")
	_cmd = RosMsg.from_type("geometry_msgs/msg/Twist")
	_timer = _node.create_timer(0.1, _drive)


func _drive() -> void:  # 10 Hz; publica solo con tecla pulsada + un cero al soltar
	var lin := float(_forward.button_pressed) - float(_back.button_pressed)
	var ang := float(_left.button_pressed) - float(_right.button_pressed)
	var driving := lin != 0.0 or ang != 0.0
	if not driving and not _driving:
		return
	_driving = driving
	_cmd.linear.x = lin * _speed.value
	_cmd.angular.z = ang * turn_speed
	_cmd_pub.publish(_cmd)


func _on_odom(msg: RosMsg) -> void:
	_status.text = "%.2f m/s   %.2f rad/s" % [msg.twist.twist.linear.x, msg.twist.twist.angular.z]


func _on_dock_pressed() -> void:  # conectar la señal pressed del botón en el editor
	_message.text = "Enviando…"
	var req := _dock_client.async_send_request(_dock_client.create_request())
	var res: RosMsg = await req.completed
	_message.text = res.message if res else "sin respuesta"
