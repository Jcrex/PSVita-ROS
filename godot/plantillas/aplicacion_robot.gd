extends Node3D

const Util = preload("res://comun/ros/util_ros.gd")
const Mundo = preload("res://comun/mundo/mundo.tscn")
const SENSORES := {
	"imu": preload("res://comun/sensores/imu.gd"),
	"gps": preload("res://comun/sensores/gps.gd"),
	"odometria": preload("res://comun/sensores/odometria.gd"),
	"lidar_2d": preload("res://comun/sensores/lidar_2d.gd"),
	"lidar_3d": preload("res://comun/sensores/lidar_3d.gd"),
	"camara": preload("res://comun/sensores/camara.gd"),
	"rango": preload("res://comun/sensores/rango.gd"),
	"barometro": preload("res://comun/sensores/barometro.gd"),
	"magnetometro": preload("res://comun/sensores/magnetometro.gd"),
	"bateria": preload("res://comun/sensores/bateria.gd"),
	"joint_state": preload("res://comun/sensores/joint_state.gd"),
	"mapeo_2d": preload("res://comun/sensores/mapeo_2d.gd"),
}

@export var ruta_config := "res://robot.json"

var config: Dictionary
var robot: CharacterBody3D
var sensores: Dictionary = {}
var camara: Camera3D
var hud: Label
var ros_listo := false
var ros_error := ""
var sin_ros := false
var demo := false
var captura := ""
var fotograma_captura := 120
var transporte_override := ""
var lod_override := ""
var _fotogramas := 0
var _tiempo := 0.0
var _hud_t := 0.0
var _yaw_cam := 0.0
var _pitch_cam := 0.5
var _distancia_cam := 7.0
var _cenital := false
var _arrastrando := false
var _pub_tf_estatico: RosPublisher


func _ready() -> void:
	_leer_argumentos()
	config = JSON.parse_string(FileAccess.get_file_as_string(ruta_config))
	if config == null:
		push_error("No se pudo leer " + ruta_config)
		get_tree().quit(1)
		return
	add_child(Mundo.instantiate())
	_crear_robot()
	_montar_camara_hud()
	if not sin_ros:
		_conectar_deferred.call_deferred()


func _leer_argumentos() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "sin_ros": sin_ros = true
		elif a == "demo": demo = true
		elif a == "cenital": _cenital = true
		elif a.begins_with("captura="): captura = a.substr(8)
		elif a.begins_with("fotograma="): fotograma_captura = a.substr(10).to_int()
		elif a.begins_with("transporte="): transporte_override = a.substr(11)
		elif a.begins_with("lod="): lod_override = a.substr(4)
		elif a.begins_with("config="): ruta_config = a.substr(7)
		elif a.begins_with("agente="):
			ProjectSettings.set_setting("ros/agent_ip", a.substr(7))
		elif a.begins_with("puerto="):
			ProjectSettings.set_setting("ros/agent_port", a.substr(7).to_int())


func _crear_robot() -> void:
	var script_robot: Script = load(config.get("script", "res://comun/robots/robot_ros.gd"))
	robot = script_robot.new()
	robot.name = "Robot"
	for clave in config.get("control", {}):
		var valor = config.control[clave]
		if valor is Array and valor.size() == 3:
			valor = Vector3(valor[0], valor[1], valor[2])
		robot.set(clave, valor)
	if demo:
		robot.aceptar_teleop_local = false
	var colision := CollisionShape3D.new()
	var capsula := CapsuleShape3D.new()
	capsula.radius = config.get("radio_colision", 0.35)
	capsula.height = config.get("altura_colision", 1.0)
	colision.shape = capsula
	colision.position.y = capsula.height * 0.5
	robot.add_child(colision)
	add_child(robot)
	var spawn: Array = config.get("spawn_ros", [0.0, 0.0, 0.0, 0.0])
	robot.position = Util.vector_godot(Vector3(spawn[0], spawn[1], spawn[2]))
	robot.rotation.y = spawn[3]
	if robot.has_method("reiniciar_estado"):
		robot.reiniciar_estado()   # sin pico de velocidad del origen al spawn en la primera odometría (R2-B5)
	var clave_visual := "visual_vita" if OS.has_feature("vita") or lod_override == "vita" else "visual_pc"
	var visual_path: String = config.get(clave_visual, "")
	if visual_path != "":
		var visual: Node3D = load(visual_path).instantiate()
		visual.name = "Modelo"
		robot.add_child(visual)
	if robot.has_method("inicializar_modelo"):
		robot.call("inicializar_modelo", config)


func _conectar_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var transporte: String = transporte_override if transporte_override != "" else ProjectSettings.get_setting("ros/transport", "xrce")
	var err: int = robot.configurar_ros(config.get("nodo", "robot_godot"), config.get("namespace", ""), transporte)
	if err != OK:
		ros_error = "ROS: %s · agente %s" % [error_string(err), ProjectSettings.get_setting("ros/agent_ip", "?")]
		push_warning(ros_error)
		return
	ros_listo = true
	_crear_sensores()


func _crear_sensores() -> void:
	for datos in config.get("sensores", []):
		var tipo: String = datos.get("tipo", "")
		var script: Script = SENSORES.get(tipo)
		if script == null and tipo.begins_with("res://"):
			script = load(tipo)
		if script == null:
			push_error("Tipo de sensor desconocido: " + tipo)
			continue
		var sensor = script.new()
		sensor.name = datos.get("nombre", tipo)
		for clave in datos:
			if not ["tipo", "nombre", "padre", "pos_ros", "rpy_ros", "link", "tf_estatico"].has(clave):
				var valor = datos[clave]
				var anterior = sensor.get(clave)
				if valor is Array:
					if anterior is Vector2i and valor.size() == 2:
						valor = Vector2i(valor[0], valor[1])
					elif anterior is Vector2 and valor.size() == 2:
						valor = Vector2(valor[0], valor[1])
					elif anterior is Vector3 and valor.size() == 3:
						valor = Vector3(valor[0], valor[1], valor[2])
					elif anterior is PackedStringArray:
						valor = PackedStringArray(valor)
				sensor.set(clave, valor)
		sensor.contexto = robot.contexto
		sensor.robot = robot
		var pos: Array = datos.get("pos_ros", [0.0, 0.0, 0.0])
		var rpy: Array = datos.get("rpy_ros", [0.0, 0.0, 0.0])
		var padre: Node = robot
		var link: Node3D = _buscar_link(datos.get("link", ""))
		if link != null:
			# R2-A3: montado en un link del URDF horneado (ejes ROS): pos_ros/rpy_ros son relativos al link y la
			# base convierte los ejes Godot del sensor a los ejes ROS del link.
			padre = link
			sensor.position = Vector3(pos[0], pos[1], pos[2])
			sensor.basis = Util.base_sensor_en_link(rpy[0], rpy[1], rpy[2])
		else:
			sensor.position = Util.vector_godot(Vector3(pos[0], pos[1], pos[2]))
			sensor.basis = _base_ros(rpy[0], rpy[1], rpy[2])
			if datos.has("padre"):
				padre = sensores.get(datos.padre, robot)
		padre.add_child(sensor)
		sensores[sensor.name] = sensor
	if robot.has_method("sensores_listos"):
		robot.call("sensores_listos", sensores)
	_publicar_tf_estatico()


func _buscar_link(nombre: String) -> Node3D:
	if nombre == "":
		return null
	var modelo := robot.get_node_or_null("Modelo")
	var link: Node3D = modelo.find_child(nombre, true, false) if modelo != null else null
	if link == null:
		push_warning("Link «%s» no encontrado en el modelo; el sensor se monta en el cuerpo" % nombre)
	return link


## R2-A4: /tf_static (fiable + TRANSIENT_LOCAL, una vez) con los marcos que no da ningún URDF:
##  - "tf_estatico" de robot.json: lista de {padre, hijo, pos_ros, rpy_ros} (p. ej. el marco óptico de la D435);
##  - sensores con "tf_estatico": true (o todos si "tf_estatico_sensores": true): base → frame_id según
##    pos_ros/rpy_ros; la cámara añade frame_id → marco óptico (rpy −π/2, 0, −π/2) y el sonar orienta su eje x
##    al haz, como pide sensor_msgs/Range.
func _publicar_tf_estatico() -> void:
	var lista: Array = []
	for e in config.get("tf_estatico", []):
		var p: Array = e.get("pos_ros", [0.0, 0.0, 0.0])
		var r: Array = e.get("rpy_ros", [0.0, 0.0, 0.0])
		lista.append([e.padre, e.hijo, Vector3(p[0], p[1], p[2]), Util.rotacion_rpy_ros(r[0], r[1], r[2])])
	var base := _base_frame()
	var todos: bool = config.get("tf_estatico_sensores", false)
	var vistos := {}
	for datos in config.get("sensores", []):
		if not datos.get("tf_estatico", todos) or datos.has("link") or datos.has("padre"):
			continue
		var sensor = sensores.get(datos.get("nombre", datos.get("tipo", "")))
		# La odometría no es un marco hijo de la base (su frame_id es odom) y "sensor" es el valor por defecto.
		if sensor == null or sensor.get("frame_id") == null or sensor.get("odom_frame") != null \
				or sensor.frame_id == "sensor":
			continue
		var hijo: String = sensor.frame_id
		if hijo == "" or hijo == base or vistos.has(hijo):
			continue
		vistos[hijo] = true
		var p: Array = datos.get("pos_ros", [0.0, 0.0, 0.0])
		var r: Array = datos.get("rpy_ros", [0.0, 0.0, 0.0])
		var rot := Util.rotacion_rpy_ros(r[0], r[1], r[2])
		var d = sensor.get("direccion_ros")
		if d is Vector3 and d.length() > 0.0:
			var u: Vector3 = d.normalized()
			rot = rot * Util.rotacion_rpy_ros(0.0, -asin(clampf(u.z, -1.0, 1.0)), atan2(u.y, u.x))
		lista.append([base, hijo, Vector3(p[0], p[1], p[2]), rot])
		if sensor.has_method("_optical_frame"):
			lista.append([hijo, sensor.call("_optical_frame"), Vector3.ZERO,
				Util.rotacion_rpy_ros(-PI * 0.5, 0.0, -PI * 0.5)])
	if lista.is_empty():
		return
	var transforms: Array = []
	for e in lista:
		var t = RosMsg.from_type("geometry_msgs/msg/TransformStamped")
		robot.contexto.sello(t.header)
		t.header.frame_id = e[0]
		t.child_frame_id = e[1]
		Util.escribir_vector(t.transform.translation, e[2])
		Util.escribir_quat(t.transform.rotation, e[3].get_rotation_quaternion())
		transforms.append(t)
	var msg = RosMsg.from_type("tf2_msgs/msg/TFMessage")
	msg.transforms = transforms
	_pub_tf_estatico = robot.contexto.publicador("/tf_static", "tf2_msgs/msg/TFMessage", false, true)
	_pub_tf_estatico.publish(msg)


func _base_frame() -> String:
	for datos in config.get("sensores", []):
		if datos.get("tipo", "") == "odometria":
			return datos.get("base_frame", "base_footprint")
	return config.get("base_frame", "base_link")


func _base_ros(roll: float, pitch: float, yaw: float) -> Basis:
	var ros := Basis(Vector3(0.0, 0.0, 1.0), yaw) * Basis(Vector3(0.0, 1.0, 0.0), pitch) * Basis(Vector3(1.0, 0.0, 0.0), roll)
	var c := Util.BASE_ROS_A_GODOT
	return c * ros * c.inverse()


func _montar_camara_hud() -> void:
	var ambiente := WorldEnvironment.new()
	ambiente.environment = Environment.new()
	ambiente.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ambiente.environment.ambient_light_color = Color(0.58, 0.62, 0.68)
	ambiente.environment.ambient_light_energy = 0.8
	add_child(ambiente)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(35.0), 0.0)
	luz.shadow_enabled = false
	add_child(luz)
	camara = Camera3D.new()
	camara.current = true
	camara.far = 80.0
	add_child(camara)
	var capa := CanvasLayer.new()
	hud = Label.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 4)
	capa.add_child(hud)
	add_child(capa)


func _process(dt: float) -> void:
	_tiempo += dt
	if demo and ros_listo:
		var fase := fmod(_tiempo, 16.0)
		if robot.has_method("fijar_orden"):
			if fase < 6.0: robot.fijar_orden(Vector3(0.5, 0.0, 0.0))
			elif fase < 10.0: robot.fijar_orden(Vector3(0.0, 0.0, 0.5))
			elif fase < 13.0: robot.fijar_orden(Vector3(0.0, 0.4, 0.0))
			else: robot.fijar_orden(Vector3(-0.3, 0.0, 0.0))
	_mover_camara(dt)
	_actualizar_hud(dt)
	_fotogramas += 1
	if captura != "" and _fotogramas >= fotograma_captura:
		get_viewport().get_texture().get_image().save_png(captura)
		get_tree().quit()


func _mover_camara(dt: float) -> void:
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rx) > 0.15: _yaw_cam -= rx * 2.0 * dt
	if absf(ry) > 0.15: _pitch_cam = clampf(_pitch_cam + ry * 1.5 * dt, 0.1, 1.45)
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP): _distancia_cam = maxf(2.0, _distancia_cam - 5.0 * dt)
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN): _distancia_cam = minf(25.0, _distancia_cam + 5.0 * dt)
	var objetivo := robot.global_position + Vector3(0.0, config.get("altura_objetivo", 0.8), 0.0)
	if _cenital:
		camara.look_at_from_position(Vector3(0.0, 45.0, 0.01), Vector3.ZERO, Vector3.FORWARD)
		return
	var y := robot.rotation.y + _yaw_cam
	var dir := Vector3(sin(y) * cos(_pitch_cam), sin(_pitch_cam), cos(y) * cos(_pitch_cam))
	camara.look_at_from_position(objetivo + dir * _distancia_cam, objetivo)


func _actualizar_hud(dt: float) -> void:
	_hud_t += dt
	if _hud_t < 0.1:
		return
	_hud_t = 0.0
	var activos := 0
	for sensor in sensores.values():
		if sensor.get("habilitado") == true:
			activos += 1
	var estado := "sin ROS" if sin_ros else ("conectado" if ros_listo else "conectando…")
	if ros_error != "": estado = ros_error
	var p: Vector3 = robot.posicion_ros()
	hud.text = "%s · ROS %s\nSensores %d/%d · pose (%.1f, %.1f, %.1f)\nFPS %d · ○/C cenital · R reinicia" % [
		config.get("titulo", "Robot ROS 2"), estado, activos, sensores.size(), p.x, p.y, p.z, Engine.get_frames_per_second()]


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_C: _cenital = not _cenital
		elif ev.keycode == KEY_R:
			var spawn: Array = config.spawn_ros
			robot.global_position = Util.vector_godot(Vector3(spawn[0], spawn[1], spawn[2]))
			robot.rotation.y = spawn[3]
			robot.reiniciar_estado()   # R2-B5
	if ev is InputEventJoypadButton and ev.pressed:
		if ev.button_index == JOY_BUTTON_B: _cenital = not _cenital
		elif ev.button_index == JOY_BUTTON_Y:
			var spawn: Array = config.spawn_ros
			robot.global_position = Util.vector_godot(Vector3(spawn[0], spawn[1], spawn[2]))
			robot.rotation.y = spawn[3]
			robot.reiniciar_estado()   # R2-B5
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT: _arrastrando = ev.pressed
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP: _distancia_cam = maxf(2.0, _distancia_cam - 0.5)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: _distancia_cam = minf(25.0, _distancia_cam + 0.5)
	elif ev is InputEventMouseMotion and _arrastrando:
		_yaw_cam -= ev.relative.x * 0.01
		_pitch_cam = clampf(_pitch_cam + ev.relative.y * 0.01, 0.1, 1.45)


func _exit_tree() -> void:
	if robot != null:
		robot.contexto.cerrar()
