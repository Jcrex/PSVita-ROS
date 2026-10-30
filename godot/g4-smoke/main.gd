extends Control
## Puerta G4 (docs/18 §8) — prueba de humo de ros2_vita en la Vita.
## Qué demuestra: la plantilla con ros2_vita arranca, rclgd.init() funciona con el
## transporte loopback (sin red) y RosMsg serializa/deserializa un Twist.
## Indicador que no depende de la fuente: fondo VERDE = todo bien, ROJO = fallo.
## Validar en hardware.

const OBJETIVO := 3   # mensajes que deben volver por loopback para dar la puerta por buena

@onready var info: Label = $Info
@onready var fondo: ColorRect = $Fondo

var lineas := PackedStringArray()
var node: RosNode
var pub: RosPublisher
var sub: RosSubscriber   # guardar la referencia: si se suelta, se cancela (RefCounted)
var timer: RosTimer
var enviados := 0
var recibidos := 0
var ultimo_x := 0.0
var terminado := false


func _ready() -> void:
	_log("ros2_vita G4 — Godot %s" % Engine.get_version_info().string)
	# En la Vita el transporte por defecto es xrce (aún pendiente, G5): forzamos loopback.
	var err := rclgd.init(PackedStringArray(["-p", "transport:=loopback"]))
	_log("rclgd.init(loopback) -> %s" % error_string(err))
	_log("rclgd.ok() = %s" % rclgd.ok())
	if err != OK or not rclgd.ok():
		_fin(false, "rclgd no arrancó")
		return
	_log("tipos en el esquema: %d" % RosMsg.list_types().size())

	node = RosNode.new()
	node.init("vita_g4", "")
	sub = node.create_subscription("/g4/cmd", "geometry_msgs/msg/Twist", _on_twist)
	pub = node.create_publisher("/g4/cmd", "geometry_msgs/msg/Twist")
	if sub == null or pub == null:
		_fin(false, "no se crearon publisher/subscriber")
		return
	timer = node.create_timer(0.5, _on_timer)


func _on_timer() -> void:
	enviados += 1
	var m := RosMsg.from_type("geometry_msgs/msg/Twist")
	m.linear.x = enviados * 0.25
	pub.publish(m)


func _on_twist(m: RosMsg) -> void:
	recibidos += 1
	ultimo_x = m.linear.x
	if not terminado and recibidos >= OBJETIVO:
		_fin(ultimo_x == recibidos * 0.25, "linear.x esperado %.2f" % (recibidos * 0.25))


func _process(_delta: float) -> void:
	info.text = "\n".join(lineas) + "\n\nenviados %d · recibidos %d · último linear.x = %.2f" % [enviados, recibidos, ultimo_x]


func _fin(ok: bool, detalle: String) -> void:
	terminado = true
	fondo.color = Color(0.1, 0.5, 0.2) if ok else Color(0.6, 0.1, 0.1)
	_log(("G4 OK: " if ok else "G4 FALLO: ") + detalle)


func _log(s: String) -> void:
	print(s)
	lineas.append(s)
