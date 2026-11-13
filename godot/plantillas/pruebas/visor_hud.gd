extends SceneTree
## Prueba de host del HUD del visor (V4; doc 36 §7.2 y §10; sentencia W13 D6). Transporte `loopback` (sin red):
##   - GestorHud: barra fija + una pestaña visible; la oculta no se dibuja ni procesa; recuento de glifos y quads
##     por zona: barra ≤ 120 y pestaña ≤ 240 (declarado y dibujado), aviso si una pestaña declara de más;
##   - cada widget recibe su mensaje y pinta sin errores de script (un `Logger` cuenta los errores de `visor/`);
##   - casos NaN (T2) de batería, medidor y mando;
##   - `main.tscn` con el HUD colocado como nodos (regla doc 35).
##
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_hud.gd
##
## Desde V5 (`TIPOS_VISOR` en `generar_esquemas.py --visor`) `sensor_msgs/Joy`, `Temperature`, `Illuminance`,
## `RelativeHumidity`, `action_msgs/GoalStatusArray` y `nav2_msgs/action/NavigateToPose_FeedbackMessage` tienen
## esquema `.rsch` y el canal suscribe («ok»); el contenido de esos widgets se sigue probando entregándoles un mensaje
## falso con los mismos campos (`Falso`); la ida y vuelta CDR de los tipos reales está en `pruebas/visor_directos.gd`.
## Por loopback de verdad: `BatteryState`, `FluidPressure` y `Float32MultiArray` (camino compacto).
## «Sin esquema» (T20) se comprueba en `pruebas/visor.gd` con un tipo falso.

const VisorRos = preload("res://comun/visor/visor_ros.gd")
const GestorHud = preload("res://comun/visor/gestor_hud.gd")
const Bateria = preload("res://comun/visor/displays/hud/bateria.gd")
const Medidor = preload("res://comun/visor/displays/hud/medidor.gd")
const Joy = preload("res://comun/visor/displays/hud/joy.gd")
const EstadoMeta = preload("res://comun/visor/displays/hud/estado_meta.gd")
const BarraEstado = preload("res://comun/visor/displays/hud/barra_estado.gd")


## Mensaje de prueba con los campos de un RosMsg (acceso `m.campo` por `_get` y `m.get_member("campo")`).
class Falso:
	extends RefCounted
	var _m := {}

	func _init(m: Dictionary) -> void:
		_m = m

	func get_member(n: String):
		return _m.get(n)

	func _get(n: StringName):
		return _m.get(String(n))


## Cuenta los errores de script y los avisos del GestorHud (Godot ≥ 4.5: `Logger`).
class Vigia:
	extends Logger
	var errores_visor := 0
	var avisos_gestor := 0
	var ultimo := ""

	func _log_error(_f: String, file: String, _l: int, code: String, rationale: String, _e: bool, tipo: int,
			_b: Array[ScriptBacktrace]) -> void:
		var texto := code + " " + rationale
		if texto.contains("GestorHud"):
			avisos_gestor += 1
		elif tipo == ERROR_TYPE_SCRIPT or (tipo == ERROR_TYPE_ERROR and file.contains("/visor/")):
			errores_visor += 1
			ultimo = "%s: %s" % [file, texto]

	func _log_message(_m: String, _e: bool) -> void:
		pass


var fallos := 0
var pruebas := 0
var vigia := Vigia.new()


func check(condicion: bool, nombre: String) -> void:
	pruebas += 1
	if not condicion:
		fallos += 1
		push_error(nombre)
	else:
		print("OK ", nombre)


func _init() -> void:
	OS.add_logger(vigia)
	_correr.call_deferred()


func _correr() -> void:
	await _probar_hud()
	await _probar_main()
	check(vigia.errores_visor == 0, "sin errores de script en visor/ (%s)" % vigia.ultimo)
	OS.remove_logger(vigia)
	print("RESULTADO: ", pruebas - fallos, "/", pruebas)
	quit(0 if fallos == 0 else 1)


# ---------------------------------------------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------------------------------------------
func _ctl(script, nombre: String, pos: Vector2, tam: Vector2, props := {}) -> Control:
	var c: Control = Control.new() if script == null else script.new()
	c.name = nombre
	c.position = pos
	c.size = tam
	for k in props:
		c.set(k, props[k])
	return c


func _fotogramas(n: int) -> void:
	for _i in n:
		await process_frame


func _esperar_conexion(v: Node) -> void:
	for _i in 60:
		if v.estado != "sin conectar":
			return
		await process_frame


func _medidor(nombre: String, y: float, topic: String, tipo: String, campo: String, props := {}) -> Control:
	var p := {"topic": topic, "tipo": tipo, "campo": campo, "etiqueta": nombre.left(4), "hz": 0.0}
	p.merge(props, true)
	return _ctl(Medidor, nombre, Vector2(0, y), Vector2(320, 72), p)


func _bateria_msg(pct: float, carga: float, cap: float, salud: int):
	var m = RosMsg.from_type("sensor_msgs/msg/BatteryState")
	m.percentage = pct
	m.charge = carga
	m.capacity = cap
	m.voltage = 12.3
	m.current = -1.2
	m.power_supply_status = 2
	m.power_supply_health = salud
	return m


func _presion_msg(pa: float):
	var m = RosMsg.from_type("sensor_msgs/msg/FluidPressure")
	m.fluid_pressure = pa
	return m


func _estado_meta(sec: int, st: int) -> Falso:
	return Falso.new({"status": st, "goal_info": Falso.new({"stamp": Falso.new({"sec": sec, "nanosec": 0})})})


func _suscrito(w: Node) -> bool:
	return w.estado == "ok" and w.canal.abierto()


# ---------------------------------------------------------------------------------------------------------------
# HUD montado en código: barra (batería, meta, estado) + pestañas Estado (6 medidores), Mando (Joy) y Sobrecarga
# ---------------------------------------------------------------------------------------------------------------
func _probar_hud() -> void:
	var v: Node = VisorRos.new()
	v.name = "VisorPrueba"
	v.transporte = "loopback"
	v.config_json = ""
	v.reintento_s = 0.0
	var capa := CanvasLayer.new()
	capa.name = "Hud"
	v.add_child(capa)
	var g: Control = _ctl(GestorHud, "GestorHud", Vector2.ZERO, Vector2(960, 544), {"avisar_en_pc": true})
	capa.add_child(g)
	var barra := _ctl(null, "Barra", Vector2.ZERO, Vector2(960, 24))
	var tabs := _ctl(null, "Pestanas", Vector2(640, 24), Vector2(320, 496))
	g.add_child(barra)
	g.add_child(tabs)
	g.barra = barra
	g.pestanas = tabs

	var bat := _ctl(Bateria, "Bateria", Vector2.ZERO, Vector2(240, 24),
			{"topic": "/battery_state", "tipo": "sensor_msgs/msg/BatteryState", "hz": 0.0})
	var meta := _ctl(EstadoMeta, "Meta", Vector2(240, 0), Vector2(300, 24), {"hz": 0.0})
	var est := _ctl(BarraEstado, "Estado", Vector2(540, 0), Vector2(420, 24), {"herramienta": "meta"})
	for w in [bat, meta, est]:
		barra.add_child(w)

	var tab_estado := _ctl(null, "Estado", Vector2.ZERO, Vector2(320, 496))
	var temp := _medidor("Temperatura", 0, "/temperature", "sensor_msgs/msg/Temperature", "temperature")
	var pres := _medidor("Presion", 80, "/barometer", "sensor_msgs/msg/FluidPressure", "fluid_pressure",
			{"escala": 0.01, "unidad": "hPa", "minimo": 950.0, "maximo": 1050.0, "aviso": 1040.0})
	var ilum := _medidor("Iluminancia", 160, "/illuminance", "sensor_msgs/msg/Illuminance", "illuminance",
			{"unidad": "lx", "minimo": 0.0, "maximo": 2000.0, "aviso": 1500.0})
	var hum := _medidor("Humedad", 240, "/humidity", "sensor_msgs/msg/RelativeHumidity", "relative_humidity",
			{"escala": 100.0, "unidad": "%", "minimo": 0.0, "maximo": 100.0, "aviso": 80.0})
	var pres2 := _medidor("Presion2", 320, "/barometer", "sensor_msgs/msg/FluidPressure", "fluid_pressure",
			{"escala": 0.01, "unidad": "hPa", "minimo": 950.0, "maximo": 1050.0, "aviso": 1000.0})
	var temp2 := _medidor("Temp2", 400, "/temperature", "sensor_msgs/msg/Temperature", "temperature")
	for w in [temp, pres, ilum, hum, pres2, temp2]:
		tab_estado.add_child(w)
	tabs.add_child(tab_estado)

	var tab_mando := _ctl(null, "Mando", Vector2.ZERO, Vector2(320, 496))
	var joy := _ctl(Joy, "Joy", Vector2.ZERO, Vector2(320, 160), {"hz": 0.0})
	tab_mando.add_child(joy)
	tabs.add_child(tab_mando)

	var tab_mucho := _ctl(null, "Sobrecarga", Vector2.ZERO, Vector2(320, 496))
	for i in 7:
		tab_mucho.add_child(_medidor("M%d" % i, i * 70, "/barometer", "sensor_msgs/msg/FluidPressure", "fluid_pressure"))
	tabs.add_child(tab_mucho)
	est.vigilado = pres

	root.add_child(v)
	await _esperar_conexion(v)
	check(v.ros_listo, "HUD: el visor arranca en loopback")
	check(v.displays.size() == 3 + 6 + 1 + 7, "HUD: VisorRos conecta los 17 widgets (también los de pestañas ocultas)")
	check(g.num_pestanas() == 3 and g.activa == 0 and g.pestana_activa() == "Estado", "gestor: 3 pestañas, Estado activa")
	check(tab_estado.visible and not tab_mando.visible and not tab_mucho.visible, "gestor: una sola pestaña visible")
	check(tab_mando.process_mode == Node.PROCESS_MODE_DISABLED, "gestor: la pestaña oculta no procesa")

	# Estados: todos con esquema desde V5 (TIPOS_VISOR) ⇒ suscritos.
	check(bat.estado == "ok" and pres.estado == "ok", "estado: BatteryState y FluidPressure suscritos")
	check(_suscrito(temp), "V5: Temperature con esquema, suscrito")
	check(_suscrito(ilum), "V5: Illuminance con esquema, suscrito")
	check(_suscrito(hum), "V5: RelativeHumidity con esquema, suscrito")
	check(_suscrito(joy) and joy.canal.topic_abierto != "", "V5: Joy con esquema, suscrito")
	check(_suscrito(meta) and meta.topic == "/navigate_to_pose/_action/status",
			"V5: GoalStatusArray con esquema; topic oculto de la acción")
	check(meta.estado_feedback == "ok" and meta.canal_fb.abierto(),
			"V5: FeedbackMessage de NavigateToPose con esquema (registro manual), suscrito")
	check(est.estado == "sin topic", "barra de estado: sin topic propio (relay_bw opcional)")

	# Mensajes reales por loopback.
	var nodo = v.contexto.nodo
	var be = v.contexto.qos(true, 1, false)
	var pub_bat = nodo.create_publisher("/battery_state", "sensor_msgs/msg/BatteryState", be)
	var pub_pres = nodo.create_publisher("/barometer", "sensor_msgs/msg/FluidPressure", be)
	pub_bat.publish(_bateria_msg(0.5, NAN, NAN, 1))
	pub_pres.publish(_presion_msg(101325.0))
	await _fotogramas(3)
	check(bat.datos != null and is_equal_approx(bat.datos[0], 0.5) and not bat.datos[2], "batería: 50 %, sin alarma")
	check(String(bat.datos[1]).begins_with("12.3 V -1.2 A descarga"), "batería: texto «%s»" % bat.datos[1])
	check(pres.datos != null and absf(pres.datos - 1013.25) < 0.01, "medidor: FluidPressure 1013,25 hPa")
	check(pres.color_valor(pres.datos) == pres.COLOR_OK and pres2.color_valor(pres2.datos) == pres2.COLOR_AVISO,
			"medidor: umbrales OK / AVISO")

	# Sin esquema: se entrega un mensaje falso con los mismos campos.
	for i in 30:                                   # serie llena (24 muestras): la sparkline pinta 23 segmentos
		temp._al_mensaje(Falso.new({"temperature": 20.0 + i * 0.1, "variance": 0.0}))
	temp._al_mensaje(Falso.new({"temperature": 23.5, "variance": 0.0}))
	temp2._al_mensaje(Falso.new({"temperature": NAN, "variance": 0.0}))
	ilum._al_mensaje(Falso.new({"illuminance": 1800.0, "variance": 0.0}))
	hum._al_mensaje(Falso.new({"relative_humidity": 0.42, "variance": 0.0}))
	check(is_equal_approx(temp.datos, 23.5) and absf(hum.datos - 42.0) < 0.001, "medidor: Temperature y RelativeHumidity (escala 100)")
	check(is_nan(temp2.datos) and temp2._serie.is_empty(), "medidor: NaN = «—» y no entra en la serie (T2)")
	check(temp._serie.size() == temp.muestras, "medidor: la serie se queda en `muestras`")
	check(ilum.color_valor(ilum.datos) == ilum.COLOR_AVISO, "medidor: Illuminance en aviso")
	meta._al_mensaje(Falso.new({"status_list": [_estado_meta(10, 4), _estado_meta(20, 2), _estado_meta(5, 6)]}))
	check(meta.fase_texto == "ejecutando", "meta: se elige la meta más reciente (stamp 20, EXECUTING)")
	meta._al_feedback(Falso.new({"feedback": Falso.new({"distance_remaining": 3.25,
			"estimated_time_remaining": Falso.new({"sec": 12, "nanosec": 0}), "number_of_recoveries": 1})}))
	check(is_equal_approx(meta.distancia, 3.25) and is_equal_approx(meta.eta, 12.0) and meta.recuperaciones == 1,
			"meta: feedback (distancia, ETA, recuperaciones)")
	var ejes := PackedFloat32Array([0.5, NAN, 0.0, -2.0, 1.0, 0.0, 0.0, 0.0])
	var botones := PackedInt32Array([1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1])   # 19 > 17
	joy._al_mensaje(Falso.new({"axes": ejes, "buttons": botones}))
	check(joy.datos[0][1] == 0.0 and joy.datos[0][3] == -1.0, "joy: eje NaN = 0 y fuera de rango recortado")
	check(joy.datos[1].size() == 17 and joy.datos[1][0] == 1, "joy: como mucho 17 botones")

	await _fotogramas(4)
	check(vigia.errores_visor == 0, "pintan sin errores de script (%s)" % vigia.ultimo)
	for w in [bat, meta, est, temp, pres, ilum, hum, pres2, temp2]:
		check(w.dibujos >= 1 and w.quads_dibujados <= int(w._coste()["quads"]),
				"dibuja %s: %d quads ≤ %d declarados" % [w.name, w.quads_dibujados, w._coste()["quads"]])
	check(joy.dibujos == 0 and tab_mucho.get_child(0).dibujos == 0, "la pestaña oculta no se dibuja")
	check(est.linea_texto.contains("Presion") and est.linea_texto.contains("Hz") and est.linea_texto.contains("meta"),
			"barra de estado: «%s»" % est.linea_texto)

	var inf: Dictionary = g.informe()
	print("[hud] Estado: ", inf)
	check(inf["barra_declarados"] <= g.BARRA_MAX, "barra: %d quads declarados ≤ 120" % inf["barra_declarados"])
	check(inf["barra_quads"] <= g.BARRA_MAX and inf["barra_glifos"] <= g.BARRA_MAX,
			"barra: %d quads y %d glifos dibujados ≤ 120" % [inf["barra_quads"], inf["barra_glifos"]])
	check(inf["barra_glifos"] > 0, "barra: hay texto")
	check(inf["pestana_declarados"] <= g.PESTANA_MAX, "pestaña Estado: %d quads declarados ≤ 240" % inf["pestana_declarados"])
	check(inf["pestana_quads"] <= g.PESTANA_MAX and inf["pestana_glifos"] <= g.PESTANA_MAX,
			"pestaña Estado: %d quads y %d glifos dibujados ≤ 240" % [inf["pestana_quads"], inf["pestana_glifos"]])
	check(inf["barra_declarados"] + inf["pestana_declarados"] + 40 <= g.HUD_MAX, "HUD: barra + pestaña + 40 de texto ≤ 400")
	check(vigia.avisos_gestor == 0, "gestor: sin avisos de cupo con barra y Estado")

	# NaN y alarmas de batería.
	pub_bat.publish(_bateria_msg(NAN, 2.0, 4.0, 1))
	await _fotogramas(3)
	check(is_equal_approx(bat.datos[0], 0.5), "batería: percentage NaN → charge/capacity")
	pub_bat.publish(_bateria_msg(NAN, NAN, 0.0, 1))
	await _fotogramas(3)
	check(is_nan(bat.datos[0]) and not bat.datos[2], "batería: sin % (NaN) y sin alarma")
	pub_bat.publish(_bateria_msg(0.9, NAN, NAN, 3))
	await _fotogramas(3)
	check(bat.datos[2], "batería: salud mala (DEAD) = alarma")
	pub_bat.publish(_bateria_msg(0.1, NAN, NAN, 1))
	await _fotogramas(3)
	check(bat.datos[2] and bat.dibujos >= 4, "batería: < 20 % = alarma; redibuja con cada mensaje")

	# Camino compacto del puente VAB/1 (docs/32:51, :61) con un Float32MultiArray real.
	var fm = RosMsg.from_type("std_msgs/msg/Float32MultiArray")
	var d := PackedFloat32Array()
	d.resize(24)
	d[7] = 4.0
	d[14] = 7.5
	d[15] = 30.0
	d[16] = 2.0
	fm.data = d
	check(meta._procesar_compacto(fm) == "ejecutando" and is_equal_approx(meta.distancia, 7.5) and meta.recuperaciones == 2,
			"meta: estado compacto del puente (fase 4 = ejecutando)")
	d[7] = 7.0
	fm.data = d
	meta._procesar_compacto(fm)
	check(meta.fase_texto == "LLEGÓ" and meta.fase_color == meta.COLOR_OK, "meta: fase 7 del puente = LLEGÓ")

	# Cambio de pestaña: Mando visible; Estado oculta y sin procesar (su canal no entrega).
	g.siguiente()
	check(g.activa == 1 and tab_mando.visible and not tab_estado.visible, "gestor: siguiente() → Mando")
	check(tab_estado.process_mode == Node.PROCESS_MODE_DISABLED and tab_mando.process_mode == Node.PROCESS_MODE_INHERIT,
			"gestor: Estado deja de procesar")
	var vistos: int = pres.canal.mostrados
	pub_pres.publish(_presion_msg(99000.0))
	await _fotogramas(4)
	check(pres.canal.recibidos >= 2 and pres.canal.mostrados == vistos, "pestaña oculta: llega pero no se entrega")
	check(joy.dibujos >= 1 and joy.quads_dibujados <= int(joy._coste()["quads"]),
			"dibuja Joy: %d quads ≤ %d declarados" % [joy.quads_dibujados, joy._coste()["quads"]])
	inf = g.informe()
	print("[hud] Mando: ", inf)
	check(inf["pestana"] == "Mando" and inf["pestana_declarados"] <= g.PESTANA_MAX and inf["pestana_quads"] <= g.PESTANA_MAX
			and inf["pestana_glifos"] <= g.PESTANA_MAX, "pestaña Mando: %d quads ≤ 240" % inf["pestana_quads"])
	check(vigia.errores_visor == 0, "Joy pinta sin errores (%s)" % vigia.ultimo)

	# Sobrecarga: 7 medidores = 280 > 240 → aviso (una vez); la vuelta atrás con anterior().
	g.siguiente()
	check(g.pestana_activa() == "Sobrecarga" and g.quads_declarados(tab_mucho) > g.PESTANA_MAX,
			"gestor: Sobrecarga declara %d > 240" % g.quads_declarados(tab_mucho))
	check(vigia.avisos_gestor == 1, "gestor: avisa de la pestaña que pasa del cupo")
	g.siguiente()
	g.siguiente()
	g.siguiente()
	check(g.pestana_activa() == "Sobrecarga" and vigia.avisos_gestor == 1, "gestor: con vuelta, y el aviso una sola vez")
	g.anterior()
	g.anterior()
	check(g.pestana_activa() == "Estado", "gestor: anterior() vuelve a Estado")
	await _fotogramas(3)
	check(pres.canal.mostrados == vistos + 1 and absf(pres.datos - 990.0) < 0.01,
			"pestaña visible otra vez: entrega lo que llegó mientras estaba oculta")

	pub_bat = null
	pub_pres = null
	v.queue_free()
	await _fotogramas(2)


# ---------------------------------------------------------------------------------------------------------------
# main.tscn: el HUD está en la escena (doc 35) y cumple el cupo
# ---------------------------------------------------------------------------------------------------------------
func _probar_main() -> void:
	var escena: Node = load("res://main.tscn").instantiate()
	var v: Node = escena.get_node("VisorRos")
	v.transporte = "loopback"
	v.reintento_s = 0.0
	root.add_child(escena)
	await _esperar_conexion(v)
	var g: Node = escena.get_node_or_null("VisorRos/Hud/GestorHud")
	check(g != null and g.num_pestanas() >= 2 and g.pestana_activa() == "Estado", "main.tscn: GestorHud con pestañas")
	if g == null:
		escena.queue_free()
		return
	var bat: Node = g.barra.get_node("Bateria")
	var pub = v.contexto.nodo.create_publisher("/battery_state", "sensor_msgs/msg/BatteryState", v.contexto.qos(true, 1, false))
	pub.publish(_bateria_msg(0.8, NAN, NAN, 1))
	await _fotogramas(4)
	check(bat.estado == "ok" and bat.datos != null and bat.dibujos >= 1, "main.tscn: la batería de la barra recibe y pinta")
	check(g.quads_declarados(g.barra) <= g.BARRA_MAX, "main.tscn: barra %d ≤ 120" % g.quads_declarados(g.barra))
	for i in g.num_pestanas():
		var p: Control = g.pestana(i)
		check(g.quads_declarados(p) <= g.PESTANA_MAX, "main.tscn: pestaña %s %d ≤ 240" % [p.name, g.quads_declarados(p)])
	var inf: Dictionary = g.informe()
	print("[hud] main.tscn: ", inf)
	check(inf["barra_glifos"] <= g.BARRA_MAX and inf["pestana_glifos"] <= g.PESTANA_MAX, "main.tscn: glifos dentro del cupo")
	pub = null
	escena.queue_free()
	await _fotogramas(2)
