extends Node3D

var contexto: RefCounted
var robot: Node3D
var _sub_low: RosSubscriber
var _sub_request: RosSubscriber
var _pub_response: RosPublisher


func _ready() -> void:
	if contexto == null or contexto.nodo == null:
		return
	_sub_low = contexto.suscripcion("/lowcmd", "unitree_hg/msg/LowCmd", _on_lowcmd, false)
	_sub_request = contexto.suscripcion("/api/sport/request", "unitree_api/msg/Request", _on_request, false)
	_pub_response = contexto.publicador("/api/sport/response", "unitree_api/msg/Response", false)


func _on_lowcmd(msg) -> void:
	for i in mini(msg.motor_cmd.size(), 35):
		robot.call("fijar_motor", i, msg.motor_cmd[i].q)


func _on_request(msg) -> void:
	var api_id: int = msg.header.identity.api_id
	var parametros = JSON.parse_string(msg.parameter)
	var codigo := 0
	match api_id:
		7105:
			if parametros is Dictionary and parametros.has("velocity"):
				var v: Array = parametros.velocity
				robot.call("fijar_orden", Vector3(v[0], v[1], v[2]))
		7101, 7102, 7103, 7104, 7106, 7107:
			pass
		_:
			codigo = 3401
	var response = RosMsg.from_type("unitree_api/msg/Response")
	response.header.identity.id = msg.header.identity.id
	response.header.identity.api_id = api_id
	response.header.status.code = codigo
	response.data = "{}"
	response.binary = PackedInt32Array()
	_pub_response.publish(response)
