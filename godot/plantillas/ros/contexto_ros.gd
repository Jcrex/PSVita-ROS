extends RefCounted

var nodo: RosNode
var publicadores: Dictionary = {}
var suscripciones: Array[RosSubscriber] = []
var iniciado_por_contexto := false
var transporte := ""


func iniciar(nombre: String, espacio: String, transporte: String) -> int:
	self.transporte = transporte
	if not rclgd.ok():
		var args := PackedStringArray()
		if transporte != "":
			args = PackedStringArray(["-p", "transport:=" + transporte])
		var err := rclgd.init(args)
		if err != OK:
			return err
		iniciado_por_contexto = true
	nodo = RosNode.new()
	nodo.init(nombre, espacio)
	return OK


func qos(best_effort: bool = true, profundidad: int = 1, latched: bool = false) -> RosQoS:
	var q := RosQoS.new()
	q.set_history(RosQoS.KEEP_LAST)
	q.set_depth(profundidad)
	q.set_reliability(RosQoS.BEST_EFFORT if best_effort else RosQoS.RELIABLE)
	q.set_durability(RosQoS.TRANSIENT_LOCAL if latched else RosQoS.VOLATILE)
	return q


func publicador(topic: String, tipo: String, best_effort: bool = true, latched: bool = false) -> RosPublisher:
	var clave := topic + "|" + tipo
	if publicadores.has(clave):
		return publicadores[clave]
	var p := nodo.create_publisher(topic, tipo, qos(best_effort, 1, latched))
	publicadores[clave] = p
	return p


func suscripcion(topic: String, tipo: String, callback: Callable, best_effort: bool = true) -> RosSubscriber:
	var s := nodo.create_subscription(topic, tipo, callback, qos(best_effort))
	suscripciones.append(s)
	return s


func sello(header) -> void:
	header.stamp = nodo.now()


func cerrar() -> void:
	suscripciones.clear()
	publicadores.clear()
	nodo = null
	if iniciado_por_contexto and rclgd.ok():
		rclgd.shutdown()
	iniciado_por_contexto = false
