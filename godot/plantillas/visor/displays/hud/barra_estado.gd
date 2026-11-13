extends "res://comun/visor/display_ros_hud.gd"
## Barra de estado (doc 36a §4.1.10, ficha nucleo#16 → sentencia W13 D6): enlace + Hz del display vigilado +
## herramienta activa, en la barra fija. La batería y la meta son widgets hermanos (bateria.gd, estado_meta.gd).
##
## Fuentes:
##   - enlace: `rclgd.get_transport_info()` (solo `ros2_vita`; por `has_method` + `call`, T7): paquetes/s leídos,
##     `be_dropped` y `reconexiones`; con rclgd, el nombre del transporte del contexto;
##   - Hz: `canal.hz_medido` del display `vigilado` (p. ej. el scan); sin vigilado, cuántos displays del visor no
##     están «ok»;
##   - `herramienta`: la fija la app (o la herramienta activa, V7);
##   - opcional `<p>/relay_bw` (`topic_vita = "relay_bw"`, `Float32MultiArray` [bytes/s, mensajes/s],
##     `docker/scripts/vita_relay.py:19`): KB/s del relay. En el PC ese topic no existe: sin `topic` no suscribe.
## Sin contadores por suscripción hasta V13 (P2). Refresco cada `periodo_s` (2 Hz) y redibujo solo si cambia el texto.
##
## Coste: texto ≤ MAX_CAR = 40 *quads*.

const MAX_CAR := 40

@export var vigilado: Node                     # display cuyo Hz se muestra
@export var herramienta := ""
@export var periodo_s := 0.5

var linea_texto := ""
var relay_kbs := NAN
var _t := 0.0
var _paquetes := -1
var _t_paquetes := 0


static func nombre_display() -> String:
	return "BarraEstado"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray()


func _init() -> void:
	caducidad_s = 0.0                          # la barra no tiene dato propio que caduque
	_t = 1000.0                                # primer refresco en el primer _process


func _process(dt: float) -> void:
	super._process(dt)
	_t += dt
	if _t < periodo_s:
		return
	_t = 0.0
	var nuevo := componer()
	if nuevo != linea_texto:
		linea_texto = nuevo
		queue_redraw()


## Texto de la barra (también para las pruebas).
func componer() -> String:
	var partes := PackedStringArray()
	if visor == null:
		partes.append("ROS ...")
	elif not visor.ros_listo:
		partes.append("ROS caído")
	else:
		partes.append(_enlace())
	if vigilado != null and "canal" in vigilado:
		partes.append("%s %.0fHz" % [vigilado.name, vigilado.canal.hz_medido])
	elif visor != null:
		var mal := 0
		for d in visor.displays:
			if is_instance_valid(d) and d.estado != "ok" and d.estado != "desactivado" and d != self:
				mal += 1
		if mal > 0:
			partes.append("%d sin dato" % mal)
	if not is_nan(relay_kbs):
		partes.append("relay %.1fKB/s" % relay_kbs)
	if herramienta != "":
		partes.append(herramienta)
	return " | ".join(partes)


func _enlace() -> String:
	if not rclgd.has_method("get_transport_info"):
		return String(visor.contexto.transporte) if visor.contexto.transporte != "" else "rclgd"
	var info: Dictionary = rclgd.call("get_transport_info")
	if info.is_empty():                         # ros2_vita sin XRCE (loopback): no hay diagnóstico
		return String(visor.contexto.transporte)
	var ahora := Time.get_ticks_msec()
	var pk := int(info.get("read_packets", 0))
	var txt := "XRCE"
	if _paquetes >= 0 and ahora > _t_paquetes:
		txt += " %.0fp/s" % ((pk - _paquetes) * 1000.0 / (ahora - _t_paquetes))
	_paquetes = pk
	_t_paquetes = ahora
	txt += " perd %d" % int(info.get("be_dropped", 0))
	var rec := int(info.get("reconexiones", 0))
	if rec > 0:
		txt += " rx%d" % rec
	return txt


## relay_bw: [bytes/s, mensajes/s] → KB/s (mismo formato por los dos caminos).
func _procesar(msg):
	var d = msg.data
	if d.size() < 1:
		return null
	relay_kbs = float(d[0]) / 1024.0
	_t = periodo_s                             # recomponer en el próximo fotograma
	return relay_kbs


func _pintar(_d) -> void:
	pass                                       # redibuja _process cuando cambia el texto


func _dibujar() -> bool:
	texto(Vector2(4, size.y - 7), linea_texto, COLOR_TEXTO, MAX_CAR)
	return true


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": MAX_CAR}
