extends SceneTree
## Prueba de movimiento del G1 de g1-sensores (headless, sin ROS): mapeo de mandos = g1-unitree, `_clip_para`,
## root motion = marcha.gd de referencia, giro, emergencia, pared con move_and_slide y modo g1_sim simulado.
## Uso: godot --headless --path godot/g1-sensores --script res://pruebas/movimiento_g1.gd -- sin_ros

class Msg:
	var data: PackedFloat32Array

var app: Node
var robot
var paso := 0
var fallos := 0
var fase := ""
var p0 := Vector3.ZERO
var yaw0 := 0.0
var ref   # marcha.gd de referencia (g1-unitree)
var ref_pos0 := Vector2.ZERO


func check(c: bool, n: String) -> void:
	if c: print("OK ", n)
	else:
		fallos += 1
		print("FALLO ", n)


func _initialize() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)


func _key(k: int, p: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = p
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _physics_process(dt: float) -> bool:
	paso += 1
	if robot == null:
		robot = app.get("robot")
		return false
	match paso:
		5:
			# mapeo de teclas
			_key(KEY_W, true); check(robot.leer_teleop() == Vector3(0.7, 0, 0), "W = avanzar 0,7"); _key(KEY_W, false)
			_key(KEY_A, true); check(robot.leer_teleop() == Vector3(0, 0, 1), "A = girar izq."); _key(KEY_A, false)
			_key(KEY_D, true); check(robot.leer_teleop() == Vector3(0, 0, -1), "D = girar der."); _key(KEY_D, false)
			_key(KEY_Q, true); check(robot.leer_teleop() == Vector3(0, 0.4, 0), "Q = lateral izq."); _key(KEY_Q, false)
			_key(KEY_W, true); _key(KEY_SHIFT, true); check(robot.leer_teleop() == Vector3(1, 0, 0), "Mayús+W = correr")
			_key(KEY_W, false); _key(KEY_SHIFT, false)
			check(robot.leer_teleop() == Vector3.ZERO, "sin teclas = cero")
			check(robot._clip_para(Vector3(1, 0, 0)) == "correr" and robot._clip_para(Vector3(0.7, 0, 0)) == "andar", "_clip_para")
			p0 = robot.posicion_ros(); yaw0 = robot.rotation.y
			ref = load("res://marcha.gd").new(); ref.cargar("res://anim/g1_marcha.json")
			ref.pos = Vector2(p0.x, p0.y); ref.yaw = yaw0; ref.f = robot.marcha.f
		6:
			pass
	if paso >= 6 and paso < 186:   # 3 s andando por /cmd_vel externo (fijar_orden)
		robot.fijar_orden(Vector3(0.5, 0, 0))
		if paso > 6:
			ref.pedir("andar"); ref.avanzar(dt, func(_p): return true)
	if paso == 186:
		var p: Vector3 = robot.posicion_ros()
		var d := Vector2(p.x - p0.x, p.y - p0.y)
		var esperado: Vector2 = ref.pos - Vector2(p0.x, p0.y)
		print("andar 3 s: ", d, " ref g1-unitree ", esperado, " clip ", robot.marcha.actual)
		check(robot.marcha.actual == "andar", "cmd 0,5 → clip andar")
		check(d.length() > 1.0 and absf(d.length() - esperado.length()) < 0.15, "root motion = marcha.gd de g1-unitree")
		check(d.normalized().dot(Vector2(cos(yaw0), sin(yaw0))) > 0.95, "avanza hacia donde mira")
		yaw0 = robot.rotation.y
	if paso > 186 and paso < 306:
		robot.fijar_orden(Vector3(0, 0, 0.5))
	if paso == 306:
		check(robot.marcha.actual == "girar_izq", "wz>0 → girar_izq")
		var dy := wrapf(robot.rotation.y - yaw0, -PI, PI)
		print("giro 2 s: ", dy)
		check(dy > 0.3, "gira a la izquierda (yaw ROS crece)")
		robot.fijar_emergencia(true)
	if paso > 306 and paso < 330:
		robot.fijar_orden(Vector3(0.5, 0, 0))
	if paso == 330:
		check(robot.marcha.actual == "quieto" and robot.orden_objetivo == Vector3.ZERO, "emergencia: quieto e ignora órdenes")
		robot.fijar_emergencia(false)
		# Pared delante: caja estática a 1 m
		var pared := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var caja := BoxShape3D.new(); caja.size = Vector3(4, 3, 0.4)
		cs.shape = caja; pared.add_child(cs)
		root.add_child(pared)
		var yaw: float = robot.rotation.y
		var delante: Vector3 = robot.global_position + Vector3(-sin(yaw), 0, -cos(yaw)) * 1.2
		pared.global_position = delante + Vector3(0, 1.5, 0)
		pared.rotation.y = yaw
		p0 = robot.posicion_ros()
	if paso > 330 and paso < 630:
		robot.fijar_orden(Vector3(0.7, 0, 0))
	if paso == 630:
		var p: Vector3 = robot.posicion_ros()
		var d := Vector2(p.x - p0.x, p.y - p0.y).length()
		print("contra la pared 5 s: ", d)
		check(d < 1.2 and robot._bloqueado, "la pared lo para (move_and_slide)")
		# g1_sim simulado: dos estados
		robot.fijar_fuente("g1_sim")
		p0 = robot.posicion_ros(); yaw0 = robot.rotation.y
		var m := Msg.new()
		var d0 := PackedFloat32Array([3.0, 4.0, 0.79, 0, 0, 0, 1]); d0.resize(19)
		m.data = d0; robot._on_estado_sim(m)
	if paso == 633:
		var p: Vector3 = robot.posicion_ros()
		check(Vector2(p.x - p0.x, p.y - p0.y).length() < 1e-3, "g1_sim relativo: primera pose = pose actual")
		var m := Msg.new()
		var s := sin(0.25); var c := cos(0.25)   # +0,5 rad de yaw
		var d1 := PackedFloat32Array([4.0, 4.0, 0.79, 0, 0, s, c]); d1.resize(19)
		d1[10] = 0.5   # rodilla izq. (índice 3 de las piernas)
		m.data = d1; robot._on_estado_sim(m)
	if paso == 636:
		var p: Vector3 = robot.posicion_ros()
		var d := Vector2(p.x - p0.x, p.y - p0.y)
		print("g1_sim +1 m en x_sim: ", d, " yaw ", wrapf(robot.rotation.y - yaw0, -PI, PI))
		check(absf(d.length() - 1.0) < 1e-3 and d.normalized().dot(Vector2(cos(yaw0), sin(yaw0))) > 0.999, "g1_sim: avance relativo al rumbo")
		check(absf(wrapf(robot.rotation.y - yaw0, -PI, PI) - 0.5) < 1e-3, "g1_sim: yaw")
		check(absf(robot.posiciones_joints(PackedStringArray(["left_knee_joint"]))[0] - 0.5) < 1e-4, "g1_sim: juntas")
		robot.fijar_fuente("local")
	if paso == 640:
		print("RESULTADO fallos=", fallos)
		quit(1 if fallos else 0)
	return false
