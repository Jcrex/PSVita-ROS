extends RefCounted
## IntrospeccionRos (doc 36 §1.1; doc 36a §4.1.1, ficha nucleo#0; tarea V12): campos de un RosMsg, portable
## rclgd (dinámico o tipado) ↔ ros2_vita (dinámico). Estático:
## `const Intro = preload("res://comun/visor/introspeccion_ros.gd")`.
##
## - rclgd no tiene `to_dict()` (`godot/rclgd/rclgd/src/rclgd/ros_msg.cpp:122-149`): la lista de campos sale de
##   `ClassDB.class_get_property_list(clase, true)` en las clases tipadas y de `get_property_list()` en el RosMsg
##   dinámico, **una vez por tipo y sobre un prototipo vacío** (en rclgd `get_property_list()` convierte cada miembro,
##   `ros_msg.cpp:285-301`: nunca sobre un `Image` de 1 MB). Caché por tipo en `_cache`.
## - Los valores se leen SIEMPRE con `get_member` (los campos con nombre reservado, p. ej. `reference` de
##   `control_msgs/JointTrajectoryControllerState`, chocan con `RefCounted.reference()` y `m.reference` es un
##   `Callable`, doc 36 §1.1 y §8).
## - Rutas con la sintaxis de Foxglove: `/odom.twist.twist.linear.x` (el punto no puede ir en un nombre de topic,
##   así que el topic es lo que hay antes del primer punto) y corchetes para índices: `poses[3].pose.position.x`.

const _OMITIR := {"script": true}
const _NO_CAMPO := PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP

static var _cache := {}                        # tipo -> PackedStringArray
static var prototipos_creados := 0             # para las pruebas: cuántas veces se fue al prototipo (sin caché)


## Nombres de los campos del tipo, en el orden del `.msg`. Vacío si el tipo no tiene esquema/typesupport.
static func campos_de_tipo(tipo: String) -> PackedStringArray:
	if _cache.has(tipo):
		return _cache[tipo]
	var out := PackedStringArray()
	var proto = RosMsg.from_type(tipo)
	if proto == null:
		return out                             # sin caché: el esquema puede cargarse después
	prototipos_creados += 1
	var clase: String = proto.get_class()
	var lista: Array = ClassDB.class_get_property_list(clase, true) if clase != "RosMsg" else proto.get_property_list()
	for p in lista:
		if p.usage & _NO_CAMPO or _OMITIR.has(p.name):
			continue
		out.append(p.name)
	_cache[tipo] = out
	return out


static func campos(msg) -> PackedStringArray:
	return campos_de_tipo(msg.get_ros_interface_name())


static func olvidar_cache() -> void:
	_cache.clear()


## Ruta troceada: ["twist", "twist", "linear", "x"] o ["poses", "3", "pose"].
static func leer_ruta(msg, ruta: PackedStringArray):
	var v = msg
	for paso in ruta:
		if v is RosMsg:
			v = v.get_member(StringName(paso))
		elif v != null and typeof(v) >= TYPE_ARRAY and paso.is_valid_int() and paso.to_int() >= 0 \
				and paso.to_int() < v.size():
			v = v[paso.to_int()]
		else:
			return null
	return v


## "twist.twist.linear.x" o "poses[3].pose" → ["twist", "twist", "linear", "x"] / ["poses", "3", "pose"].
static func trocear(campo: String) -> PackedStringArray:
	var out := PackedStringArray()
	for p in campo.replace("[", ".").replace("]", "").split(".", false):
		out.append(p)
	return out


## Ruta de Foxglove → {"topic": "/odom", "campos": PackedStringArray}. Sin «/» inicial = solo campos (topic "").
static func partir_ruta(ruta: String) -> Dictionary:
	var r := ruta.strip_edges()
	if not r.begins_with("/"):
		return {"topic": "", "campos": trocear(r)}
	var i := r.find(".")
	var j := r.find("[")
	if j >= 0 and (i < 0 or j < i):
		i = j
	if i < 0:
		return {"topic": r, "campos": PackedStringArray()}
	return {"topic": r.left(i), "campos": trocear(r.substr(i))}


## Inversa de `partir_ruta`: (topic, ["poses", "3", "x"]) → "/topic.poses[3].x".
static func unir_ruta(topic: String, trozos: PackedStringArray) -> String:
	var s := topic
	for t in trozos:
		s += ("[%s]" % t) if t.is_valid_int() else ("." + t if s != "" else t)
	return s


## Rutas numéricas hoja del tipo (para ofrecer campos al trazador), recorriendo submensajes del prototipo hasta
## `profundidad` niveles. Sin arrays (su longitud no se conoce en el prototipo). Coste: solo al elegir campos.
static func rutas_numericas(tipo: String, profundidad := 4) -> PackedStringArray:
	var out := PackedStringArray()
	var proto = RosMsg.from_type(tipo)
	if proto != null:
		_rutas(proto, "", profundidad, out)
	return out


static func _rutas(m, prefijo: String, nivel: int, out: PackedStringArray) -> void:
	if nivel <= 0:
		return
	for c in campos(m):
		var v = m.get_member(StringName(c))
		var r := c if prefijo == "" else prefijo + "." + c
		if v is RosMsg:
			_rutas(v, r, nivel - 1, out)
		elif v is float or v is int or v is bool:
			out.append(r)
