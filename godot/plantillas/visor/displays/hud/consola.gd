extends "res://comun/visor/display_ros_hud.gd"
## Consola (doc 36a §4.8.2, ficha hmi#8; tarea V6): `rcl_interfaces/msg/Log` = `/rosout` en la pestaña Consola.
## Líneas coloreadas por nivel (10 D, 20 I, 30 W, 40 E, 50 F), la más nueva abajo; filtro por nivel mínimo y por
## subcadena del nombre del nodo; `pausado` congela la vista.
##
## PC: `/rosout` directo (los emisores publican fiable + TRANSIENT_LOCAL; aquí fiable y volátil, sin historial).
## Vita: relay `<p>/rosout` (VC/1 rev. 2, `docker/scripts/vita_relay.py` módulo `rosout`) = el MISMO tipo `Log`, solo
## ≥ WARN, `file`/`function` vacíos, `msg` ≤ 200 car., ≤ 10/s y fiable (⚖ un aviso perdido no se repite). El widget
## no cambia, solo el topic. Es un widget de EVENTOS: no caduca (`caducidad_s = 0`) y entrega todos los mensajes
## (`canal.coalescer = false`, con tope de pendientes para la pestaña oculta).
##
## Presupuesto (⚖ D6): pestaña Consola = **6 líneas × 40 caracteres = 240 *quads*** (todo el cupo de la pestaña: sin
## fondo; el texto = 1 *quad* por carácter). Los mismos números en el PC (un solo camino de código; la escena puede
## subirlos en el PC, pero entonces la pestaña declara de más). Gate G-W13-H0 antes de fijar filas; prueba de
## hardware de V6: 20 avisos/s durante 5 min, FPS sin bajar de escalón y `reliable_dropped` = 0.
##
## datos = true (las líneas viven en `lineas`: [nivel, texto]).

const LETRA := {10: "D", 20: "I", 30: "W", 40: "E", 50: "F"}

@export var max_lineas := 6
@export var max_car := 40
@export var nivel_minimo := 30                 # WARN, como el relay (en el PC se puede bajar a 20 = INFO)
@export var filtro_nodo := ""                  # subcadena del nombre del nodo ("" = todos)
@export var alto_linea := 14.0

var lineas: Array = []                         # [nivel, texto] de la más vieja a la más nueva (≤ max_lineas)
var pausado := false
var filtrados := 0                             # mensajes que no pasaron el filtro (nivel o nodo)


static func nombre_display() -> String:
	return "Consola"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["rcl_interfaces/msg/Log"])


func _init() -> void:
	topic = "/rosout"
	tipo = "rcl_interfaces/msg/Log"
	topic_vita = "rosout"
	tipo_vita = "rcl_interfaces/msg/Log"
	fiabilidad = 2                             # FIABLE (doc 36 §6: eventos; profundidad 10 PC / 5 Vita)
	caducidad_s = 0.0                          # eventos: no caduca


func conectar(v) -> void:
	canal.coalescer = false                    # cada aviso es un evento: se entregan todos
	canal.max_pendientes = max_lineas * 2      # con la pestaña oculta solo interesan los últimos
	super.conectar(v)


## Letra del nivel (los niveles intermedios caen en el inferior: 35 → W).
static func letra(nivel: int) -> String:
	var l := "?"
	for k in [10, 20, 30, 40, 50]:
		if nivel >= k:
			l = LETRA[k]
	return l


func color_nivel(nivel: int) -> Color:
	if nivel >= 40:
		return COLOR_ERROR
	if nivel >= 30:
		return COLOR_AVISO
	return COLOR_TEXTO if nivel >= 20 else COLOR_CADUCADO


func _procesar(msg):
	var nivel := int(msg.get_member("level"))
	var nodo := String(msg.get_member("name"))        # get_member: `name` choca con propiedades de Object (T1)
	if nivel < nivel_minimo or (filtro_nodo != "" and not nodo.contains(filtro_nodo)):
		filtrados += 1
		return null
	if pausado:
		return null
	var txt := String(msg.get_member("msg")).replace("\n", " ").replace("\t", " ")
	lineas.append([nivel, ("%s %s: %s" % [letra(nivel), nodo, txt]).left(max_car)])
	while lineas.size() > max_lineas:
		lineas.remove_at(0)
	return true


func _dibujar() -> bool:
	if lineas.is_empty():
		texto(Vector2(4, alto_linea), "rosout ...", color_estado(COLOR_CADUCADO), max_car)
		return true
	var y := alto_linea
	for l in lineas:
		texto(Vector2(4, y), l[1], color_estado(color_nivel(l[0])), max_car)
		y += alto_linea
	return true


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": max_lineas * max_car}
