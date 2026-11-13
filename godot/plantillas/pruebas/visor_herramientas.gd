extends SceneTree
## Prueba de host de V7 (doc 36 §10; sentencia W13 C9): herramientas que publican, en `loopback`.
##   - un mensaje por confirmación (PC: al soltar; Vita simulada: pendiente hasta ✕) y un toque = un evento;
##   - QoS de la tabla de doc 36 §6 (fiable; profundidad 5 PC / 1 Vita; teleop 1; volátil) y `fiabilidad` BE;
##   - `header.frame_id` = marco fijo del visor; ejes Godot → ROS (`rclgd.godot_to_ros_vector`) desde la planta 2D
##     y desde la cámara 3D (suelo y rayo de física);
##   - covarianza de `initialpose` como RViz (`initial_pose_tool.cpp:62-70`);
##   - SELECT recorre ninguna → Teleop → Meta → Pose inicial → Punto → ninguna (un evento = un cambio) y el nombre
##     llega a la barra de estado; Publish Point se desactiva tras publicar («Single click»);
##   - teleop: Twist con hombre muerto, UN cero al soltar y silencio, sin −0,0, escala con △/✕.
## Los eventos entran por `root.push_input` (el mismo reparto que en ejecución: `_unhandled_input`).
##
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_herramientas.gd

const VisorRos = preload("res://comun/visor/visor_ros.gd")
const H := "res://comun/visor/herramientas/"
const D := "res://comun/visor/displays/"
const PX := 40.0                               # px_por_m del visor
const ORIGEN := Vector2(480, 272)              # posición de la «Vista» de la planta


## Cuenta los errores de script (Godot ≥ 4.5: `Logger`), como las demás pruebas del visor.
class Vigia:
	extends Logger
	var errores := 0
	var ultimo := ""

	func _log_error(_f: String, file: String, _l: int, code: String, rationale: String, _e: bool, tipo: int,
			_b: Array[ScriptBacktrace]) -> void:
		if tipo == ERROR_TYPE_SCRIPT or (tipo == ERROR_TYPE_ERROR and file.contains("/visor/")):
			errores += 1
			ultimo = "%s: %s %s" % [file, code, rationale]

	func _log_message(_m: String, _e: bool) -> void:
		pass


var fallos := 0
var pruebas := 0
var vigia := Vigia.new()
var recibidos := {}                            # topic -> Array de mensajes
var _subs: Array = []


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
	RosMsg.load_schema_file(String(ProjectSettings.get_setting("ros/schema_path", "res://ros/schema.rsch")))
	await _probar_pc()
	await _probar_vita()
	await _probar_3d()
	await _probar_escena()
	check(vigia.errores == 0, "sin errores de script en visor/ (%s)" % vigia.ultimo)
	OS.remove_logger(vigia)
	print("RESULTADO: ", pruebas - fallos, "/", pruebas)
	quit(0 if fallos == 0 else 1)


# ---------------------------------------------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------------------------------------------
func _fotogramas(n: int) -> void:
	for _i in n:
		await process_frame


func _esperar(v: Node) -> void:
	for _i in 60:
		if v.estado != "sin conectar":
			return
		await process_frame


func _herr(nombre: String, archivo: String, props := {}) -> Node:
	var h: Node = load(H + archivo).new()
	h.name = nombre
	for k in props:
		h.set(k, props[k])
	return h


## Visor como el de main.tscn: Planta/Vista (Node2D en ORIGEN), Hud con la barra de estado y las herramientas.
## Devuelve {visor, vista, barra, cam, raiz}.
func _visor(en_vita: bool, herramientas: Array, con_planta := true) -> Dictionary:
	var v: Node = VisorRos.new()
	v.name = "VisorPrueba"
	v.transporte = "loopback"
	v.config_json = ""
	v.reintento_s = 0.0
	v.en_vita = en_vita
	v.marco_fijo = "odom"                      # distinto del defecto: la prueba ve que se usa el del visor
	v.px_por_m = PX
	var planta := CanvasLayer.new()
	planta.name = "Planta"
	v.add_child(planta)
	var vista := Node2D.new()
	vista.name = "Vista"
	vista.position = ORIGEN
	vista.visible = con_planta
	planta.add_child(vista)
	var hud := CanvasLayer.new()
	hud.name = "Hud"
	hud.layer = 2
	v.add_child(hud)
	var barra: Control = load(D + "hud/barra_estado.gd").new()
	barra.name = "Estado"
	hud.add_child(barra)
	var grupo := Node2D.new()
	grupo.name = "Herramientas"
	hud.add_child(grupo)
	for h in herramientas:
		if con_planta:
			h.planta = vista
		grupo.add_child(h)
	var raiz := Node3D.new()
	raiz.name = "Escena"
	var cam := Camera3D.new()
	raiz.add_child(cam)
	raiz.add_child(v)
	root.add_child(raiz)
	cam.look_at_from_position(Vector3(0, 5, 5), Vector3.ZERO)
	cam.current = true
	v.camara = cam
	return {"visor": v, "vista": vista, "barra": barra, "cam": cam, "raiz": raiz}


func _cerrar(e: Dictionary) -> void:
	_subs.clear()
	e.raiz.queue_free()
	await _fotogramas(2)


## Suscripciones fiables a los cuatro topics (en el mismo nodo: loopback entrega lo propio).
func _escuchar(v: Node) -> void:
	recibidos.clear()
	for par in [["/goal_pose", "geometry_msgs/msg/PoseStamped"],
			["/initialpose", "geometry_msgs/msg/PoseWithCovarianceStamped"],
			["/clicked_point", "geometry_msgs/msg/PointStamped"], ["/cmd_vel", "geometry_msgs/msg/Twist"]]:
		var t: String = par[0]
		recibidos[t] = []
		_subs.append(v.contexto.suscripcion(t, par[1], func(m): recibidos[t].append(m), false))


func _n(topic: String) -> int:
	return recibidos[topic].size()


func _ultimo(topic: String):
	return recibidos[topic].back() if not recibidos[topic].is_empty() else null


## Píxel de pantalla de un punto ROS del suelo en la planta (inverso de lo que hace la herramienta).
func _px(x: float, y: float) -> Vector2:
	return ORIGEN + Vector2(x, -y) * PX


func _boton(b: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = true
	root.push_input(e)
	var s := InputEventJoypadButton.new()
	s.button_index = b
	s.pressed = false
	root.push_input(s)


func _raton(pos: Vector2, pulsado: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pulsado
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pulsado else 0
	root.push_input(e)


func _arrastre(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func _gesto(a: Vector2, b: Vector2) -> void:
	_raton(a, true)
	if b != a:
		_arrastre((a + b) * 0.5)
		_arrastre(b)
	_raton(b, false)


func _qos_es(h: Node, fiable: bool, prof: int) -> bool:
	var q = h.qos
	return q != null and q.get_reliability() == (RosQoS.RELIABLE if fiable else RosQoS.BEST_EFFORT) \
			and q.get_depth() == prof and q.get_durability() == RosQoS.VOLATILE and q.get_history() == RosQoS.KEEP_LAST


func _activa(hs: Array) -> String:
	for h in hs:
		if h.activa:
			return h.nombre_herramienta()
	return ""


# ---------------------------------------------------------------------------------------------------------------
# PC: publicar al soltar, QoS de la tabla, frame, ejes, covarianza, SELECT, teleop
# ---------------------------------------------------------------------------------------------------------------
func _probar_pc() -> void:
	var teleop := _herr("Teleop", "teleop.gd")
	var meta := _herr("Meta", "meta.gd")
	var pose := _herr("PoseInicial", "pose_inicial.gd")
	var punto := _herr("Punto", "punto.gd")
	var be := _herr("MetaBE", "meta.gd", {"topic": "/goal_be", "fiabilidad": 1, "habilitado": true})
	var hs := [teleop, meta, pose, punto]
	var e := _visor(false, hs + [be])
	var v: Node = e.visor
	await _esperar(v)
	check(v.ros_listo, "PC: el visor arranca en loopback")
	_escuchar(v)
	for h in hs:
		check(h.estado == "ok" and h.pub != null and not h.activa, "PC: %s conectada, sin activar" % h.name)
	check(v.displays.has(meta), "VisorRos conecta las herramientas (grupo display_ros)")
	check(_qos_es(meta, true, 5) and _qos_es(pose, true, 5) and _qos_es(punto, true, 5),
			"QoS PC: meta, pose inicial y punto fiables, KEEP_LAST 5, volátiles (doc 36 §6)")
	check(_qos_es(teleop, true, 1), "QoS: teleop fiable, KEEP_LAST 1, volátil")
	check(_qos_es(be, false, 5), "QoS: fiabilidad = BEST_EFFORT se respeta")
	check(meta.topic == "goal_pose" and pose.topic == "initialpose" and punto.topic == "/clicked_point"
			and teleop.topic == "/cmd_vel", "topics de RViz (goal_pose e initialpose relativos)")
	be.habilitado = false                      # fuera del ciclo de SELECT a partir de aquí
	be.desconectar()
	be.estado = "desactivado"

	# Sin herramienta activa, un clic no publica nada.
	_gesto(_px(1, 1), _px(1, 1))
	await _fotogramas(3)
	check(_n("/goal_pose") + _n("/initialpose") + _n("/clicked_point") == 0, "sin herramienta activa no se publica")

	# SELECT: ninguna → Teleop → Meta (un evento = un cambio) y nombre en la barra.
	_boton(JOY_BUTTON_BACK)
	check(_activa(hs) == "Teleop", "SELECT 1: Teleop (%s)" % _activa(hs))
	_boton(JOY_BUTTON_BACK)
	check(_activa(hs) == "Meta", "SELECT 2: Meta (%s)" % _activa(hs))
	await _fotogramas(2)
	check(e.barra.herramienta == "Meta" and e.barra.componer().ends_with("Meta"), "la barra de estado enseña «Meta»")

	# Meta: pulsar (2, 1), arrastrar a (2, 3) → rumbo +90°, soltar = UN mensaje.
	_gesto(_px(2, 1), _px(2, 3))
	await _fotogramas(3)
	check(_n("/goal_pose") == 1 and meta.publicados == 1, "meta PC: un mensaje al soltar (%d)" % _n("/goal_pose"))
	var g = _ultimo("/goal_pose")
	if g != null:
		check(g.header.frame_id == "odom", "meta: frame_id = marco fijo del visor (%s)" % g.header.frame_id)
		check(is_equal_approx(g.pose.position.x, 2.0) and is_equal_approx(g.pose.position.y, 1.0)
				and is_zero_approx(g.pose.position.z), "meta: posición ROS (2, 1, 0) desde la planta (%s)"
				% Vector3(g.pose.position.x, g.pose.position.y, g.pose.position.z))
		check(is_equal_approx(g.pose.orientation.z, sin(PI / 4)) and is_equal_approx(g.pose.orientation.w, cos(PI / 4))
				and is_zero_approx(g.pose.orientation.x), "meta: rumbo atan2(Δy, Δx) = 90° → (0, 0, sin45°, cos45°)")
		check(g.header.stamp.sec > 0 or g.header.stamp.nanosec > 0, "meta: sello del nodo (now)")
	# Un clic sin arrastre: rumbo 0 (no hereda el de la meta anterior).
	_gesto(_px(-1, 0), _px(-1, 0))
	await _fotogramas(3)
	g = _ultimo("/goal_pose")
	check(_n("/goal_pose") == 2 and g != null and is_equal_approx(g.pose.orientation.w, 1.0)
			and is_equal_approx(g.pose.position.x, -1.0), "meta: clic sin arrastre = rumbo 0 en (−1, 0)")
	# Arrastre por debajo del umbral de 5 cm: sigue con rumbo 0.
	_gesto(_px(0, 0), _px(0, 0.04))
	await _fotogramas(3)
	g = _ultimo("/goal_pose")
	check(g != null and is_equal_approx(g.pose.orientation.w, 1.0), "meta: arrastre < 5 cm no cambia el rumbo")

	# Pose inicial: SELECT → Pose inicial; clic con arrastre hacia −x (rumbo 180°).
	_boton(JOY_BUTTON_BACK)
	check(_activa(hs) == "Pose inicial" and not meta.activa, "SELECT 3: Pose inicial (y la meta se apaga)")
	_gesto(_px(-1, 0.5), _px(-2, 0.5))
	await _fotogramas(3)
	check(_n("/initialpose") == 1 and _n("/goal_pose") == 3, "pose inicial: un mensaje en /initialpose y ninguno en goal_pose")
	var ip = _ultimo("/initialpose")
	if ip != null:
		check(ip.header.frame_id == "odom", "pose inicial: frame_id = marco fijo")
		check(is_equal_approx(ip.pose.pose.position.x, -1.0) and is_equal_approx(ip.pose.pose.position.y, 0.5),
				"pose inicial: posición ROS (−1, 0,5)")
		check(absf(absf(ip.pose.pose.orientation.z) - 1.0) < 1e-6 and absf(ip.pose.pose.orientation.w) < 1e-6,
				"pose inicial: rumbo 180°")
		var cov: PackedFloat64Array = ip.pose.covariance
		var resto := 0.0
		for i in cov.size():
			if i != 0 and i != 7 and i != 35:
				resto += absf(cov[i])
		check(cov.size() == 36 and is_equal_approx(cov[0], 0.25) and is_equal_approx(cov[7], 0.25)
				and absf(cov[35] - 0.06853891945200942) < 1e-12 and resto == 0.0,
				"covarianza de initialpose como RViz: [0] = [7] = 0,25, [35] = (π/12)², resto 0")

	# Punto: SELECT → Punto; un clic = un PointStamped y la herramienta se desactiva («Single click»).
	_boton(JOY_BUTTON_BACK)
	check(_activa(hs) == "Punto", "SELECT 4: Punto")
	_gesto(_px(3, -2), _px(3, -2))
	await _fotogramas(3)
	check(_n("/clicked_point") == 1, "punto: un mensaje en /clicked_point")
	var cp = _ultimo("/clicked_point")
	if cp != null:
		check(cp.header.frame_id == "odom" and is_equal_approx(cp.point.x, 3.0) and is_equal_approx(cp.point.y, -2.0)
				and is_zero_approx(cp.point.z), "punto: (3, −2, 0) en el marco fijo")
	check(not punto.activa and _activa(hs) == "", "punto: «Single click» la desactiva")
	await _fotogramas(2)
	check(e.barra.herramienta == "", "la barra se vacía sin herramienta activa")
	_gesto(_px(3, -2), _px(3, -2))
	await _fotogramas(3)
	check(_n("/clicked_point") == 1, "punto desactivado: un segundo clic no publica")
	# SELECT desde «ninguna» vuelve a la primera.
	_boton(JOY_BUTTON_BACK)
	check(_activa(hs) == "Teleop", "SELECT desde ninguna → Teleop")
	var k := InputEventKey.new()
	k.keycode = KEY_TAB
	k.pressed = true
	root.push_input(k)
	check(_activa(hs) == "Meta", "Tab en el PC = SELECT")
	meta.activar(false)

	# Teleop (entrada simulada; el temporizador de 20 Hz existe).
	check(teleop._timer != null, "teleop: RosTimer de 0,05 s creado en conectar()")
	# El temporizador publica solo (20 Hz) con la herramienta activa y hombre muerto; luego se para para contar a mano.
	teleop.simular(0.2, 0.0, true)
	teleop.activar(true)
	await create_timer(0.3).timeout
	await _fotogramas(2)
	check(_n("/cmd_vel") >= 2, "teleop: el RosTimer publica a ~20 Hz (%d en 0,3 s)" % _n("/cmd_vel"))
	teleop._timer.cancel()
	teleop.simular(0.0, 0.0, false)
	teleop.tick()                              # el cero de parada
	teleop.activar(false)
	await _fotogramas(2)
	var antes := _n("/cmd_vel")
	teleop.simular(1.0, 0.5, true)
	teleop.tick()
	await _fotogramas(2)
	check(_n("/cmd_vel") == antes, "teleop inactiva: con hombre muerto no publica")
	teleop.activar(true)
	teleop.tick()
	teleop.tick()
	await _fotogramas(3)
	var tw = _ultimo("/cmd_vel")
	check(_n("/cmd_vel") == antes + 2 and tw != null and is_equal_approx(tw.linear.x, 0.5)
			and is_equal_approx(tw.angular.z, 1.0 * 0.5), "teleop: Twist (0,5 m/s, 0,5 rad/s) con hombre muerto")
	teleop.simular(1.0, 0.5, false)
	teleop.tick()
	teleop.tick()
	teleop.tick()
	await _fotogramas(3)
	tw = _ultimo("/cmd_vel")
	check(_n("/cmd_vel") == antes + 3 and tw != null and tw.linear.x == 0.0 and tw.angular.z == 0.0,
			"teleop: al soltar, UN Twist cero y silencio")
	teleop.simular(-0.0, -0.0, true)
	teleop.tick()
	check(1.0 / teleop.ultimo_lin > 0.0 and 1.0 / teleop.ultimo_ang > 0.0, "teleop: nunca publica −0,0")
	teleop.simular(0.8, 0.0, true)
	teleop.tick()
	var n_antes := _n("/cmd_vel")
	await _fotogramas(2)
	n_antes = _n("/cmd_vel")
	teleop.activar(false)                      # SELECT con el robot en marcha
	await _fotogramas(3)
	tw = _ultimo("/cmd_vel")
	check(_n("/cmd_vel") == n_antes + 1 and tw != null and tw.linear.x == 0.0, "teleop: desactivar en marcha manda el cero")
	teleop.activar(true)
	_boton(JOY_BUTTON_Y)
	check(is_equal_approx(teleop.escala, 1.25), "teleop: △ sube la escala")
	_boton(JOY_BUTTON_A)
	_boton(JOY_BUTTON_A)
	check(is_equal_approx(teleop.escala, 0.75), "teleop: ✕ la baja")
	teleop.activar(false)
	await _cerrar(e)


# ---------------------------------------------------------------------------------------------------------------
# Vita simulada: profundidad 1, ✕ confirma meta y pose inicial, un toque = un evento
# ---------------------------------------------------------------------------------------------------------------
func _probar_vita() -> void:
	var meta := _herr("Meta", "meta.gd")
	var pose := _herr("PoseInicial", "pose_inicial.gd")
	var punto := _herr("Punto", "punto.gd")
	var teleop := _herr("Teleop", "teleop.gd")
	var e := _visor(true, [meta, pose, punto, teleop])
	var v: Node = e.visor
	await _esperar(v)
	_escuchar(v)
	check(_qos_es(meta, true, 1) and _qos_es(pose, true, 1) and _qos_es(punto, true, 1) and _qos_es(teleop, true, 1),
			"QoS Vita: fiable, KEEP_LAST 1, volátil en las cuatro (doc 36 §6)")

	meta.activar(true)
	_gesto(_px(1, 1), _px(2, 1))
	await _fotogramas(3)
	check(meta.toques == 1, "Vita: un toque = un evento (%d)" % meta.toques)
	check(_n("/goal_pose") == 0 and meta.pendiente(), "Vita: la meta queda pendiente al soltar (no publica)")
	# Un ScreenTouch (lo que además genera el táctil) no cuenta: solo el ratón emulado.
	var st := InputEventScreenTouch.new()
	st.position = _px(1, 1)
	st.pressed = true
	root.push_input(st)
	check(meta.toques == 1 and meta.pendiente(), "Vita: InputEventScreenTouch no duplica el evento")
	_boton(JOY_BUTTON_A)
	await _fotogramas(3)
	check(_n("/goal_pose") == 1 and not meta.pendiente(), "Vita: ✕ publica la meta pendiente (un mensaje)")
	var g = _ultimo("/goal_pose")
	check(g != null and g.header.frame_id == "odom" and is_equal_approx(g.pose.position.x, 1.0)
			and is_equal_approx(g.pose.orientation.w, 1.0), "Vita: meta (1, 1) rumbo 0 en el marco fijo")
	_boton(JOY_BUTTON_A)
	await _fotogramas(3)
	check(_n("/goal_pose") == 1, "Vita: un segundo ✕ sin meta pendiente no publica")
	# ○ descarta lo pendiente.
	_gesto(_px(0, 0), _px(0, 0))
	_boton(JOY_BUTTON_B)
	_boton(JOY_BUTTON_A)
	await _fotogramas(3)
	check(_n("/goal_pose") == 1, "Vita: ○ descarta la meta pendiente")

	pose.activar(true)
	check(not meta.activa, "Vita: activar una herramienta apaga la otra")
	_gesto(_px(0.5, -0.5), _px(0.5, 0.5))
	await _fotogramas(3)
	check(_n("/initialpose") == 0, "Vita: la pose inicial también espera a ✕")
	_boton(JOY_BUTTON_A)
	await _fotogramas(3)
	var ip = _ultimo("/initialpose")
	check(_n("/initialpose") == 1 and ip != null and is_equal_approx(ip.pose.covariance[35], pow(PI / 12.0, 2.0))
			and is_equal_approx(ip.pose.pose.orientation.z, sin(PI / 4)), "Vita: ✕ publica la pose inicial (rumbo 90°, covarianza RViz)")

	punto.activar(true)
	_raton(_px(1, 2), true)
	_raton(_px(1, 2), false)
	await _fotogramas(3)
	check(_n("/clicked_point") == 1 and punto.toques == 1, "Vita: un toque = un PointStamped (sin ✕)")
	await _cerrar(e)


# ---------------------------------------------------------------------------------------------------------------
# Vista 3D (sin planta): rayo de cámara al suelo y rayo de física contra el mundo
# ---------------------------------------------------------------------------------------------------------------
func _probar_3d() -> void:
	var meta := _herr("Meta", "meta.gd")
	var punto := _herr("Punto", "punto.gd", {"un_solo_clic": false})
	var e := _visor(false, [meta, punto], false)
	var v: Node = e.visor
	var cam: Camera3D = e.cam
	await _esperar(v)
	_escuchar(v)
	# Godot (−1, 0, −2) = ROS (2, 1, 0) (ros = (−g.z, −g.x, g.y)).
	var objetivo := Vector3(-1, 0, -2)
	check(rclgd.godot_to_ros_vector(objetivo).is_equal_approx(Vector3(2, 1, 0)), "godot_to_ros_vector: (−1, 0, −2) → (2, 1, 0)")
	var p := cam.unproject_position(objetivo)
	var suelo = meta.suelo_ros(p)
	check(suelo != null and (suelo as Vector3).is_equal_approx(Vector3(2, 1, 0)),
			"3D: rayo de cámara al suelo = ROS (2, 1, 0) (%s)" % [suelo])
	meta.activar(true)
	_gesto(p, cam.unproject_position(Vector3(-1, 0, -4)))   # hacia +x ROS
	await _fotogramas(3)
	var g = _ultimo("/goal_pose")
	check(_n("/goal_pose") == 1 and g != null and is_equal_approx(g.pose.position.x, 2.0)
			and is_equal_approx(g.pose.position.y, 1.0) and is_equal_approx(g.pose.orientation.w, 1.0),
			"3D: meta en ROS (2, 1) con rumbo 0 (arrastre hacia +x)")
	# Marco fijo desplazado: un nodo en Godot (1, 0, 0) ⇒ el mismo punto queda en ROS (2, 2, 0).
	var mf := Node3D.new()
	mf.position = Vector3(1, 0, 0)
	e.raiz.add_child(mf)
	meta.marco_fijo_nodo = mf
	suelo = meta.suelo_ros(p)
	check(suelo != null and (suelo as Vector3).is_equal_approx(Vector3(2, 2, 0)), "3D: marco_fijo_nodo desplaza el suelo")
	meta.marco_fijo_nodo = null

	# Punto contra el suelo (sin colisiones) y contra una losa de 4 × 1 × 4 m centrada en el objetivo (cara de arriba
	# en z = 0,5; el rayo de la cámara la corta por arriba en Godot (−0,9, 0,5, −1,3) = ROS (1,3, 0,9, 0,5)).
	punto.activar(true)
	_gesto(p, p)
	await _fotogramas(3)
	var cp = _ultimo("/clicked_point")
	check(cp != null and is_equal_approx(cp.point.x, 2.0) and is_equal_approx(cp.point.y, 1.0) and is_zero_approx(cp.point.z),
			"3D: punto sin colisiones = suelo (2, 1, 0)")
	var cuerpo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(4, 1, 4)
	forma.shape = caja
	cuerpo.add_child(forma)
	cuerpo.position = objetivo
	e.raiz.add_child(cuerpo)
	await physics_frame
	await physics_frame
	_gesto(p, p)
	await _fotogramas(3)
	cp = _ultimo("/clicked_point")
	check(_n("/clicked_point") == 2 and cp != null and is_equal_approx(cp.point.z, 0.5)
			and absf(cp.point.x - 1.3) < 0.01 and absf(cp.point.y - 0.9) < 0.01,
			"3D: rayo de física contra la losa → ROS (1,3, 0,9, 0,5) (%.2f, %.2f, %.2f)" % [cp.point.x, cp.point.y, cp.point.z] if cp != null else "3D: punto contra la caja")
	check(punto.activa, "3D: con un_solo_clic = false la herramienta sigue activa")
	await _cerrar(e)


# ---------------------------------------------------------------------------------------------------------------
# godot/visor-ros/main.tscn: las cuatro herramientas en la escena (regla doc 35), sin chocar con el banco ni el HUD
# ---------------------------------------------------------------------------------------------------------------
func _probar_escena() -> void:
	if not ResourceLoader.exists("res://main.tscn"):
		return
	var esc: Node = load("res://main.tscn").instantiate()
	var v: Node = esc.get_node("VisorRos")
	v.transporte = "loopback"
	v.reintento_s = 0.0
	root.add_child(esc)
	await _esperar(v)
	var hs: Array = esc.get_node("VisorRos/Hud/Herramientas").get_children()
	var nombres := PackedStringArray()
	for h in hs:
		nombres.append(h.nombre_herramienta())
	check(nombres == PackedStringArray(["Teleop", "Meta", "Pose inicial", "Punto"]), "main.tscn: herramientas en orden de SELECT (%s)" % ", ".join(nombres))
	check(hs.all(func(h): return h.estado == "ok" and not h.activa), "main.tscn: las cuatro conectadas y ninguna activa")
	check(hs[1].planta == esc.get_node("VisorRos/Planta/Vista"), "main.tscn: meta toca en la planta 2D")
	check(int(esc.get_node("BancoPrimitivas").boton) != JOY_BUTTON_BACK, "main.tscn: el banco E-W8-1 no usa SELECT")
	check(int(esc.get_node("VisorRos/Hud/GestorHud").boton_siguiente) == -1, "main.tscn: R libre para el hombre muerto")
	_boton(JOY_BUTTON_BACK)
	check(hs[0].activa and not hs[1].activa, "main.tscn: SELECT activa Teleop")
	hs[0].activar(false)
	esc.queue_free()
	await _fotogramas(2)
