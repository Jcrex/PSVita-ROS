extends "res://comun/visor/display_ros_hud.gd"
## Estado de la meta de Nav2 (doc 36a §4.8.9, ficha hmi#15) en la barra fija: «Meta: fase · distancia · ETA ·
## recuperaciones» con color por fase.
##
## Nivel 0 de ADR 0012 (topics ocultos de la acción, sin puente):
##   - `<accion>/_action/status` = `action_msgs/msg/GoalStatusArray`, fiable + TRANSIENT_LOCAL, profundidad 1 (el
##     servidor lo publica *latched* [I]); solo cambia al cambiar la meta ⇒ no caduca (`caducidad_s = 0`).
##   - `<accion>/_action/feedback` = `nav2_msgs/action/NavigateToPose_FeedbackMessage` (116 B, hasta ~100 msg/s): una
##     segunda suscripción con su propio CanalDisplay y el mismo tope `hz`. [?] que rclgd acepte ese tipo por texto
##     en una suscripción normal (doc 36 §9.3); si no hay esquema/typesupport se queda sin feedback y lo dice
##     `estado_feedback`.
##   La Vita no conoce el UUID de su meta: se muestra la de `goal_info.stamp` más reciente (docs/32 §3).
##
## Nivel 1 (camino compacto, `topic_vita = "accion/estado"`, `Float32MultiArray` de 24 floats, docs/32:51 y :61):
## [ver, epoca, seq, canal, ack_epoca, ack_seq, id_meta, fase, codigo, enlace_ms, puerta, servidores_ok, t_meta_s,
## progreso, f0 distancia, f1 ETA, f2 recuperaciones, …]. El puente VAB/1 NO está implementado [I]: el camino está
## escrito según el diseño y queda apagado (`topic_vita = ""`) hasta que exista.
##
## SIN esquema en la Vita: ni `GoalStatusArray` ni el FeedbackMessage están en `generar_esquemas.py` ⇒ «sin
## esquema» hasta V5 (`TIPOS_VISOR` incluye `action_msgs/GoalStatusArray`; el FeedbackMessage, registro manual).
##
## Coste: texto ≤ MAX_CAR = 40 *quads* (catálogo ≈ 50).

const TiempoRos = preload("res://comun/visor/tiempo_ros.gd")   # Canal ya viene de la base

## action_msgs/GoalStatus STATUS_* (0..6).
const FASE := ["sin meta", "aceptada", "ejecutando", "cancelando", "LLEGÓ", "cancelada", "ABORTADA"]
const COLOR_FASE := [COLOR_CADUCADO, COLOR_TEXTO, Color(0.3, 0.7, 1.0), COLOR_AVISO, COLOR_OK, COLOR_CADUCADO,
		COLOR_ERROR]
## Fases del puente VAB/1 (docs/32:61) → (texto, índice de color de COLOR_FASE).
const FASE_PUENTE := [["reposo", 0], ["comprobando", 1], ["enviada", 1], ["RECHAZADA", 6], ["ejecutando", 2],
		["cancelando", 3], ["cancelada", 5], ["LLEGÓ", 4], ["ABORTADA", 6], ["SIN SERVIDOR", 6], ["ERROR PUENTE", 6]]
const MAX_CAR := 40

@export var accion := "/navigate_to_pose"
@export var tipo_feedback := "nav2_msgs/action/NavigateToPose_FeedbackMessage"
@export var con_feedback := true

var canal_fb = Canal.new()
var estado_feedback := "sin conectar"
var fase_texto := "sin meta"
var fase_color := COLOR_CADUCADO
var distancia := NAN                           # m
var eta := NAN                                 # s
var recuperaciones := -1


static func nombre_display() -> String:
	return "EstadoMeta"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["action_msgs/msg/GoalStatusArray"])


func _init() -> void:
	tipo = "action_msgs/msg/GoalStatusArray"
	latched = true                             # AUTO + latched = fiable + TRANSIENT_LOCAL, profundidad 1
	caducidad_s = 0.0


func conectar(v) -> void:
	if topic == "" and accion != "":
		topic = accion.trim_suffix("/") + "/_action/status"
	super.conectar(v)
	if estado == "desactivado" or canal.compacto or not con_feedback or accion == "":
		estado_feedback = "sin feedback"
		return
	if not canal_fb.mensaje.is_connected(_al_feedback):
		canal_fb.mensaje.connect(_al_feedback)
	# Mismo cuidado que CanalDisplay.abrir_para: sin esquema no se suscribe (T20).
	if RosMsg.from_type(tipo_feedback) == null:
		estado_feedback = "sin esquema: " + tipo_feedback
		return
	canal_fb.hz = canal.hz
	var qos = v.contexto.qos(true, 1, false)     # best effort, profundidad 1: solo interesa el último
	var t := accion.trim_suffix("/") + "/_action/feedback"
	estado_feedback = "ok" if canal_fb.abrir(v.contexto.nodo, t, tipo_feedback, qos) else "error al suscribir"


func desconectar() -> void:
	canal_fb.cerrar()
	if canal_fb.mensaje.is_connected(_al_feedback):
		canal_fb.mensaje.disconnect(_al_feedback)
	super.desconectar()


func _process(dt: float) -> void:
	super._process(dt)
	if canal_fb.abierto():
		canal_fb.bombear()


func _poner_fase(i: int) -> void:
	i = clampi(i, 0, FASE.size() - 1)
	fase_texto = FASE[i]
	fase_color = COLOR_FASE[i]


## GoalStatusArray → fase de la meta más reciente (por `goal_info.stamp`).
func _procesar(msg):
	var mejor = null
	var t_mejor := -INF
	for st in msg.status_list:
		var t := TiempoRos.segundos(st.goal_info.stamp)
		if mejor == null or t > t_mejor:
			mejor = st
			t_mejor = t
	_poner_fase(0 if mejor == null else int(mejor.status))
	return fase_texto


## Puente VAB/1 (nivel 1): ver cabecera. Mensaje corto = se ignora.
func _procesar_compacto(msg):
	var d = msg.data
	if d.size() < 17:
		return null
	var f := int(d[7])
	if f >= 0 and f < FASE_PUENTE.size():
		fase_texto = FASE_PUENTE[f][0]
		fase_color = COLOR_FASE[FASE_PUENTE[f][1]]
	else:
		fase_texto = "?"
		fase_color = COLOR_ERROR
	distancia = float(d[14])
	eta = float(d[15])
	recuperaciones = int(d[16]) if not is_nan(float(d[16])) else -1
	return fase_texto


## FeedbackMessage de NavigateToPose: `feedback.distance_remaining` (float32 m),
## `feedback.estimated_time_remaining` (Duration), `feedback.number_of_recoveries` (int16).
func _al_feedback(msg) -> void:
	var fb = msg.feedback
	distancia = float(fb.distance_remaining)
	eta = TiempoRos.segundos(fb.estimated_time_remaining)
	recuperaciones = int(fb.number_of_recoveries)
	queue_redraw()


func _dibujar() -> bool:
	var s := "Meta: " + fase_texto
	if not is_nan(distancia):
		s += " %s m" % num(distancia)
	if not is_nan(eta):
		s += " ETA %s s" % num(eta, "%.0f")
	if recuperaciones >= 0:
		s += " rec %d" % recuperaciones
	texto(Vector2(4, size.y - 7), s, color_estado(fase_color), MAX_CAR)
	return true


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": MAX_CAR}
