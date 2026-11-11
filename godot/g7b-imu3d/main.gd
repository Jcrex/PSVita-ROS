extends Node3D
## G7b — visor 3D de la IMU: un modelo de la Vita que gira como la consola real.
##
## Qué hace:
##   - Se SUSCRIBE a /vita/imu (sensor_msgs/msg/Imu), que publica g7-imu desde la Vita.
##   - Pasa cada mensaje al filtro complementario (filtro.gd, reto del usuario), que calcula
##     roll / pitch / yaw.
##   - Gira el nodo «Vita» (modelo 3D de la Vita + ejes de colores) con esa orientación, convertida de los
##     ejes de ROS a los de Godot.
##
## Corre en el PC con nuestro módulo ros2_vita (misma API que rclgd: RosNode.create_subscription)
## a través del agente micro-ROS de la estación (docker/vita-ros.sh up).
## Lección: docs/tutorial/09-godot-visor-3d-imu.md
##
## ESTADO (2026-11-01): probado con el demo de g7-imu en el PC y con la Vita real (tras calibrar los
## ejes de g7-imu). Modelo: assets/PSVita (EricWalker, CC-BY 3.0, ver CREDITOS.md); necesita Blender.

const Filtro := preload("res://filtro.gd")

# --- Cambio de ejes ROS → Godot -----------------------------------------------------------------
# ROS (REP-103): x adelante, y izquierda, z arriba.
# Godot:         x derecha,  y arriba,    -z adelante.
# Cada columna dice adónde va en Godot un eje de ROS:
#   ROS x (adelante)  → Godot (0, 0, -1)
#   ROS y (izquierda) → Godot (-1, 0, 0)
#   ROS z (arriba)    → Godot (0, 1, 0)
# Basis(a, b, c) construye la matriz con a, b, c como COLUMNAS.
const ROS_A_GODOT := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))

@onready var vita: Node3D = $Vita
@onready var camara: Camera3D = $Camara
@onready var luz: DirectionalLight3D = $Luz
@onready var lbl_estado: Label = $HUD/Estado
@onready var lbl_datos: Label = $HUD/Datos

# --- Objetos ROS (en variables del script: si fueran locales, Godot los borraría) --------------
var node: RosNode
var sub_imu: RosSubscriber

var topic := "/vita/imu"
var filtro := Filtro.new()

# --- Estado -------------------------------------------------------------------------------------
var conectado := false
var error_txt := ""
var acel := Vector3.ZERO
var giro := Vector3.ZERO
var t_anterior := -1.0      # sello de tiempo del mensaje anterior (s); -1 = aún no hay
var recibidos := 0
var recibidos_seg := 0
var hz_real := 0
var t_hz := 0.0


func _ready() -> void:
	# look_at_from_position(dónde, hacia dónde): coloca el nodo y lo orienta mirando a un punto.
	camara.look_at_from_position(Vector3(3.2, 2.0, 3.2), Vector3.ZERO)
	luz.look_at_from_position(Vector3(2.0, 4.0, 1.0), Vector3.ZERO)

	lbl_estado.text = "Conectando con el agente %s..." % ProjectSettings.get_setting("ros/agent_ip", "?")
	await get_tree().process_frame

	# 1) Arrancar ROS por XRCE. Los argumentos tras `--` se pasan tal cual (p. ej. -p agent_ip:=127.0.0.1).
	var args := PackedStringArray(["-p", "transport:=xrce"])
	args.append_array(OS.get_cmdline_user_args())
	var err := rclgd.init(args)
	if err != OK:
		error_txt = "Sin conexión con el agente (%s): %s" % [
				rclgd.get_transport_info().get("agent", "?"), error_string(err)]
		return

	# 2) Nodo y parámetro del topic.
	node = RosNode.new()
	node.init("visor_imu3d", "")
	node.declare_parameter("topic", topic)
	topic = node.get_parameter("topic")

	# 3) Suscriptor. La QoS DEBE ser BEST_EFFORT porque g7-imu publica en best effort:
	#    un suscriptor RELIABLE (el valor por defecto) no casa con un publicador BEST_EFFORT
	#    y no recibiría nada, sin dar ningún error.
	var qos := RosQoS.new()
	qos.set_reliability(RosQoS.BEST_EFFORT)
	qos.set_depth(5)
	sub_imu = node.create_subscription(topic, "sensor_msgs/msg/Imu", _on_imu, qos)
	if sub_imu == null:
		error_txt = "El agente rechazó la suscripción a %s" % topic
		return
	conectado = true


# --- Llega un mensaje (callback del suscriptor, en el hilo principal) ---------------------------
func _on_imu(m: RosMsg) -> void:
	acel = Vector3(m.linear_acceleration.x, m.linear_acceleration.y, m.linear_acceleration.z)
	giro = Vector3(m.angular_velocity.x, m.angular_velocity.y, m.angular_velocity.z)

	# dt con el reloj de la VITA (header.stamp), no con el del PC: así no le afectan los
	# retrasos de la WiFi. clamp() lo limita a 0..0,2 s por si se pierden mensajes o la
	# Vita se reinicia (el sello saltaría).
	var t: float = m.header.stamp.sec + m.header.stamp.nanosec * 1e-9
	var dt: float = 0.0 if t_anterior < 0.0 else clampf(t - t_anterior, 0.0, 0.2)
	t_anterior = t

	filtro.actualizar(acel, giro, dt)
	recibidos += 1
	recibidos_seg += 1


# --- Cada fotograma: girar el modelo y pintar el HUD ---------------------------------------------
func _process(delta: float) -> void:
	# Orientación en ROS: primero roll (x), luego pitch (y), luego yaw (z), aplicados en ejes
	# del cuerpo. Basis(eje, ángulo) = rotación de `ángulo` radianes sobre `eje`.
	var b_ros := (Basis(Vector3(0, 0, 1), filtro.yaw)
			* Basis(Vector3(0, 1, 0), filtro.pitch)
			* Basis(Vector3(1, 0, 0), filtro.roll))
	# Cambio de base: la misma rotación vista con los ejes de Godot.
	vita.basis = ROS_A_GODOT * b_ros * ROS_A_GODOT.transposed()

	t_hz += delta
	if t_hz >= 1.0:
		hz_real = recibidos_seg
		recibidos_seg = 0
		t_hz -= 1.0
	_pintar_hud()


func _unhandled_input(event: InputEvent) -> void:
	# `as` convierte al tipo concreto, o da null si el evento es de otro tipo.
	var tecla := event as InputEventKey
	var boton := event as InputEventJoypadButton
	if tecla and tecla.pressed and tecla.keycode == KEY_R:
		filtro.reiniciar()
	elif boton and boton.pressed and boton.button_index == JOY_BUTTON_Y:   # Triángulo
		filtro.reiniciar()


func _pintar_hud() -> void:
	if not error_txt.is_empty():
		lbl_estado.text = error_txt
		lbl_estado.modulate = Color(1.0, 0.4, 0.4)
		return
	if not conectado:
		return
	if recibidos == 0:
		lbl_estado.text = "Suscrito a %s · esperando mensajes (¿está g7-imu publicando?)" % topic
	else:
		lbl_estado.text = "ROS 2 conectado · %s a %d Hz (%d recibidos)" % [topic, hz_real, recibidos]
	lbl_datos.text = (
			"acel  %+.2f  %+.2f  %+.2f m/s²   |a| = %.2f\n" % [acel.x, acel.y, acel.z, acel.length()] +
			"giro  %+.3f  %+.3f  %+.3f rad/s\n\n" % [giro.x, giro.y, giro.z] +
			"roll  %+6.1f°\npitch %+6.1f°\nyaw   %+6.1f°" % [
				rad_to_deg(filtro.roll), rad_to_deg(filtro.pitch), rad_to_deg(filtro.yaw)])
