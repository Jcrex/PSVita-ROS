extends Control
## Puerta G5 (docs/18 §8) — ros2_vita con el transporte XRCE (micro-ROS por WiFi/UDP).
## Publica std_msgs/String en /vita_hello (1 Hz) y geometry_msgs/Twist en /cmd_vel (10 Hz, stick
## izquierdo), y se suscribe a /pc_hello. Comprobar en el PC:
##   ros2 topic echo /vita_hello        ros2 topic pub /pc_hello std_msgs/msg/String "{data: hola}"
## Color de fondo: AMARILLO = sesión XRCE abierta y publicando; VERDE = además llegó /pc_hello;
## ROJO = no hay sesión (mirar el texto). La IP del agente sale de ros/agent_ip (project.godot) o de
## la línea de órdenes en el host: godot --path godot/g5-xrce -- -p agent_ip:=127.0.0.1
## Probado en host contra el agente en docker; en la Vita: validar en hardware.

@onready var info: Label = $Info
@onready var fondo: ColorRect = $Fondo

var lineas := PackedStringArray()
var node: RosNode
var pub_hello: RosPublisher
var pub_cmd: RosPublisher
var sub_pc: RosSubscriber   # guardar las referencias: si se sueltan, se cancelan (RefCounted)
var t_hello: RosTimer
var t_cmd: RosTimer
var enviados := 0
var recibidos := 0
var ultimo_pc := ""


func _ready() -> void:
	_log("ros2_vita G5 — Godot %s" % Engine.get_version_info().string)
	_log("agente: %s:%s" % [ProjectSettings.get_setting("ros/agent_ip", "?"), ProjectSettings.get_setting("ros/agent_port", "?")])
	fondo.color = Color(0.15, 0.15, 0.2)
	await get_tree().process_frame   # pintar el texto antes de bloquear en la conexión
	# Sin -p transport:=... => en la Vita el transporte por defecto es xrce. En el host se fuerza aquí.
	var args := PackedStringArray(["-p", "transport:=xrce"])
	args.append_array(OS.get_cmdline_user_args())
	var err := rclgd.init(args)
	_log("rclgd.init(xrce) -> %s" % error_string(err))
	if err != OK:
		_estado(Color(0.6, 0.1, 0.1), "G5 FALLO: sin sesión XRCE (¿agente corriendo? ¿IP correcta? ¿WiFi?)")
		return
	node = RosNode.new()
	node.init("vita_g5", "")
	pub_hello = node.create_publisher("/vita_hello", "std_msgs/msg/String")
	pub_cmd = node.create_publisher("/cmd_vel", "geometry_msgs/msg/Twist")
	sub_pc = node.create_subscription("/pc_hello", "std_msgs/msg/String", _on_pc_hello)
	if pub_hello == null or pub_cmd == null or sub_pc == null:
		_estado(Color(0.6, 0.1, 0.1), "G5 FALLO: el agente rechazó publishers/subscriber")
		return
	t_hello = node.create_timer(1.0, _on_hello)
	t_cmd = node.create_timer(0.1, _on_cmd)
	_estado(Color(0.6, 0.5, 0.1), "sesión XRCE abierta: publicando /vita_hello y /cmd_vel")


func _on_hello() -> void:
	var m := RosMsg.from_type("std_msgs/msg/String")
	m.data = "hola desde ros2_vita #%d" % enviados
	pub_hello.publish(m)
	enviados += 1


func _on_cmd() -> void:
	var m := RosMsg.from_type("geometry_msgs/msg/Twist")
	var stick := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	m.linear.x = -stick.y * 0.5 + 0.0    # adelante = stick arriba (+0.0 evita publicar -0.0)
	m.angular.z = -stick.x * 1.0 + 0.0  # izquierda = giro positivo (REP-103)
	pub_cmd.publish(m)


func _on_pc_hello(m: RosMsg) -> void:
	recibidos += 1
	ultimo_pc = m.data
	if recibidos == 1:
		_estado(Color(0.1, 0.5, 0.2), "G5 OK: llega /pc_hello desde ROS 2")


func _process(_delta: float) -> void:
	info.text = "\n".join(lineas) + "\n\n/vita_hello enviados: %d   /pc_hello recibidos: %d\núltimo /pc_hello: %s" % [enviados, recibidos, ultimo_pc]


func _estado(c: Color, s: String) -> void:
	fondo.color = c
	_log(s)


func _log(s: String) -> void:
	print(s)
	lineas.append(s)
