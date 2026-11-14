extends Node3D

var contexto: RefCounted
var robot: Node3D
var topic := "/emergency_stop"
var _sub: RosSubscriber


func _ready() -> void:
	if contexto == null or contexto.nodo == null:
		return
	_sub = contexto.suscripcion(topic, "std_msgs/msg/Bool", _on_estop, false)


func _on_estop(msg) -> void:
	if robot != null:   # R2-B12
		robot.call("fijar_emergencia", msg.data)
