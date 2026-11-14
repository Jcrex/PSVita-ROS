extends SceneTree
## Prueba de host del núcleo del visor (V1; doc 36 §10, ADR 0013). Transporte `loopback` (sin red):
## recibe, «el último gana», tope de Hz y aviso D8, caducidad, reserva de cupo, `solo_pc`, camino compacto,
## RegistroDisplays, TiempoRos y que `main.tscn` arranca.
##
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script res://comun/pruebas/visor.gd
##
## Los displays de prueba son subclases mínimas creadas aquí (GDScript en memoria) para no dejar en `visor/`
## scripts que no son displays de verdad. Cuentan lo que reciben, lo que caduca y por qué camino llegó.

const VisorRos = preload("res://comun/visor/visor_ros.gd")
const Registro = preload("res://comun/visor/registro_displays.gd")
const TiempoRos = preload("res://comun/visor/tiempo_ros.gd")

const CUERPO_ECO := """
var vistos := []
var compactos := 0
var caducados := 0
var pide := 0
func _procesar(msg):
	return String(msg.data)
func _procesar_compacto(msg):
	compactos += 1
	return "c:" + String(msg.data)
func _pintar(d) -> void:
	vistos.append(d)
func _caducar() -> void:
	caducados += 1
	super._caducar()
"""

var fallos := 0
var pruebas := 0
var _hud: GDScript
var _d3: GDScript
var _d2: GDScript


func check(condicion: bool, nombre: String) -> void:
	pruebas += 1
	if not condicion:
		fallos += 1
		push_error(nombre)
	else:
		print("OK ", nombre)


func _init() -> void:
	_correr.call_deferred()


func _correr() -> void:
	_hud = _script("res://comun/visor/display_ros_hud.gd",
			"func _coste() -> Dictionary:\n\treturn {\"instancias\": 0, \"triangulos\": 0, \"quads\": pide}\n")
	_d3 = _script("res://comun/visor/display_ros_3d.gd",
			"func _coste() -> Dictionary:\n\treturn {\"instancias\": pide, \"triangulos\": 0, \"quads\": 0}\n")
	_d2 = _script("res://comun/visor/display_ros_2d.gd",
			"func _coste() -> Dictionary:\n\treturn {\"instancias\": 0, \"triangulos\": 0, \"quads\": pide}\n")
	_probar_registro()
	await _probar_pc()
	await _probar_vita_simulada()
	await _probar_main()
	print("RESULTADO: ", pruebas - fallos, "/", pruebas)
	quit(0 if fallos == 0 else 1)


func _script(base: String, extra: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends \"%s\"\n%s%s" % [base, CUERPO_ECO, extra]
	var err := s.reload()
	check(err == OK, "subclase de prueba de %s compila" % base.get_file())
	return s


func _display(script: GDScript, nombre: String, props: Dictionary) -> Node:
	var d: Node = script.new()
	d.name = nombre
	for k in props:
		d.set(k, props[k])
	return d


func _visor(en_vita: bool, displays: Array) -> Node:
	var v: Node = VisorRos.new()
	v.name = "VisorPrueba"
	v.transporte = "loopback"
	v.config_json = ""
	v.reintento_s = 0.0
	v.en_vita = en_vita
	for d in displays:
		v.add_child(d)
	root.add_child(v)
	return v


func _esperar_conexion(v: Node) -> void:
	for _i in 60:
		if v.estado != "sin conectar":
			return
		await process_frame


func _fotogramas(n: int) -> void:
	for _i in n:
		await process_frame


func _cerrar(v: Node) -> void:
	v.queue_free()
	await _fotogramas(2)


func _cadena(texto: String):
	var m = RosMsg.from_type("std_msgs/msg/String")
	m.data = texto
	return m


# ---------------------------------------------------------------------------------------------------------------
# PC: camino estándar, «el último gana», Hz, caducidad, estados y TiempoRos
# ---------------------------------------------------------------------------------------------------------------
func _probar_pc() -> void:
	var eco = _display(_hud, "Eco", {"topic": "/prueba/eco", "tipo": "std_msgs/msg/String", "hz": 0.0, "caducidad_s": 0.3})
	var eco3 = _display(_d3, "Eco3D", {"topic": "/prueba/eco", "tipo": "std_msgs/msg/String", "hz": 0.0, "caducidad_s": 0.3, "pide": 6})
	var eco2 = _display(_d2, "Eco2D", {"topic": "/prueba/eco", "tipo": "std_msgs/msg/String", "hz": 0.0, "pide": 5000})
	var lento = _display(_hud, "Lento", {"topic": "/prueba/eco", "tipo": "std_msgs/msg/String", "hz": 5.0, "caducidad_s": 0.0})
	var sin_esquema = _display(_hud, "SinEsquema", {"topic": "/prueba/x", "tipo": "paquete_falso/msg/Nada"})
	var sin_topic = _display(_hud, "SinTopic", {})
	var apagado = _display(_hud, "Apagado", {"topic": "/prueba/eco", "tipo": "std_msgs/msg/String", "habilitado": false})
	var solo_pc = _display(_hud, "SoloPc", {"topic": "/prueba/eco", "tipo": "std_msgs/msg/String", "hz": 0.0, "solo_pc": true})
	var comp = _display(_hud, "Comp", {"topic": "/prueba/estandar", "tipo": "std_msgs/msg/String",
			"topic_vita": "eco", "tipo_vita": "std_msgs/msg/String", "hz": 0.0})
	var v := _visor(false, [eco, eco3, eco2, lento, sin_esquema, sin_topic, apagado, solo_pc, comp])
	await _esperar_conexion(v)
	check(v.ros_listo and v.estado == "ok", "PC: el visor arranca ROS en loopback")
	check(not v.usa_compactos(), "PC: loopback sin forzar = camino estándar")
	check(v.displays.size() == 9, "PC: conecta los 9 displays del grupo display_ros")
	check(eco.estado == "ok" and eco3.estado == "ok" and eco2.estado == "ok", "PC: estados ok")
	check(sin_esquema.estado.begins_with("sin esquema") and not sin_esquema.canal.abierto(), "PC: tipo sin esquema no suscribe")
	check(sin_topic.estado == "sin topic" and not sin_topic.canal.abierto(), "PC: sin topic no suscribe")
	check(apagado.estado == "desactivado" and not apagado.visible, "PC: habilitado=false se desactiva")
	check(solo_pc.estado == "ok", "PC: solo_pc funciona en el PC")
	check(eco3.cupo == 6 and eco2.cupo == 5000 and v.reservar("tf", 1000, "x") == 1000, "PC: sin cupos (todo concedido)")
	check(not comp.canal.compacto and comp.canal.topic_abierto == "/prueba/estandar", "PC: con topic_vita usa el topic estándar")

	var pub = v.contexto.nodo.create_publisher("/prueba/eco", "std_msgs/msg/String", v.contexto.qos(true, 1, false))
	pub.publish(_cadena("uno"))
	await _fotogramas(3)
	check(eco.vistos == ["uno"] and eco.datos == "uno", "recibe: HUD")
	check(eco3.vistos == ["uno"] and eco3.visible and eco3.transform == Transform3D.IDENTITY, "recibe: 3D (sin frame = marco fijo)")
	check(eco2.vistos == ["uno"] and eco2.visible, "recibe: 2D")
	check(solo_pc.vistos == ["uno"], "recibe: solo_pc en el PC")
	check(eco.canal.recibidos == 1 and eco.canal.mostrados == 1, "recibe: contadores 1/1")

	for t in ["a", "b", "c"]:
		pub.publish(_cadena(t))
	await _fotogramas(3)
	check(eco.canal.recibidos == 4, "el último gana: llegan los 3")
	check(eco.canal.mostrados == 2 and eco.vistos == ["uno", "c"], "el último gana: se entrega solo «c»")
	check(eco3.vistos == ["uno", "c"] and eco2.vistos == ["uno", "c"], "el último gana: también 3D y 2D")

	await create_timer(0.45).timeout
	check(eco.gris and eco.caducados == 1, "caducidad: el HUD pasa a gris una vez")
	check(eco.color_estado(Color.RED) == eco.COLOR_CADUCADO, "caducidad: color de dato viejo")
	# Revisión V1: los colores del HUD salen de PaletaViz (gris de la rampa, no STALE: ver display_ros_hud.gd).
	var pal = preload("res://comun/visor/paleta_viz.gd")
	check(eco.COLOR_CADUCADO.is_equal_approx(pal.color(eco.I_CADUCADO)) and eco.COLOR_OK == pal.OK
			and eco.COLOR_AVISO == pal.WARN and eco.COLOR_ERROR == pal.ERROR, "HUD: colores de PaletaViz")
	check(not eco3.visible and eco3.caducados == 1, "caducidad: el 3D se oculta una vez")
	check(eco2.visible and eco2.caducados == 0, "caducidad 0 = nunca caduca")
	pub.publish(_cadena("d"))
	await _fotogramas(3)
	check(not eco.gris and eco.caducados == 2, "caducidad: vuelve a vivo con un mensaje")
	check(eco3.visible and eco3.vistos.back() == "d", "caducidad: el 3D reaparece con un mensaje")

	# Tope de Hz (5 Hz) con mensajes a ~50 Hz durante 1,2 s, y aviso D8 (recibido > 2 × dibujado).
	var antes: int = lento.canal.mostrados
	var antes_eco: int = eco.canal.mostrados
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1200:
		pub.publish(_cadena("r"))
		await create_timer(0.02).timeout
	await _fotogramas(2)
	var entregados: int = lento.canal.mostrados - antes
	check(entregados >= 3 and entregados <= 8, "hz=5: %d entregas en 1,2 s" % entregados)
	var sin_tope: int = eco.canal.mostrados - antes_eco
	check(sin_tope > entregados * 2, "hz=0: sin tope (%d entregas)" % sin_tope)
	check(lento.canal.avisado_hz and not eco.canal.avisado_hz, "D8: avisa si llega > 2 × hz")

	# TiempoRos
	var ps = RosMsg.from_type("geometry_msgs/msg/PoseStamped")
	check(is_nan(TiempoRos.latencia(v.contexto.nodo, ps)), "TiempoRos: sello 0 = NAN")
	v.contexto.sello(ps.header)
	var lat := TiempoRos.latencia(v.contexto.nodo, ps)
	check(lat >= 0.0 and lat < 1.0, "TiempoRos: latencia de un sello recién puesto (%.4f s)" % lat)
	check(is_nan(TiempoRos.latencia(v.contexto.nodo, _cadena("x"))), "TiempoRos: sin cabecera = NAN")
	var tm = RosMsg.from_type("builtin_interfaces/msg/Time")
	if tm != null:
		TiempoRos.escribir_tiempo(tm, 12.25)
		check(tm.sec == 12 and tm.nanosec == 250000000, "TiempoRos: escribir 12,25 s")
		check(is_equal_approx(TiempoRos.segundos(tm), 12.25) and TiempoRos.a_texto(tm) == "12.250000000",
				"TiempoRos: segundos y texto")
	pub = null
	await _cerrar(v)
	check(not rclgd.ok(), "PC: al salir del árbol el visor cierra rclgd")


# ---------------------------------------------------------------------------------------------------------------
# Vita simulada (en_vita = true, perfil HMI): cupos, solo_pc, camino compacto y hz_vita
# ---------------------------------------------------------------------------------------------------------------
func _probar_vita_simulada() -> void:
	var solo_pc = _display(_hud, "SoloPc", {"topic": "/prueba/eco", "tipo": "std_msgs/msg/String", "solo_pc": true})
	var a = _display(_d3, "A", {"topic": "/prueba/eco", "tipo": "std_msgs/msg/String", "capa": "tf", "pide": 6})
	var b = _display(_d3, "B", {"topic": "/prueba/eco", "tipo": "std_msgs/msg/String", "capa": "tf", "pide": 6})
	var c = _display(_d3, "C", {"topic": "/prueba/eco", "tipo": "std_msgs/msg/String", "capa": "tf", "pide": 4})
	var q1 = _display(_d2, "Q1", {"topic": "/prueba/eco", "tipo": "std_msgs/msg/String", "pide": 500})
	var q2 = _display(_d2, "Q2", {"topic": "/prueba/eco", "tipo": "std_msgs/msg/String", "pide": 400})
	var comp = _display(_hud, "Comp", {"topic": "/prueba/estandar", "tipo": "std_msgs/msg/String",
			"topic_vita": "eco", "tipo_vita": "std_msgs/msg/String", "hz": 0.0, "hz_vita": 0.0})
	var hz_v = _display(_hud, "HzVita", {"topic": "/prueba/eco", "tipo": "std_msgs/msg/String", "hz": 10.0, "hz_vita": 4.0})
	var v := _visor(true, [solo_pc, a, b, c, q1, q2, comp, hz_v])
	await _esperar_conexion(v)
	check(v.ros_listo and v.usa_compactos(), "Vita: arranca y usa el camino compacto")
	check(solo_pc.estado == "desactivado" and not solo_pc.visible and not solo_pc.canal.abierto(),
			"solo_pc: en la Vita se desactiva y no suscribe")
	check(a.cupo == 6 and a.estado == "ok", "cupo: A recibe 6 de 8 en «tf»")
	check(b.cupo == 2 and b.estado == "ok", "cupo: B recibe los 2 que quedan")
	check(c.cupo == 0 and c.estado == "sin cupo" and not c.visible and not c.canal.abierto(), "cupo: C sin cupo no suscribe")
	check(v.usado("tf") == 8, "cupo: «tf» lleno (8, perfil HMI)")
	check(q1.cupo == 500 and q2.cupo == 300 and v.usado("sensores_2d") == 800, "cupo: quads 2D 500 + 300 de 800")
	a.desconectar()
	check(v.usado("tf") == 2 and a.cupo == 0 and not a.canal.abierto(), "cupo: desconectar libera")
	check(v.reservar("tf", 6, "otro") == 6 and v.usado("tf") == 8, "cupo: lo liberado se puede volver a reservar")
	check(comp.canal.compacto and comp.canal.topic_abierto == "/vita/eco", "compacto: prefijo + topic_vita")
	check(not b.canal.compacto and b.canal.topic_abierto == "/prueba/eco", "sin topic_vita: tipo estándar en directo")
	check(hz_v.canal.hz == 4.0 and comp.canal.hz == 0.0, "hz_vita manda en la Vita (0 = el mismo)")

	var pub_v = v.contexto.nodo.create_publisher("/vita/eco", "std_msgs/msg/String", v.contexto.qos(true, 1, false))
	var pub_e = v.contexto.nodo.create_publisher("/prueba/estandar", "std_msgs/msg/String", v.contexto.qos(true, 1, false))
	pub_e.publish(_cadena("no"))
	pub_v.publish(_cadena("z"))
	await _fotogramas(3)
	check(comp.vistos == ["c:z"] and comp.compactos == 1, "compacto: llega por _procesar_compacto")
	pub_v = null
	pub_e = null
	await _cerrar(v)


# ---------------------------------------------------------------------------------------------------------------
# main.tscn: la escena del proyecto arranca vacía y conecta (en loopback)
# ---------------------------------------------------------------------------------------------------------------
func _probar_main() -> void:
	var escena: Node = load("res://main.tscn").instantiate()
	var v: Node = escena.get_node("VisorRos")
	v.transporte = "loopback"
	v.reintento_s = 0.0
	root.add_child(escena)
	await _esperar_conexion(v)
	check(v.ros_listo and v.camara == escena.get_node("Camara"), "main.tscn: VisorRos conecta y tiene cámara")
	check(v.prefijo_compacto == "/vita", "main.tscn: prefijo_compacto de robot.json")
	escena.queue_free()
	await _fotogramas(2)


# ---------------------------------------------------------------------------------------------------------------
# RegistroDisplays (estático)
# ---------------------------------------------------------------------------------------------------------------
func _probar_registro() -> void:
	var r: Array = Registro.candidatos("/vita/scan_compacto", "std_msgs/msg/Int16MultiArray", true)
	check(r.size() >= 2 and String(r[0]["script"]).ends_with("2d/scan.gd"), "registro: la regla con topic va primero")
	check(String(r[-1]["script"]).ends_with("hud/inspector_texto.gd"), "registro: el comodín va el último")
	var g: Array = Registro.candidatos("/otro", "std_msgs/msg/Int16MultiArray", false)
	check(String(g[0]["script"]).ends_with("hud/multiarray.gd"), "registro: MultiArray sin topic conocido = genérico")
	check(String(Registro.candidatos("/scan", "sensor_msgs/msg/LaserScan", false)[0]["script"]).ends_with("2d/scan.gd"),
			"registro: LaserScan → scan")
	# V12: el comodín (inspector de texto) ya existe, así que un tipo sin display propio cae en él.
	var ins: Node = Registro.crear("/x", "tipo/msg/SinDisplayAun", false)
	check(ins != null and ins.get_script().resource_path.ends_with("hud/inspector_texto.gd"),
			"registro: tipo sin display propio → inspector de texto (comodín, V12)")
	if ins != null:
		ins.free()
