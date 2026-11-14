extends SceneTree
## Prueba de host de V12 (inspector, trazador y explorador; doc 36 §1.1, §1.3, §7 y §10; doc 36a §4.1.1–§4.1.4 y
## §4.1.11; sentencia W13 D6 y D9). Transporte `loopback` (sin red):
##   - IntrospeccionRos: `campos_de_tipo` sobre el prototipo vacío de varios tipos (incluido
##     `control_msgs/JointTrajectoryControllerState`, con el campo reservado `reference`), caché por tipo (el
##     prototipo se crea una sola vez), tipo sin esquema = vacío, rutas de Foxglove y `leer_ruta`;
##   - Trazador: 3 series × 64 puntos = 3 comandos de dibujo de series (una polilínea por serie, sin bucle por punto)
##     y ≤ 240 *quads*; en la Vita la capacidad se recorta a 64; recibe por loopback;
##   - Inspector de texto: en modo Vita ≤ 12 filas (8 × 30, D6) aunque la escena pida más; desplegar submensajes;
##     la fila de `reference` se lee con `get_member`;
##   - ExploradorTopics: sin grafo (ros2_vita) usa el catálogo de la escena y los tipos del esquema; añade displays
##     sin guardarlos en el PC y no añade nada en la Vita;
##   - `main.tscn`: pestañas Gráficas e Inspector dentro del cupo.
##
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_inspector.gd

const VisorRos = preload("res://comun/visor/visor_ros.gd")
const GestorHud = preload("res://comun/visor/gestor_hud.gd")
const Intro = preload("res://comun/visor/introspeccion_ros.gd")
const Trazador = preload("res://comun/visor/displays/hud/trazador.gd")
const Inspector = preload("res://comun/visor/displays/hud/inspector_texto.gd")
const Explorador = preload("res://comun/visor/explorador_topics.gd")

const ODOM := "nav_msgs/msg/Odometry"
const JTCS := "control_msgs/msg/JointTrajectoryControllerState"


## Cuenta los errores de script de visor/ (Godot ≥ 4.5: `Logger`).
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
	# El esquema lo carga VisorRos al iniciar ROS; la introspección pura se prueba antes, así que se carga aquí.
	if not RosMsg.has_schema():
		RosMsg.load_schema_file(ProjectSettings.get_setting("ros/schema_path", "res://ros/schema.rsch"))
	_probar_introspeccion()
	await _probar_trazador()
	await _probar_trazador_loopback(false)
	await _probar_trazador_loopback(true)
	await _probar_inspector(true)
	await _probar_inspector(false)
	await _probar_explorador(false)
	await _probar_explorador(true)
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


func _visor(en_vita: bool, hijos: Array) -> Node:
	var v: Node = VisorRos.new()
	v.name = "VisorPrueba"
	v.transporte = "loopback"
	v.config_json = ""
	v.reintento_s = 0.0
	v.en_vita = en_vita
	var capa := CanvasLayer.new()
	capa.name = "Hud"
	v.add_child(capa)
	for h in hijos:
		if h is Control:
			capa.add_child(h)
		else:
			v.add_child(h)
	root.add_child(v)
	await _esperar_conexion(v)
	return v


func _odom(vx: float, vy: float, wz: float):
	var m = RosMsg.from_type(ODOM)
	var lin = m.get_member("twist").get_member("twist").get_member("linear")
	lin.x = vx
	lin.y = vy
	m.get_member("twist").get_member("twist").get_member("angular").z = wz
	return m


# ---------------------------------------------------------------------------------------------------------------
# IntrospeccionRos
# ---------------------------------------------------------------------------------------------------------------
func _probar_introspeccion() -> void:
	Intro.olvidar_cache()
	var antes: int = Intro.prototipos_creados
	var c := Intro.campos_de_tipo(ODOM)
	check(c == PackedStringArray(["header", "child_frame_id", "pose", "twist"]), "intro: Odometry = %s" % [c])
	check(Intro.campos_de_tipo("std_msgs/msg/Float32MultiArray") == PackedStringArray(["layout", "data"]),
			"intro: Float32MultiArray = layout, data")
	check(Intro.campos_de_tipo("sensor_msgs/msg/Temperature") == PackedStringArray(["header", "temperature", "variance"]),
			"intro: Temperature = header, temperature, variance")
	var j := Intro.campos_de_tipo(JTCS)
	check(j.has("reference") and j.has("feedback") and j.has("multi_dof_reference") and not j.has("script"),
			"intro: JointTrajectoryControllerState incluye `reference` (campo reservado) y no `script`")
	check(Intro.prototipos_creados - antes == 4, "intro: un prototipo por tipo")
	Intro.campos_de_tipo(ODOM)
	Intro.campos_de_tipo(JTCS)
	check(Intro.prototipos_creados - antes == 4, "intro: la segunda consulta sale de la caché (sin prototipo)")
	check(Intro.campos_de_tipo("tipo/msg/SinEsquema").is_empty(), "intro: tipo sin esquema = sin campos")
	# `reference` se lee con get_member (m.reference sería RefCounted.reference(), un Callable).
	var proto = RosMsg.from_type(JTCS)
	var ref = Intro.leer_ruta(proto, Intro.trocear("reference"))
	check(ref is RosMsg and Intro.campos(ref).has("positions"), "intro: leer_ruta(reference) = JointTrajectoryPoint")
	check(Intro.leer_ruta(proto, Intro.trocear("reference.time_from_start.sec")) == 0, "intro: ruta anidada en reference")

	# Rutas de Foxglove.
	var r := Intro.partir_ruta("/odom.twist.twist.linear.x")
	check(r["topic"] == "/odom" and r["campos"] == PackedStringArray(["twist", "twist", "linear", "x"]),
			"intro: /odom.twist.twist.linear.x → /odom + 4 campos")
	r = Intro.partir_ruta("/robot/poses[3].position.x")
	check(r["topic"] == "/robot/poses" and r["campos"] == PackedStringArray(["3", "position", "x"]),
			"intro: índice tras el topic")
	r = Intro.partir_ruta("poses[3].pose.position.x")
	check(r["topic"] == "" and r["campos"] == PackedStringArray(["poses", "3", "pose", "position", "x"]),
			"intro: ruta relativa con índice")
	check(Intro.unir_ruta("/odom", PackedStringArray(["poses", "3", "x"])) == "/odom.poses[3].x", "intro: unir_ruta")
	var m = _odom(1.5, -0.25, 0.75)
	check(is_equal_approx(Intro.leer_ruta(m, Intro.trocear("twist.twist.linear.x")), 1.5), "intro: leer_ruta = 1,5")
	check(Intro.leer_ruta(m, Intro.trocear("twist.nada.x")) == null, "intro: ruta inexistente = null")
	var fa = RosMsg.from_type("std_msgs/msg/Float32MultiArray")
	fa.data = PackedFloat32Array([0.0, 1.0, 2.0, 3.5])
	check(is_equal_approx(Intro.leer_ruta(fa, Intro.trocear("data[3]")), 3.5), "intro: data[3] = 3,5")
	check(Intro.leer_ruta(fa, Intro.trocear("data[9]")) == null, "intro: índice fuera = null")
	var num := Intro.rutas_numericas(ODOM)
	check(num.has("twist.twist.linear.x") and num.has("pose.pose.orientation.w") and num.has("header.stamp.sec"),
			"intro: rutas numéricas de Odometry (%d)" % num.size())


# ---------------------------------------------------------------------------------------------------------------
# Trazador
# ---------------------------------------------------------------------------------------------------------------
func _probar_trazador() -> void:
	var tr: Control = _ctl(Trazador, "Trazador", Vector2.ZERO, Vector2(320, 160))
	root.add_child(tr)
	tr.preparar(PackedStringArray(["twist.twist.linear.x", "twist.twist.linear.y", "/odom.twist.twist.angular.z",
			"pose.pose.position.x"]))
	check(tr.series.size() == 3, "trazador: como mucho 3 series")
	for i in 100:
		tr.anadir_muestra(_odom(sin(i * 0.1), cos(i * 0.1), i * 0.01), i * 0.2)
	tr.queue_redraw()
	await _fotogramas(2)
	check(tr.dibujos >= 1, "trazador: dibuja sin errores")
	check(tr.comandos_series == 3 and tr.puntos_dibujados == PackedInt32Array([64, 64, 64]),
			"trazador: 3 × 64 puntos = 3 comandos de dibujo (%d, %s)" % [tr.comandos_series, tr.puntos_dibujados])
	check(tr.comandos <= 7, "trazador: ≤ 7 comandos en total (marco, cero, 3 series, 2 etiquetas): %d" % tr.comandos)
	var o: PackedVector2Array = tr.ordenados(0)
	check(o.size() == 64 and is_equal_approx(o[0].x, 36 * 0.2) and is_equal_approx(o[63].x, 99 * 0.2),
			"trazador: búfer circular en orden temporal (de la muestra 36 a la 99)")
	check(tr.quads_dibujados <= 240 and tr._coste().quads <= 240,
			"trazador: %d quads dibujados, %d declarados ≤ 240" % [tr.quads_dibujados, tr._coste().quads])
	check(is_equal_approx(tr.y_max, 1.0) or tr.y_max <= 1.0, "trazador: rango y acotado")
	# NaN no entra (T2).
	var n_antes: int = tr.series[0].n
	var nan_m = _odom(NAN, NAN, NAN)
	check(tr.anadir_muestra(nan_m, 30.0) == null and tr.series[0].n == n_antes, "trazador: NaN no entra en la serie")
	# Revisión V3: diezmado por tiempo (ventana 10 s / 64 puntos ≈ 0,156 s): 30 Hz no llena el búfer en 2 s.
	var n_d: int = tr.series[0].n
	var cab_d: int = tr.series[0].cab
	for i in 30:
		tr.anadir_muestra(_odom(0.5, 0.0, 0.0), 40.0 + i / 30.0)
	var guardadas: int = (tr.series[0].cab - cab_d + tr.capacidad) % tr.capacidad
	check(guardadas >= 6 and guardadas <= 8 and tr.series[0].n == n_d,
			"trazador: 1 s a 30 Hz guarda ≈ 6,4 muestras (%d), no 30" % guardadas)
	tr.queue_free()
	await _fotogramas(1)


func _probar_trazador_loopback(en_vita: bool) -> void:
	var pre := "Vita: " if en_vita else "PC: "
	var tr: Control = _ctl(Trazador, "Trazador", Vector2(640, 24), Vector2(320, 160),
			{"topic": "/odom", "tipo": ODOM, "capacidad": 300, "hz": 0.0, "hz_vita": 0.0})
	var v: Node = await _visor(en_vita, [tr])
	check(tr.estado == "ok" and tr.canal.topic_abierto == "/odom" and not tr.canal.coalescer,
			pre + "trazador suscrito a /odom sin «el último gana»")
	check(tr.capacidad == (64 if en_vita else 300), pre + "capacidad %d (Vita = 64, D6)" % tr.capacidad)
	var pub = v.contexto.nodo.create_publisher("/odom", ODOM, v.contexto.qos(true, 1, false))
	for i in 5:
		pub.publish(_odom(0.1 * i, 0.0, -0.1 * i))
		await _fotogramas(1)
	await _fotogramas(3)
	check(tr.series.size() == 2 and tr.series[0].n >= 1 and tr.dibujos >= 1,
			pre + "trazador recibe por loopback (%d muestras)" % (tr.series[0].n if tr.series.size() > 0 else -1))
	pub = null
	v.queue_free()
	await _fotogramas(2)


# ---------------------------------------------------------------------------------------------------------------
# Inspector de texto
# ---------------------------------------------------------------------------------------------------------------
func _probar_inspector(en_vita: bool) -> void:
	var pre := "Vita: " if en_vita else "PC: "
	var ins: Control = _ctl(Inspector, "Inspector", Vector2(640, 24), Vector2(320, 496),
			{"topic": "/odom", "tipo": ODOM, "filas": 20, "ancho_max": 40, "hz": 0.0, "hz_vita": 0.0})
	var v: Node = await _visor(en_vita, [ins])
	check(ins.estado == "ok", pre + "inspector suscrito")
	if en_vita:
		check(ins.filas <= 12 and ins.filas == 8 and ins.ancho_max == 30, "Vita: inspector recortado a 8 × 30 (≤ 12 filas)")
	else:
		check(ins.filas == 20, "PC: inspector con las filas de la escena")
	# Desplegar pose, pose.pose, twist y twist.twist para tener más líneas que filas.
	for r in ["/pose", "/pose/pose", "/pose/pose/position", "/pose/pose/orientation", "/twist", "/twist/twist",
			"/twist/twist/linear", "/twist/twist/angular", "/header"]:
		ins.desplegados[r] = true
	var pub = v.contexto.nodo.create_publisher("/odom", ODOM, v.contexto.qos(true, 1, false))
	pub.publish(_odom(1.25, 0.0, 0.5))
	await _fotogramas(4)
	check(ins.lineas.size() > 12, pre + "inspector: %d líneas aplanadas" % ins.lineas.size())
	check(ins.filas_dibujadas == ins.filas and ins.dibujos >= 1, pre + "inspector: %d filas dibujadas" % ins.filas_dibujadas)
	if en_vita:
		check(ins.filas_dibujadas <= 12 and ins.quads_dibujados <= 240 and ins._coste().quads <= 240,
				"Vita: inspector ≤ 12 filas y ≤ 240 quads (%d)" % ins.quads_dibujados)
	var txt := "\n".join(ins.lineas)
	check(txt.contains("x: 1.250") and txt.contains("child_frame_id"), pre + "inspector: valores y campos")
	var antes: int = ins.primera
	ins.desplazar(3)
	check(ins.primera == antes + 3, pre + "inspector: desplazar")
	# Plegar el submensaje de la primera fila visible si lo es; si no, alternar devuelve false.
	ins.primera = 0
	var n0: int = ins.lineas.size()
	check(ins.alternar(0) and ins.lineas.size() < n0, pre + "inspector: plegar header reduce las líneas")
	# Campo reservado `reference`: el aplanado usa get_member.
	var lin = ins._aplanar_todo(RosMsg.from_type(JTCS))
	check(lin != null and "\n".join(lin).contains("reference: {…}"), pre + "inspector: fila de `reference`")
	pub = null
	v.queue_free()
	await _fotogramas(2)


# ---------------------------------------------------------------------------------------------------------------
# ExploradorTopics
# ---------------------------------------------------------------------------------------------------------------
func _probar_explorador(en_vita: bool) -> void:
	var pre := "Vita: " if en_vita else "PC: "
	var tr: Control = _ctl(Trazador, "Trazador", Vector2(640, 24), Vector2(320, 160),
			{"topic": "/odom", "tipo": ODOM, "topic_vita": "pose2d", "tipo_vita": "std_msgs/msg/Float32MultiArray"})
	var ex: Node = Explorador.new()
	ex.name = "Explorador"
	var nuevos := []
	ex.topic_nuevo.connect(func(t, _ti): nuevos.append(t))
	var v: Node = await _visor(en_vita, [tr, ex])
	await _fotogramas(2)
	check(ex.visor == v and not ex.tiene_grafo(), pre + "explorador: ros2_vita sin API de grafo")
	var cat: Dictionary = ex.topics
	var t_esp := "/vita/pose2d" if en_vita else "/odom"
	check(cat.has(t_esp) and not ex.desde_grafo and nuevos.has(t_esp), pre + "explorador: catálogo de la escena %s" % [cat])
	var tipos: PackedStringArray = Explorador.tipos_conocidos()
	check(tipos.has(ODOM) and tipos.has("std_msgs/msg/Float32MultiArray"), pre + "explorador: tipos del esquema (%d)" % tipos.size())
	var d: Node = ex.anadir_display("/temperatura_x", "sensor_msgs/msg/Temperature", v.get_node("Hud"))
	if en_vita:
		check(d == null, "Vita: el explorador no añade displays (D9)")
	else:
		check(d != null and d.owner == null and d.is_inside_tree() and ex.anadidos.has(d) and v.displays.has(d),
				"PC: display añadido en ejecución, sin owner (no se guarda)")
		if d != null:
			ex.quitar_display(d)
			check(not v.displays.has(d), "PC: quitar_display")
	v.queue_free()
	await _fotogramas(2)


# ---------------------------------------------------------------------------------------------------------------
# main.tscn
# ---------------------------------------------------------------------------------------------------------------
func _probar_main() -> void:
	var escena: Node = load("res://main.tscn").instantiate()
	var v: Node = escena.get_node("VisorRos")
	v.transporte = "loopback"
	v.reintento_s = 0.0
	root.add_child(escena)
	await _esperar_conexion(v)
	var g: Node = escena.get_node("VisorRos/Hud/GestorHud")
	var tr: Node = escena.get_node_or_null("VisorRos/Hud/GestorHud/Pestanas/Graficas/Trazador")
	var ins: Node = escena.get_node_or_null("VisorRos/Hud/GestorHud/Pestanas/Inspector/Inspector")
	check(tr != null and ins != null and escena.get_node_or_null("VisorRos/ExploradorTopics") != null,
			"main.tscn: pestañas Gráficas e Inspector y ExploradorTopics")
	if tr != null and ins != null:
		check(tr.estado == "ok" and ins.estado == "ok", "main.tscn: trazador e inspector suscritos")
		for nombre in ["Graficas", "Inspector"]:
			var p: Control = g.pestanas.get_node(nombre)
			check(g.quads_declarados(p) <= g.PESTANA_MAX, "main.tscn: pestaña %s %d ≤ 240" % [nombre, g.quads_declarados(p)])
	escena.queue_free()
	await _fotogramas(2)
