extends RefCounted
## CanalDisplay (ADR 0013 §1; doc 36 §2.9.2): suscripción + QoS + «el último gana» + Hz medido + caducidad
## (≈ rviz_common::RosTopicDisplay). TODA la lógica ROS de un display vive aquí; las bases DisplayRos3D/2D/Hud solo
## lo llaman. Es portable rclgd ↔ ros2_vita: tipo por texto, `RosMsg` sin clases tipadas y QoS con `set_*()`
## (vía `contexto.qos()`, trampa T3 de doc 36 §8).
##
## Los callbacks llegan en el hilo principal en las dos plataformas (rclgd por `call_deferred`; ros2_vita desde
## `process_frame`, `godot/ros2_vita/ros_runtime.cpp` `_pump`), así que no hacen falta cerrojos.

signal mensaje(msg)

enum { AUTO, BEST_EFFORT, FIABLE }

var hz := 0.0                    # tope de entrega al display (0 = sin tope)
var coalescer := true            # true = «el último gana»; false = entregar todos (trazador)
## Con `coalescer = false`: tope de mensajes pendientes (0 = sin tope). Una pestaña oculta del HUD no bombea, y
## sin tope una consola de eventos apilaría sin fin; con tope se descartan los más viejos (V6).
var max_pendientes := 0
var descartados := 0             # pendientes tirados por `max_pendientes`
var compacto := false            # true = camino del relay (/vita/*): el display usa _procesar_compacto
var topic_abierto := ""          # topic y tipo realmente suscritos (para el HUD y las pruebas)
var tipo_abierto := ""
var recibidos := 0               # mensajes llegados del middleware
var mostrados := 0               # mensajes entregados al display (≤ recibidos)
var hz_medido := 0.0             # ritmo de llegada medido en ventanas de 1 s
var avisado_hz := false          # D8: ya se avisó de que llega mucho más de lo que se dibuja
var _sub                         # RosSubscriber sin anotar: guardarlo mantiene viva la suscripción
var _pendientes: Array = []      # con coalescer, como mucho uno
var _t_ultimo := -1000000        # ms de la última entrega al display
var _t_recibido := -1000000      # ms de la última llegada (caducidad)
var _t_ventana := 0
var _n_ventana := 0


## Lee los @export comunes del display `d` y abre la suscripción adecuada en el visor `v`. Devuelve el estado:
## "ok", "sin topic", "sin esquema: <tipo>" o "error al suscribir".
func abrir_para(d, v) -> String:
	compacto = v.usa_compactos() and d.topic_vita != ""
	var t: String = (v.prefijo_compacto.trim_suffix("/") + "/" + d.topic_vita.trim_prefix("/")) if compacto else d.topic
	var ti: String = d.tipo_vita if compacto else d.tipo
	if t == "" or ti == "":
		return "sin topic"
	# Sin esquema (.rsch en la Vita) o sin typesupport (PC) no se suscribe: en la Vita cada muestra de un tipo
	# desconocido sería un ERR_FAIL_COND (trampa T20; ros_msg.cpp:161-162).
	if RosMsg.from_type(ti) == null:
		return "sin esquema: " + ti
	hz = d.hz_vita if (v.en_vita and d.hz_vita > 0.0) else d.hz
	var fiable: bool = d.fiabilidad == FIABLE or (d.fiabilidad == AUTO and d.latched)
	# Profundidad (ADR 0013 §6): 1 para best effort y latched; los eventos fiables, 10 en el PC y 5 en la Vita.
	var prof: int = d.profundidad
	if prof <= 0:
		prof = 1 if (not fiable or d.latched) else (5 if v.en_vita else 10)
	var qos = v.contexto.qos(not fiable, prof, d.latched)
	return "ok" if abrir(v.contexto.nodo, t, ti, qos) else "error al suscribir"


func abrir(nodo, topic: String, tipo: String, qos) -> bool:
	cerrar()
	_sub = nodo.create_subscription(topic, tipo, _al_recibir, qos)
	if _sub == null:
		return false
	topic_abierto = topic
	tipo_abierto = tipo
	return true


## Suelta la suscripción (los objetos Ros* son RefCounted: sin referencia, se cancela).
func cerrar() -> void:
	_sub = null
	_pendientes.clear()
	topic_abierto = ""
	tipo_abierto = ""


func abierto() -> bool:
	return _sub != null


func _al_recibir(msg) -> void:
	recibidos += 1
	_n_ventana += 1
	_t_recibido = Time.get_ticks_msec()
	if coalescer:
		_pendientes.clear()      # «el último gana» (trampa T24: rclgd entrega CADA mensaje)
	elif max_pendientes > 0 and _pendientes.size() >= max_pendientes:
		_pendientes.pop_front()
		descartados += 1
	_pendientes.append(msg)


## Una vez por fotograma (desde el _process del display). Entrega lo pendiente si pasó 1/hz desde la última vez.
## Con `coalescer` el bucle de entrega recorre como mucho un mensaje (no hay bucles por elemento en _process).
func bombear() -> void:
	var ahora := Time.get_ticks_msec()
	if ahora - _t_ventana >= 1000:
		hz_medido = _n_ventana * 1000.0 / maxi(ahora - _t_ventana, 1)
		_n_ventana = 0
		_t_ventana = ahora
		# D8: llega mucho más de lo que se dibuja; en la Vita se decodifica entero cada mensaje antes del
		# callback (doc 31 H25), así que el ritmo hay que fijarlo en origen (relay o módulo `ritmo`).
		if hz > 0.0 and hz_medido > 2.0 * hz and not avisado_hz:
			avisado_hz = true
			push_warning("CanalDisplay %s: %.0f Hz recibidos para %.0f Hz de dibujo; fijar el ritmo en origen"
					% [topic_abierto, hz_medido, hz])
	if _pendientes.is_empty() or (hz > 0.0 and ahora - _t_ultimo < 1000.0 / hz):
		return
	_t_ultimo = ahora
	var lote := _pendientes
	_pendientes = []
	for m in lote:
		mostrados += 1
		mensaje.emit(m)


## ¿Lleva más de `segundos` sin llegar nada? Falso si nunca llegó nada o si `segundos` ≤ 0 (= nunca caduca).
func caducado(segundos: float) -> bool:
	return segundos > 0.0 and recibidos > 0 and Time.get_ticks_msec() - _t_recibido > segundos * 1000.0
