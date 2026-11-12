extends Node3D
## Entrada de mando Unitree del G1 simulado: `/lowcmd` (unitree_hg/LowCmd) y la API «sport» del LocoClient del
## G1 por topics (`/api/sport/request` → `/api/sport/response`, unitree_api). Identificadores y códigos:
## unitree_sdk2 `include/unitree/robot/g1/loco/g1_loco_api.hpp` e `include/unitree/robot/internal/internal_error.hpp`.

const OK_UNITREE := 0
const ERR_API_NO_IMPLEMENTADA := 3203   # UT_ROBOT_ERR_SERVER_API_NOT_IMPL (revisión R3-2.5: antes 3401, que no existe)
const ERR_PARAMETRO := 3204             # UT_ROBOT_ERR_SERVER_API_PARAMETER

const GET_FSM_ID := 7001
const GET_BALANCE_MODE := 7003
const SET_FSM_ID := 7101
const SET_BALANCE_MODE := 7102
const SET_VELOCITY := 7105
## FSM que dejan el robot sin marcha (zero torque, damp, squat, sit; g1_loco_client.hpp: Damp=1, Squat=2, Sit=3).
const FSM_SIN_MARCHA := [0, 1, 2, 3]

var contexto: RefCounted
var robot: Node3D
var _sub_low: RosSubscriber
var _sub_request: RosSubscriber
var _pub_response: RosPublisher
var fsm_id := 500            # Start() = SetFsmId(500): marcha
var balance_mode := 0


func _ready() -> void:
	if contexto == null or contexto.nodo == null:
		return
	_sub_low = contexto.suscripcion("/lowcmd", "unitree_hg/msg/LowCmd", _on_lowcmd, false)
	_sub_request = contexto.suscripcion("/api/sport/request", "unitree_api/msg/Request", _on_request, false)
	_pub_response = contexto.publicador("/api/sport/response", "unitree_api/msg/Response", false)


func _on_lowcmd(msg) -> void:
	if robot == null:   # R2-B12
		return
	for i in mini(msg.motor_cmd.size(), 35):
		robot.call("fijar_motor", i, msg.motor_cmd[i].q)


## R3-2.5/2.6: solo responden 0 las API que el modelo cinemático simula de verdad; el resto, 3203. Antes
## 7101–7107 respondían «éxito» sin hacer nada y un cliente creía, p. ej., que el cambio de FSM se había aplicado.
func _on_request(msg) -> void:
	var api_id: int = msg.header.identity.api_id
	var parametros = JSON.parse_string(msg.parameter) if msg.parameter != "" else {}
	var codigo := OK_UNITREE
	var datos := {}
	match api_id:
		SET_VELOCITY:
			# {"velocity":[vx, vy, ω], "duration": d}; la duración se respeta (antes se ignoraba, R3-2.4).
			if robot == null or not (parametros is Dictionary) or not parametros.has("velocity") \
					or not (parametros.velocity is Array) or parametros.velocity.size() < 3:
				codigo = ERR_PARAMETRO
			elif fsm_id in FSM_SIN_MARCHA:
				codigo = ERR_PARAMETRO   # sin marcha no hay locomoción: no fingir que se obedece
			else:
				var v: Array = parametros.velocity
				var d: float = float(parametros.get("duration", 1.0))
				robot.call("fijar_orden_durante", Vector3(v[0], v[1], v[2]), d)
		SET_FSM_ID:
			if not (parametros is Dictionary) or not parametros.has("data"):
				codigo = ERR_PARAMETRO
			else:
				fsm_id = int(parametros.data)
				if fsm_id in FSM_SIN_MARCHA and robot != null:
					robot.call("fijar_orden", Vector3.ZERO)   # Damp/Sit/…: el robot se detiene
		SET_BALANCE_MODE:
			if not (parametros is Dictionary) or not parametros.has("data"):
				codigo = ERR_PARAMETRO
			else:
				balance_mode = int(parametros.data)   # solo estado: la marcha cinemática no cambia
		GET_FSM_ID:
			datos = {"data": fsm_id}
		GET_BALANCE_MODE:
			datos = {"data": balance_mode}
		_:
			# 7002 GetFsmMode, 7004/7005 alturas, 7006 fase, 7103 SwingHeight, 7104 StandHeight, 7106 ArmTask,
			# 7107 SpeedMode, 7110/7111 y cualquier otro: no simulados.
			codigo = ERR_API_NO_IMPLEMENTADA
	var response = RosMsg.from_type("unitree_api/msg/Response")
	response.header.identity.id = msg.header.identity.id
	response.header.identity.api_id = api_id
	response.header.status.code = codigo
	response.data = JSON.stringify(datos)
	response.binary = PackedInt32Array()
	_pub_response.publish(response)
