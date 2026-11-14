extends SceneTree
## Prueba de host de V6 (relay VC/1 rev. 2: base + `rosout`, `diag`, `ritmo`; doc 36 §5 y §10; sentencia W13 D5–D6).
## Transporte `loopback` (sin red):
##   - `ros/vc1.gd` rev. 2: `cabecera()` (válidas e inválidas), `trocear()` = `vita_relay_formatos.trocear` (las
##     mismas huellas que `docker/scripts/test_vita_relay.py`; la prueba de registro es la de `pruebas/runner.gd`),
##     `leer_relay_info()`, y que los formatos VC/1 de siempre siguen leyéndose igual;
##   - Consola (`rcl_interfaces/msg/Log`): filtro de nivel y de nodo, 6 líneas × 40 car., colores por nivel, eventos
##     sin «el último gana», QoS fiable, camino compacto `<p>/rosout`, pausa, tope de pendientes con la pestaña oculta;
##   - Diagnóstico (`DiagnosticArray`): un estado por mensaje (como el relay), de peor a mejor, STALE por fila,
##     «solo problemas» en la Vita, 8 filas, QoS (fiable directo / best effort por el relay), nivel como bytes;
##   - GestorHud: pestañas Consola y Diagnóstico ≤ 240 *quads* (D6), declarado y dibujado;
##   - RegistroDisplays y las pestañas de `main.tscn`.
##
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_relay.gd

const VisorRos = preload("res://comun/visor/visor_ros.gd")
const GestorHud = preload("res://comun/visor/gestor_hud.gd")
const Consola = preload("res://comun/visor/displays/hud/consola.gd")
const Diagnostico = preload("res://comun/visor/displays/hud/diagnostico.gd")
const Registro = preload("res://comun/visor/registro_displays.gd")
const VC1 = preload("res://comun/ros/vc1.gd")
const VitaRelay = preload("res://comun/vita_relay.gd")


## Mensaje falso con los campos de un RosMsg (para casos que el esquema no deja construir, p. ej. nivel en bytes).
class Falso:
	extends RefCounted
	var _m := {}

	func _init(m: Dictionary) -> void:
		_m = m

	func get_member(n: String):
		return _m.get(n)

	func _get(n: StringName):
		return _m.get(String(n))


class Vigia:
	extends Logger
	var errores_visor := 0
	var ultimo := ""

	func _log_error(_f: String, file: String, _l: int, code: String, rationale: String, _e: bool, tipo: int,
			_b: Array[ScriptBacktrace]) -> void:
		if tipo == ERROR_TYPE_SCRIPT or (tipo == ERROR_TYPE_ERROR and file.contains("/visor/")):
			errores_visor += 1
			ultimo = "%s: %s %s" % [file, code, rationale]

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
	_probar_vc1()
	await _probar_consola(false)
	await _probar_consola(true)
	await _probar_diagnostico(false)
	await _probar_diagnostico(true)
	await _probar_main()
	check(vigia.errores_visor == 0, "sin errores de script en visor/ (%s)" % vigia.ultimo)
	OS.remove_logger(vigia)
	print("RESULTADO: ", pruebas - fallos, "/", pruebas)
	quit(0 if fallos == 0 else 1)


# ---------------------------------------------------------------------------------------------------------------
# vc1.gd rev. 2
# ---------------------------------------------------------------------------------------------------------------
func _probar_vc1() -> void:
	check(VC1.MAX_BE == 488 and VC1.MAX_F32 == 118 and VC1.MAX_I16 == 236, "VC/1.2: límites 488 B, 118 floats, 236 int16")
	var c := VC1.cabecera(PackedFloat32Array([40000 & 0x7FFF, 1, 2, 12, 640, 480]))
	check(c.seq == 7232 and c.trozo == 1 and c.n_trozos == 2 and c.n == 12, "cabecera: Float32MultiArray")
	check(VC1.cabecera(PackedInt32Array([5, 0, 1, 0])).n == 0, "cabecera: Int16MultiArray (PackedInt32Array, T6), n = 0")
	check(VC1.cabecera(PackedFloat32Array([1, 2, 2, 0])).is_empty(), "cabecera: trozo ≥ n_trozos = inválida")
	check(VC1.cabecera(PackedFloat32Array([1, 0, 0, 0])).is_empty(), "cabecera: n_trozos 0 = inválida")
	check(VC1.cabecera(PackedFloat32Array([1, 0, 1, -1])).is_empty(), "cabecera: n negativo = inválida")
	check(VC1.cabecera(PackedFloat32Array([1, 0])).is_empty() and VC1.cabecera(null).is_empty(), "cabecera: corta o nula")
	var el := []
	for i in 40:
		el.append([i * 3 - 50, i % 7, 1000 + i, -i])
	var t: Array = VC1.trocear(el, 4, [640, 480], 40000)
	var plano := []
	for x in t:
		plano.append_array(x)
	check(t.size() == 2 and t[0].size() == VC1.MAX_F32 and t[1][3] == 12 and t[1].slice(4, 6) == [640, 480],
			"trocear: 40 elementos = 28 + 12, extra tras la cabecera")
	check(_md5(plano) == "5da842991233e493fd04afd2d9c78df6", "trocear = vita_relay_formatos.trocear (huella cruzada)")
	check(VC1.trocear([], 8) == [[0, 0, 1, 0]], "trocear: vacío = un trozo con n = 0")
	check(VC1.trocear(el + el + el + el + el, 4, [], 1, VC1.MAX_F32, 3).size() == 3, "trocear: corta a 3 trozos")
	var info := VC1.leer_relay_info("VC/1.2;scan,pose,rosout,diag")
	check(info.version == "VC/1.2" and info.modulos == PackedStringArray(["scan", "pose", "rosout", "diag"]),
			"relay_info: versión y módulos")
	check(VC1.leer_relay_info("hola").is_empty() and VC1.leer_relay_info("VC/1.2;").modulos.is_empty(),
			"relay_info: saludo falso / sin módulos")
	# Los formatos VC/1 de siempre no cambian (D5.2): el cliente los sigue leyendo igual.
	var fm := Falso.new({"data": PackedFloat32Array([1.0, 2.0, 0.5, 0.1, 0.0, 0.2])})
	check(VitaRelay.pose2d(fm).pos == Vector2(1, 2), "VC/1: pose2d intacto")
	var sc := Falso.new({"data": PackedInt32Array([3, 0, 9000, 2, 100, 0])})
	check(VitaRelay.scan_puntos(sc).size() == 1, "VC/1: scan_compacto intacto")


func _md5(datos) -> String:
	var partes := PackedStringArray()
	for v in datos:
		partes.append(str(int(v)))
	return ",".join(partes).md5_text()


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


## VisorRos + GestorHud con una pestaña Otra (para ocultar) y la pestaña `nombre` con el widget.
func _montar(en_vita: bool, nombre: String, w: Control) -> Array:
	var v: Node = VisorRos.new()
	v.name = "VisorPrueba"
	v.transporte = "loopback"
	v.config_json = ""
	v.reintento_s = 0.0
	v.en_vita = en_vita
	var capa := CanvasLayer.new()
	capa.name = "Hud"
	v.add_child(capa)
	var g: Control = _ctl(GestorHud, "GestorHud", Vector2.ZERO, Vector2(960, 544), {"avisar_en_pc": true})
	g.en_vita = en_vita
	capa.add_child(g)
	var barra := _ctl(null, "Barra", Vector2.ZERO, Vector2(960, 24))
	var tabs := _ctl(null, "Pestanas", Vector2(640, 24), Vector2(320, 496))
	g.add_child(barra)
	g.add_child(tabs)
	g.barra = barra
	g.pestanas = tabs
	var tab := _ctl(null, nombre, Vector2.ZERO, Vector2(320, 496))
	tab.add_child(w)
	tabs.add_child(tab)
	tabs.add_child(_ctl(null, "Otra", Vector2.ZERO, Vector2(320, 496)))
	root.add_child(v)
	return [v, g, tab]


func _log(nivel: int, nodo: String, texto: String):
	var m = RosMsg.from_type("rcl_interfaces/msg/Log")
	m.level = nivel
	m.set_member("name", nodo)
	m.set_member("msg", texto)
	return m


func _diag(nivel: int, nombre: String, mensaje: String):
	var st = RosMsg.from_type("diagnostic_msgs/msg/DiagnosticStatus")
	st.level = nivel
	st.set_member("name", nombre)
	st.message = mensaje
	var kv = RosMsg.from_type("diagnostic_msgs/msg/KeyValue")
	kv.key = "t"
	kv.value = "41"
	st.values = [kv]
	var m = RosMsg.from_type("diagnostic_msgs/msg/DiagnosticArray")
	m.status = [st]
	return m


# ---------------------------------------------------------------------------------------------------------------
# Consola
# ---------------------------------------------------------------------------------------------------------------
func _probar_consola(en_vita: bool) -> void:
	var pre := "Vita: " if en_vita else "PC: "
	var con: Control = _ctl(Consola, "Consola", Vector2.ZERO, Vector2(320, 100), {"hz": 0.0, "hz_vita": 0.0})
	var r := await _montaje(en_vita, "Consola", con)
	var v: Node = r[0]
	var g: Control = r[1]
	var tab: Control = r[2]
	check(con.estado == "ok" and con.canal.abierto(), pre + "consola suscrita (esquema Log en TIPOS_VISOR)")
	var t_esperado := "/vita/rosout" if en_vita else "/rosout"
	check(con.canal.topic_abierto == t_esperado and con.canal.compacto == en_vita, pre + "consola en %s" % t_esperado)
	check(con.fiabilidad == 2 and not con.canal.coalescer and con.caducidad_s == 0.0,
			pre + "consola: fiable, todos los eventos, no caduca")
	check(con._coste().quads == 240, pre + "consola: 6 × 40 = 240 quads declarados (D6)")

	var pub = v.contexto.nodo.create_publisher(t_esperado, "rcl_interfaces/msg/Log", v.contexto.qos(false, 10, false))
	pub.publish(_log(20, "nav", "info que no pasa"))
	pub.publish(_log(30, "nav", "aviso uno"))
	pub.publish(_log(40, "planner", "error\ncon salto"))
	await _fotogramas(3)
	check(con.lineas.size() == 2 and con.filtrados == 1, pre + "consola: INFO filtrado (nivel mínimo WARN)")
	check(con.lineas[0][1] == "W nav: aviso uno" and con.lineas[1][1] == "E planner: error con salto",
			pre + "consola: «%s» / «%s»" % [con.lineas[0][1], con.lineas[1][1]] if con.lineas.size() == 2 else pre + "consola: líneas")
	check(con.color_nivel(30) == con.COLOR_AVISO and con.color_nivel(50) == con.COLOR_ERROR
			and Consola.letra(35) == "W" and Consola.letra(5) == "?", pre + "consola: colores y letras por nivel")
	for i in 9:
		pub.publish(_log(30, "nodo_con_nombre_largo", "aviso %d con un texto bastante largo para recortar" % i))
	await _fotogramas(3)
	check(con.lineas.size() == 6 and String(con.lineas[5][1]).length() == 40 and String(con.lineas[5][1]).begins_with("W nodo"),
			pre + "consola: 6 líneas de ≤ 40 caracteres, la más nueva abajo")
	check(con.canal.mostrados == con.canal.recibidos and con.canal.recibidos == 12, pre + "consola: llegan los 12 eventos (sin «el último gana»)")
	await _fotogramas(2)
	check(con.dibujos >= 1 and con.quads_dibujados <= 240 and con.glifos_dibujados <= 240,
			pre + "consola: dibuja %d quads ≤ 240" % con.quads_dibujados)
	var inf: Dictionary = g.informe()
	check(inf["pestana"] == "Consola" and inf["pestana_declarados"] <= g.PESTANA_MAX and inf["pestana_quads"] <= g.PESTANA_MAX,
			pre + "pestaña Consola: %d declarados, %d dibujados ≤ 240" % [inf["pestana_declarados"], inf["pestana_quads"]])
	# Filtro por nodo y pausa.
	con.filtro_nodo = "planner"
	pub.publish(_log(30, "nav", "otro nodo"))
	await _fotogramas(3)
	check(con.lineas[5][1].begins_with("W nodo_con") and con.filtrados == 2, pre + "consola: filtro por nodo")
	con.filtro_nodo = ""
	con.pausado = true
	pub.publish(_log(40, "nav", "en pausa"))
	await _fotogramas(3)
	check(not String(con.lineas[5][1]).contains("pausa"), pre + "consola: en pausa no añade")
	con.pausado = false
	# Pestaña oculta: el canal no bombea; con tope de pendientes no apila sin fin (se queda con los últimos).
	g.siguiente()
	check(not tab.visible and tab.process_mode == Node.PROCESS_MODE_DISABLED, pre + "consola oculta")
	for i in 30:
		pub.publish(_log(30, "nav", "oculto %d" % i))
	await _fotogramas(3)
	check(con.canal._pendientes.size() == con.max_lineas * 2 and con.canal.descartados == 30 - con.max_lineas * 2,
			pre + "consola oculta: %d pendientes (tope), %d descartados" % [con.canal._pendientes.size(), con.canal.descartados])
	g.anterior()
	await _fotogramas(3)
	check(con.lineas[5][1] == "W nav: oculto 29", pre + "consola visible otra vez: los últimos avisos")
	check(Registro.regla("/rosout", "rcl_interfaces/msg/Log", en_vita).get("script", "").ends_with("hud/consola.gd"),
			pre + "registro: Log → hud/consola.gd")
	pub = null
	v.queue_free()
	await _fotogramas(2)


func _montaje(en_vita: bool, nombre: String, w: Control) -> Array:
	var r := _montar(en_vita, nombre, w)
	await _esperar_conexion(r[0])
	return r


# ---------------------------------------------------------------------------------------------------------------
# Diagnóstico
# ---------------------------------------------------------------------------------------------------------------
func _probar_diagnostico(en_vita: bool) -> void:
	var pre := "Vita: " if en_vita else "PC: "
	var dg: Control = _ctl(Diagnostico, "Diagnostico", Vector2.ZERO, Vector2(320, 140), {"hz": 0.0, "hz_vita": 0.0})
	var r := await _montaje(en_vita, "Diagnostico", dg)
	var v: Node = r[0]
	var g: Control = r[1]
	var t_esperado := "/vita/diagnostics" if en_vita else "/diagnostics"
	check(dg.estado == "ok" and dg.canal.topic_abierto == t_esperado, pre + "diagnóstico suscrito a %s" % t_esperado)
	if en_vita:
		check(dg.fiabilidad == 0 and dg.solo_problemas, "Vita: diagnóstico por el relay = best effort y «solo problemas»")
	else:
		check(dg.fiabilidad == 2 and dg.profundidad == 1 and not dg.solo_problemas,
				"PC: diagnóstico directo = fiable, profundidad 1 (doc 36 §6)")
	check(dg._coste().quads == 240, pre + "diagnóstico: 8 × 30 = 240 quads declarados (D6)")
	var pub = v.contexto.nodo.create_publisher(t_esperado, "diagnostic_msgs/msg/DiagnosticArray",
			v.contexto.qos(not en_vita, 1, false))
	# Como el relay: un estado por mensaje, varios en el mismo fotograma (coalescer = false).
	pub.publish(_diag(0, "motor_izq", "ok"))
	pub.publish(_diag(2, "bateria", "baja"))
	pub.publish(_diag(1, "lidar", "frecuencia baja"))
	await _fotogramas(3)
	check(dg.filas.size() == 3, pre + "diagnóstico: 3 estados en 3 mensajes, ninguno perdido")
	check(dg.filas.has("bateria") and dg.filas["bateria"][0] == 2,
			pre + "diagnóstico: nivel byte ida y vuelta (%s)" % str(dg.filas.get("bateria", [])))
	var vis: Array = dg.filas_visibles()
	var nombres := []
	for f in vis:
		nombres.append(f[1])
	if en_vita:
		check(nombres == ["bateria", "lidar"], "Vita: solo problemas, de peor a mejor (%s)" % str(nombres))
	else:
		check(nombres == ["bateria", "lidar", "motor_izq"], "PC: de peor a mejor (%s)" % str(nombres))
	# Nivel en bytes (según binding) y nombres largos recortados al dibujar.
	dg._al_mensaje(Falso.new({"status": [Falso.new({"level": PackedByteArray([1]), "name": "x".repeat(50),
			"message": "m", "values": []})]}))
	check(dg.filas["x".repeat(50)][0] == 1, pre + "diagnóstico: nivel como PackedByteArray")
	for i in 12:
		dg._al_mensaje(Falso.new({"status": [Falso.new({"level": 2, "name": "e%02d" % i, "message": "fallo",
				"values": []})]}))
	await _fotogramas(2)
	check(dg.filas_visibles().size() == 8, pre + "diagnóstico: como mucho 8 filas")
	check(dg.dibujos >= 1 and dg.quads_dibujados <= 240 and dg.glifos_dibujados <= 8 * 29,
			pre + "diagnóstico: dibuja %d quads ≤ 240 (%d glifos)" % [dg.quads_dibujados, dg.glifos_dibujados])
	var inf: Dictionary = g.informe()
	check(inf["pestana"] == "Diagnostico" and inf["pestana_declarados"] <= g.PESTANA_MAX
			and inf["pestana_quads"] <= g.PESTANA_MAX, pre + "pestaña Diagnóstico ≤ 240")
	# STALE por fila sin noticias (caducidad corta para la prueba) y redibujo sin mensajes.
	dg.caducidad_fila_s = 0.15
	dg.filas.clear()
	pub.publish(_diag(0, "motor_izq", "ok"))
	await _fotogramas(3)
	var antes: int = dg.dibujos
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400:
		await process_frame
	check(dg.nivel_fila("motor_izq", Time.get_ticks_msec()) == 3, pre + "diagnóstico: fila STALE tras su caducidad")
	check(dg.dibujos > antes, pre + "diagnóstico: redibuja al caducar una fila sin que llegue nada")
	if en_vita:
		check(dg.filas_visibles().size() == 1, "Vita: STALE es un problema (se ve con «solo problemas»)")
	check(Registro.regla("/diagnostics", "diagnostic_msgs/msg/DiagnosticArray", en_vita).get("script", "").ends_with(
			"hud/diagnostico.gd"), pre + "registro: DiagnosticArray → hud/diagnostico.gd")
	pub = null
	v.queue_free()
	await _fotogramas(2)


# ---------------------------------------------------------------------------------------------------------------
# main.tscn: pestañas Consola y Diagnóstico colocadas como nodos (doc 35)
# ---------------------------------------------------------------------------------------------------------------
func _probar_main() -> void:
	var escena: Node = load("res://main.tscn").instantiate()
	var v: Node = escena.get_node("VisorRos")
	v.transporte = "loopback"
	v.reintento_s = 0.0
	root.add_child(escena)
	await _esperar_conexion(v)
	var con: Node = escena.get_node_or_null("VisorRos/Hud/GestorHud/Pestanas/Consola/Consola")
	var dg: Node = escena.get_node_or_null("VisorRos/Hud/GestorHud/Pestanas/Diagnostico/Diagnostico")
	check(con != null and dg != null, "main.tscn: pestañas Consola y Diagnóstico")
	if con != null and dg != null:
		check(con.estado == "ok" and dg.estado == "ok", "main.tscn: consola y diagnóstico suscritos")
		var g: Node = escena.get_node("VisorRos/Hud/GestorHud")
		check(g.quads_declarados(con.get_parent()) <= g.PESTANA_MAX and g.quads_declarados(dg.get_parent()) <= g.PESTANA_MAX,
				"main.tscn: pestañas V6 ≤ 240 quads")
	escena.queue_free()
	await _fotogramas(2)
