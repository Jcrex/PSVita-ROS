extends Node
## ExploradorTopics (doc 36 §1.3; doc 36a §4.1.11, ficha nucleo#9; sentencia W13 D9; tarea V12).
##
## PC (rclgd): sondea `RosNode.get_topic_names_and_types()` cada `periodo_s` (rclgd no da eventos de grafo,
## `rclgd/src/rclgd/ros_node.cpp:361-381`), emite `topic_nuevo` / `topic_perdido`, y `anadir_display()` crea con
## RegistroDisplays el display que toca y lo cuelga en ejecución **sin guardarlo** (sin `owner`, regla doc 35).
##
## Vita (ros2_vita): XRCE no tiene API de grafo (`godot/ros2_vita/API_PARITY.md:38`) y ⚖ D9 = ningún descubrimiento.
## El explorador solo enseña el catálogo fijo: los topics de los displays de la escena (los compactos con su nombre
## real `<prefijo>/<topic_vita>`) y, como lista de tipos, los del esquema (`RosMsg.list_types()`, que solo existe en
## ros2_vita: se llama por `ClassDB.class_call_static` para que el script compile también con rclgd). En la Vita
## `anadir_display()` no hace nada (decisión conservadora: los topics de la Vita son fijos en la escena).
##
## Va colgado bajo el VisorRos (o con `visor` apuntándolo). Sondea solo con el visor listo.

const Registro = preload("res://comun/visor/registro_displays.gd")

signal topic_nuevo(topic: String, tipos: PackedStringArray)
signal topic_perdido(topic: String)

@export var visor: Node                         # VisorRos; null = el primer ancestro con `contexto`
@export var periodo_s := 2.0
@export var destino: Node                       # dónde se cuelgan los displays añadidos (null = el visor)

var topics := {}                                # topic -> PackedStringArray de tipos
var desde_grafo := false                        # true = la última lista salió del grafo (PC); false = catálogo
var anadidos: Array = []                        # displays creados en ejecución (no se guardan)
var _acum := 0.0
var _catalogo_hecho := false


func _ready() -> void:
	if visor == null:
		var n := get_parent()
		while n != null and not ("contexto" in n and "en_vita" in n):
			n = n.get_parent()
		visor = n


## ¿Hay API de grafo? (rclgd sí; ros2_vita no). Sin anotar: RosNode no tiene el método en la Vita.
func tiene_grafo() -> bool:
	if visor == null or not visor.ros_listo:
		return false
	var nodo = visor.contexto.nodo
	return nodo != null and nodo.has_method("get_topic_names_and_types")


func _process(dt: float) -> void:
	if visor == null or not visor.ros_listo:
		return
	_acum += dt
	if _acum < periodo_s and _catalogo_hecho:
		return
	_acum = 0.0
	if tiene_grafo() or not _catalogo_hecho:
		sondear()


## Actualiza `topics` y emite las señales de alta y baja. Devuelve la lista nueva.
func sondear() -> Dictionary:
	var nuevos := {}
	if tiene_grafo():
		desde_grafo = true
		var g: Dictionary = visor.contexto.nodo.call("get_topic_names_and_types")
		for t in g:
			nuevos[String(t)] = PackedStringArray(g[t])
	else:
		desde_grafo = false
		nuevos = catalogo()
		_catalogo_hecho = true
	for t in nuevos:
		if not topics.has(t):
			topic_nuevo.emit(t, nuevos[t])
	for t in topics:
		if not nuevos.has(t):
			topic_perdido.emit(t)
	topics = nuevos
	return topics


## Catálogo fijo (Vita, o PC sin grafo): topic -> [tipo] de los displays de la escena bajo el visor.
func catalogo() -> Dictionary:
	var out := {}
	if visor == null:
		return out
	var compacto: bool = visor.usa_compactos()
	for d in visor.get_tree().get_nodes_in_group("display_ros"):
		if not visor.is_ancestor_of(d) or not ("topic" in d):
			continue
		var t: String = d.topic
		var ti: String = d.tipo
		if compacto and String(d.topic_vita) != "":
			t = visor.prefijo_compacto.trim_suffix("/") + "/" + String(d.topic_vita).trim_prefix("/")
			ti = d.tipo_vita
		if t == "" or ti == "":
			continue
		if not out.has(t):
			out[t] = PackedStringArray()
		if not out[t].has(ti):
			out[t].append(ti)
	return out


## Tipos con esquema (solo ros2_vita; en rclgd, vacío: allí manda el grafo).
static func tipos_conocidos() -> PackedStringArray:
	if ClassDB.class_has_method("RosMsg", "list_types"):
		return PackedStringArray(ClassDB.class_call_static("RosMsg", "list_types"))
	return PackedStringArray()


## Crea el display de RegistroDisplays para (topic, tipo), lo cuelga de `padre` (o `destino`, o el visor) y lo conecta.
## Sin `owner`: no se guarda en la escena. null en la Vita (D9) o si no hay display para el tipo.
func anadir_display(topic: String, tipo: String, padre: Node = null) -> Node:
	if visor == null or visor.en_vita:
		return null
	var d: Node = Registro.crear(topic, tipo, false)
	if d == null:
		return null
	d.name = "Explorado_" + topic.trim_prefix("/").replace("/", "_")
	var p: Node = padre if padre != null else (destino if destino != null else visor)
	p.add_child(d)
	if visor.ros_listo:
		d.conectar(visor)
		visor.displays.append(d)
	anadidos.append(d)
	return d


## Quita un display añadido en ejecución.
func quitar_display(d: Node) -> void:
	if not anadidos.has(d):
		return
	anadidos.erase(d)
	if visor != null:
		visor.displays.erase(d)
	if d.has_method("desconectar"):
		d.desconectar()
	d.queue_free()
