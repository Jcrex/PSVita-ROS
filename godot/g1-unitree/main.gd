extends Node3D
## Proyecto G1 — Unitree G1 (29 GDL, URDF oficial de unitree_rl_gym) en Godot 4, para el PC y la PS Vita.
##
## Fase 1 · importación: robot/g1_vita.tscn (~12 600 triángulos) en la Vita, robot/g1_pc.tscn (~60 600) en el
##          PC, generados con tools/urdf2godot/urdf2godot.py. Modos «de pie» y «barrido» (valida cada joint).
## Fase 2 · desplazamiento con el control oficial de Unitree (su política de marcha en MuJoCo):
##          «marcha»: clips grabados de esa política (anim/g1_marcha.json) con desplazamiento integrado; no
##                    necesita PC ni red (vale en la Vita sola).
##          «ros»:    en vivo: la Vita/PC publica /cmd_vel y recibe /g1/estado del simulador
##                    (docker/vita-ros.sh g1 → docker/g1/g1_sim.py).
## Fase 3 · casa: casa/casa.tscn (de docker/g1/casa.json; la misma casa está en MuJoCo y en casa/mapa.pgm).
##
## Mandos (Vita / teclado):
##   stick izq. ↑↓ (W/S) andar adelante/atrás (a tope = correr, o Mayús) · stick izq. ←→ (A/D) girar
##   L/R (Q/E) paso lateral · stick der. (arrastrar ratón) cámara · cruceta ↑↓ (rueda) zoom
##   ✕ (Espacio) cambia de modo · △ (R) vuelve al inicio (en modo ros sin conexión: reintenta) · ○ (C) cenital
## Argumentos tras `--`: `captura=/ruta.png` (+ `fotograma=N`, por defecto 60) guarda una imagen y sale;
## `modo=barrido|marcha|ros|de_pie`; `lod=g1_vita`; `demo` (la marcha se conduce sola, para pruebas);
## `sin_ros` (no conectar con el agente al arrancar).

const Marcha := preload("res://marcha.gd")
const ColisionCasa := preload("res://colision_casa.gd")

const MODOS := ["marcha", "ros", "de pie", "barrido"]
const POSE_DEFECTO := {   # deploy/deploy_mujoco/configs/g1.yaml (default_angles) de unitree_rl_gym
	"left_hip_pitch_joint": -0.1, "left_knee_joint": 0.3, "left_ankle_pitch_joint": -0.2,
	"right_hip_pitch_joint": -0.1, "right_knee_joint": 0.3, "right_ankle_pitch_joint": -0.2,
}
const ALTURA_PELVIS := 0.78   # m sobre el suelo con la pose por defecto (ROS z)
const ZONA_MUERTA := 0.25

var robot: Node3D
var casa: Node3D
var camara: Camera3D
var hud: Label
var marcha := Marcha.new()
var colision := ColisionCasa.new()
var modo := "marcha"
var inicio := Vector3.ZERO     # x, y, yaw en el mundo (ROS)
var t := 0.0
var yaw_cam := 0.0            # desfase de la cámara respecto a la espalda del robot
var yaw_seguir := 0.0         # guiñada del robot suavizada (la cámara le sigue por detrás)
var yaw_robot := 0.0
var pitch_cam := 0.45
var dist_cam := 3.2
var cenital := false
var captura := ""
var fotograma_captura := 60
var fotogramas := 0
var tris_robot := "?"
var lod_forzado := ""
var demo := false
var sin_ros := false
var ros_intentos := 0
var _hud_t := 0.0
var _arrastrando := false

# ROS (modo «ros»)
var node: RosNode
var pub_cmd: RosPublisher
var sub_estado: RosSubscriber   # guardar las referencias: RefCounted, si se sueltan se cancelan
var ros_listo := false
var ros_error := ""
var estado_n := 0
var estado_t := -1.0
var _cmd_t := 0.0
var cmd := Vector3.ZERO        # vx, vy, wz pedidos


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("captura="):
			captura = a.substr(8)
		elif a.begins_with("fotograma="):
			fotograma_captura = a.substr(10).to_int()
		elif a.begins_with("modo="):
			modo = a.substr(5).replace("_", " ")
		elif a.begins_with("lod="):
			lod_forzado = a.substr(4)
		elif a == "demo":
			demo = true
		elif a == "sin_ros":
			sin_ros = true
	var lod := "g1_vita" if OS.has_feature("vita") else "g1_pc"
	if lod_forzado != "":
		lod = lod_forzado
	casa = load("res://casa/casa.tscn").instantiate()
	add_child(casa)
	inicio = casa.get_meta("inicio_robot", Vector3.ZERO)
	colision.cargar(casa)
	robot = load("res://robot/%s.tscn" % lod).instantiate()
	add_child(robot)
	tris_robot = _leer_tris(lod)
	if not marcha.cargar("res://anim/g1_marcha.json"):
		push_error("no se pudo cargar anim/g1_marcha.json")
	_montar_escena()
	_reiniciar()
	# Conectar con el agente al arrancar, como G6/G7 (camino probado en la Vita). Si no hay agente, el modo
	# marcha sigue funcionando; en modo ros, △ reintenta. `ros/conectar_al_inicio=false` o `-- sin_ros` lo evita.
	if ProjectSettings.get_setting("ros/conectar_al_inicio", true) and not sin_ros:
		_iniciar_ros()


func _leer_tris(lod: String) -> String:
	var f := FileAccess.open("res://robot/mallas_%s/informe.json" % lod, FileAccess.READ)
	if f == null:
		return "?"
	var d = JSON.parse_string(f.get_as_text())
	return "%d" % d.get("triangulos_escena", 0) if d is Dictionary else "?"


func _montar_escena() -> void:
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	add_child(luz)
	var amb := WorldEnvironment.new()
	amb.environment = Environment.new()
	amb.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	amb.environment.ambient_light_color = Color(0.5, 0.52, 0.58)
	add_child(amb)
	camara = Camera3D.new()
	camara.fov = 55
	camara.far = 60
	add_child(camara)
	hud = Label.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hud.add_theme_constant_override("outline_size", 4)
	var capa := CanvasLayer.new()
	capa.add_child(hud)
	add_child(capa)


func _reiniciar() -> void:
	marcha.pos = Vector2(inicio.x, inicio.y)
	marcha.yaw = inicio.z
	marcha.f = 0.0
	yaw_robot = inicio.z
	yaw_seguir = inicio.z
	_pose_defecto()


func _pose_defecto() -> void:
	var nombres: PackedStringArray = robot.nombres_joints_movibles()
	var pos := PackedFloat32Array()
	for n in nombres:
		pos.append(POSE_DEFECTO.get(n, 0.0))
	robot.set_joints(nombres, pos)
	robot.set_base_pose_ros(Vector3(marcha.pos.x, marcha.pos.y, ALTURA_PELVIS),
			Quaternion(Vector3(0, 0, 1), marcha.yaw))


## Barrido: cada articulación oscila dentro de sus límites con una fase distinta (fase 1).
func _barrido() -> void:
	var nombres: PackedStringArray = robot.nombres_joints_movibles()
	var pos := PackedFloat32Array()
	for i in nombres.size():
		var j: Node3D = robot.find_child(nombres[i], true, false)
		var lo: float = j.get_meta("urdf_lower", -0.5)
		var hi: float = j.get_meta("urdf_upper", 0.5)
		var centro := clampf(POSE_DEFECTO.get(nombres[i], 0.0), lo, hi)
		var amp := minf(0.6, minf(hi - centro, centro - lo)) if hi > lo else 0.5
		pos.append(centro + amp * sin(t * 1.5 + i * 0.7))
	robot.set_joints(nombres, pos)


## Lee los mandos y devuelve la orden (vx, vy, wz) en el rango de la política de Unitree.
func _leer_orden() -> Vector3:
	var ly := -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	var lx := -Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if Input.is_key_pressed(KEY_W): ly = 0.7
	if Input.is_key_pressed(KEY_S): ly = -0.7
	if Input.is_key_pressed(KEY_A): lx = 1.0
	if Input.is_key_pressed(KEY_D): lx = -1.0
	if Input.is_key_pressed(KEY_SHIFT) and ly > 0: ly = 1.0
	var vy := 0.0
	if Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER) or Input.is_key_pressed(KEY_Q): vy = 0.4
	if Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER) or Input.is_key_pressed(KEY_E): vy = -0.4
	if demo:   # recorrido de prueba: adelante, girar, lateral, atrás
		var c := fmod(t, 12.0)
		ly = 0.7 if c < 4.0 else (0.0 if c < 6.0 else (0.0 if c < 8.0 else -0.6))
		lx = 1.0 if (c >= 4.0 and c < 6.0) else 0.0
		vy = 0.4 if (c >= 6.0 and c < 8.0) else 0.0
	var vx := 0.0
	if absf(ly) > ZONA_MUERTA:
		vx = ly * (1.0 if ly > 0 else 0.6)
	var wz := lx if absf(lx) > ZONA_MUERTA else 0.0
	return Vector3(vx, vy, wz)


## Elige el clip grabado más parecido a la orden (modo «marcha»).
func _clip_para(o: Vector3) -> String:
	if o.x > 0.85: return "correr"
	if o.x > 0.0: return "andar"
	if o.x < 0.0: return "atras"
	if o.z > 0.0: return "girar_izq"
	if o.z < 0.0: return "girar_der"
	if o.y > 0.0: return "izquierda"
	if o.y < 0.0: return "derecha"
	return "quieto"


func _process(dt: float) -> void:
	t += dt
	cmd = _leer_orden()
	match modo:
		"barrido":
			_barrido()
		"marcha":
			marcha.pedir(_clip_para(cmd))
			marcha.avanzar(dt, colision.libre)
			var pb: Array = marcha.pose_base()
			robot.set_base_pose_ros(pb[0], pb[1])
			robot.set_joints(marcha.joints, marcha.q_joints())
			yaw_robot = marcha.yaw
		"ros":
			_cmd_t += dt
			if ros_listo and _cmd_t >= 0.05:   # /cmd_vel a 20 Hz
				_cmd_t = 0.0
				_publicar_cmd()
	_mover_camara(dt)
	_actualizar_hud(dt)
	fotogramas += 1
	if captura != "" and fotogramas == fotograma_captura:
		get_viewport().get_texture().get_image().save_png(captura)
		get_tree().quit()


func _actualizar_hud(dt: float) -> void:
	_hud_t += dt
	if _hud_t < 0.1:   # HUD a 10 Hz (optimización O1 de G7c)
		return
	_hud_t = 0.0
	var linea := ""
	match modo:
		"marcha":
			linea = "Clip: %s%s · (%.1f, %.1f) m · ROS: %s" % [marcha.actual, "  [pared]" if marcha.bloqueado else "",
					marcha.pos.x, marcha.pos.y, "conectado" if ros_listo else ("sin conexión" if ros_error != "" else "conectando...")]
		"ros":
			if ros_error != "":
				linea = ros_error
			elif not ros_listo:
				linea = "Conectando con el agente %s..." % ProjectSettings.get_setting("ros/agent_ip", "?")
			elif estado_t < 0 or t - estado_t > 1.0:
				linea = "Sin /g1/estado: arranca el simulador en el PC (docker/vita-ros.sh g1)"
			else:
				linea = "ROS en vivo · /g1/estado recibidos: %d · orden (%.1f, %.1f, %.1f)" % [estado_n, cmd.x, cmd.y, cmd.z]
		_:
			linea = ""
	hud.text = "Unitree G1 · modo: %s  (✕/Espacio cambia)\n%s\nFPS %d · %s triángulos" % [
			modo, linea, Engine.get_frames_per_second(), tris_robot]


# ---------------------------------------------------------------- ROS (modo «ros»)

func _iniciar_ros() -> void:
	if ros_listo:
		return
	ros_error = ""
	ros_intentos += 1
	_hud_t = 1.0                     # forzar el HUD: que se vea «Conectando...»
	await get_tree().process_frame   # pintar «Conectando...» antes de que init bloquee
	await get_tree().process_frame
	var err := rclgd.init(PackedStringArray(["-p", "transport:=xrce"]))
	if err != OK:
		# Diagnóstico de red de ros2_vita (xrce_transport.cpp: paso alcanzado, estado WiFi y códigos sce*).
		var d: Dictionary = rclgd.get_transport_info()
		ros_error = "Sin conexión con %s (intento %d): %s\npaso: %s · WiFi netctl=%s (3 = con IP) · net=%s ctl=%s udp=%s\n△ reintenta · en el PC: docker/vita-ros.sh g1" % [
				d.get("agent", ProjectSettings.get_setting("ros/agent_ip", "?")), ros_intentos, error_string(err),
				d.get("step", "?"), d.get("netctl_state", "?"), d.get("rc_netinit", "?"), d.get("rc_netctl", "?"),
				d.get("rc_net_udp", "?")]
		print("g1: ", ros_error)
		return
	node = RosNode.new()
	node.init("vita_g1", "")
	var qos := RosQoS.new()
	qos.set_reliability(RosQoS.BEST_EFFORT)   # g1_sim publica /g1/estado en best effort
	pub_cmd = node.create_publisher("/cmd_vel", "geometry_msgs/msg/Twist", qos)
	sub_estado = node.create_subscription("/g1/estado", "std_msgs/msg/Float32MultiArray", _on_estado, qos)
	ros_listo = true


## /g1/estado = [x, y, z, qx, qy, qz, qw, q0..q11] (docker/g1/g1_sim.py), piernas en el orden de marcha.joints.
func _on_estado(m) -> void:
	if modo != "ros":
		return
	var d: PackedFloat32Array = m.data
	if d.size() < 19:
		return
	estado_n += 1
	estado_t = t
	robot.set_base_pose_ros(Vector3(d[0], d[1], d[2]), Quaternion(d[3], d[4], d[5], d[6]))
	yaw_robot = atan2(2.0 * (d[6] * d[5] + d[3] * d[4]), 1.0 - 2.0 * (d[4] * d[4] + d[5] * d[5]))
	robot.set_joints(marcha.joints, d.slice(7, 19))


func _publicar_cmd() -> void:
	var m := RosMsg.from_type("geometry_msgs/msg/Twist")
	m.linear.x = cmd.x + 0.0   # +0.0 evita publicar -0.0
	m.linear.y = cmd.y + 0.0
	m.angular.z = cmd.z + 0.0
	pub_cmd.publish(m)


# ---------------------------------------------------------------- cámara y entrada

func _mover_camara(dt: float) -> void:
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rx) > 0.15:
		yaw_cam -= rx * 2.0 * dt
	if absf(ry) > 0.15:
		pitch_cam = clampf(pitch_cam + ry * 1.5 * dt, -0.1, 1.45)
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP):
		dist_cam = maxf(dist_cam - 3.0 * dt, 1.0)
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN):
		dist_cam = minf(dist_cam + 3.0 * dt, 14.0)
	var pelvis: Node3D = robot.find_child("pelvis", true, false)
	var objetivo := pelvis.global_position + Vector3(0, -0.2, 0)
	if cenital:
		# Vista de planta de toda la casa (10 × 8 m): centro de la casa en ROS (5, 4) → Godot (-4, 0, -5)
		camara.look_at_from_position(Vector3(-4, 12, -5 + 4.5), Vector3(-4, 0, -5))
		return
	# Guiñada de ROS y → Godot: «detrás del robot» = (sin y, 0, cos y). Se suaviza para no marear.
	yaw_seguir = lerp_angle(yaw_seguir, yaw_robot, 1.0 - exp(-dt / 0.6))
	var y := yaw_seguir + yaw_cam
	var dir := Vector3(sin(y) * cos(pitch_cam), sin(pitch_cam), cos(y) * cos(pitch_cam))
	camara.look_at_from_position(objetivo + dir * dist_cam, objetivo)


func _unhandled_input(ev: InputEvent) -> void:
	var boton := -1
	if ev is InputEventJoypadButton and ev.pressed:
		boton = ev.button_index
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		boton = {KEY_SPACE: JOY_BUTTON_A, KEY_R: JOY_BUTTON_Y, KEY_C: JOY_BUTTON_B}.get(ev.keycode, -1)
	match boton:
		JOY_BUTTON_A:   # ✕: siguiente modo
			modo = MODOS[(MODOS.find(modo) + 1) % MODOS.size()]
			if modo == "de pie":
				_pose_defecto()
			elif modo == "ros" and not ros_listo and ros_error == "":
				_iniciar_ros()
		JOY_BUTTON_Y:   # △: en modo ros sin conexión, reintentar; si no, volver al inicio
			if modo == "ros" and not ros_listo:
				_iniciar_ros()
			else:
				_reiniciar()
		JOY_BUTTON_B:   # ○: cámara cenital
			cenital = not cenital
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			_arrastrando = ev.pressed
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist_cam = maxf(dist_cam - 0.3, 1.0)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist_cam = minf(dist_cam + 0.3, 14.0)
	elif ev is InputEventMouseMotion and _arrastrando:
		yaw_cam -= ev.relative.x * 0.01
		pitch_cam = clampf(pitch_cam + ev.relative.y * 0.01, -0.1, 1.45)
