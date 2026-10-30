extends Node2D
## Puerta G6 (docs/18 §8) — HMI piloto: teleop de un robot desde la Vita con ros2_vita (XRCE).
##  - Publica geometry_msgs/Twist en /cmd_vel a 20 Hz con el mapeo de docs/09 (Objetivo 2):
##      stick izq. ↑↓ = linear.x · stick izq. ←→ = angular.z (← positivo, REP-103) · cruceta ↑↓ = linear.x
##      (prioridad sobre el stick) · L/R = giro fijo ±0.5 rad/s · △/✕ = escala de velocidad ±0.5 (✕ hasta 0 = stop)
##      · ○ = borrar el rastro. (Sin movimiento lateral: los robots de prueba son diferenciales.)
##  - Se suscribe a nav_msgs/Odometry en /odom y dibuja una vista cenital centrada en el robot: rejilla de
##    1 m, el robot como flecha, su rastro y un panel con velocidad, pose y frecuencia de /odom.
## Probar contra la estación: docker/vita-ros.sh sim (turtlesim + /odom) o sim-tb3 (TurtleBot3/Gazebo).
## En el host, `-- demo` hace que publique un círculo sin mandos (prueba automática).
## Probado en host contra turtlesim; en la Vita: validar en hardware.

const ESCALA := 80.0                      # píxeles por metro
const CENTRO := Vector2(480, 330)         # el robot se dibuja aquí (la vista lo sigue)
const VEL_INICIAL := 0.5
const VEL_PASO := 0.5
const VEL_MAX := 2.0
const GIRO_LR := 0.5                      # rad/s de L/R (docs/09)
const ZONA_MUERTA := 0.12                 # fracción del recorrido del stick (≈ ±30 de 255 en docs/09)
const RASTRO_MAX := 600

@onready var hud: Label = $Hud

var node: RosNode
var pub_cmd: RosPublisher
var sub_odom: RosSubscriber   # guardar las referencias: si se sueltan, se cancelan (RefCounted)
var t_cmd: RosTimer

var conectado := false
var error_txt := ""
var demo := false
var vel := VEL_INICIAL
var cmd_lin := 0.0
var cmd_ang := 0.0

var tiene_odom := false
var pose := Vector2.ZERO                  # metros, marco odom (x adelante, y izquierda)
var yaw := 0.0
var odom_v := 0.0
var odom_w := 0.0
var odom_total := 0
var odom_seg := 0                         # mensajes en el segundo actual
var odom_hz := 0
var t_hz := 0.0
var rastro := PackedVector2Array()


func _ready() -> void:
	demo = "demo" in OS.get_cmdline_user_args()
	hud.text = "Conectando con el agente %s..." % ProjectSettings.get_setting("ros/agent_ip", "?")
	await get_tree().process_frame   # pintar el texto antes de bloquear en la conexión
	var args := PackedStringArray(["-p", "transport:=xrce"])
	for a in OS.get_cmdline_user_args():
		if a != "demo":
			args.append(a)
	var err := rclgd.init(args)
	if err != OK:
		var d: Dictionary = rclgd.get_transport_info()
		error_txt = "Sin conexión con el agente (%s): %s\npaso: %s · WiFi netctl=%s" % [
				d.get("agent", "?"), error_string(err), d.get("step", "?"), d.get("netctl_state", "?")]
		queue_redraw()
		return
	node = RosNode.new()
	node.init("vita_hmi", "")
	pub_cmd = node.create_publisher("/cmd_vel", "geometry_msgs/msg/Twist")
	sub_odom = node.create_subscription("/odom", "nav_msgs/msg/Odometry", _on_odom)
	if pub_cmd == null or sub_odom == null:
		error_txt = "El agente rechazó /cmd_vel o /odom"
		queue_redraw()
		return
	t_cmd = node.create_timer(0.05, _publicar_cmd)   # 20 Hz, lo que espera un robot real
	conectado = true


# --- mandos -> Twist (docs/09) ------------------------------------------------------------------
func _eje(axis: JoyAxis) -> float:
	# Zona muerta reescalada: el borde de la zona vale 0 y el extremo ±1 (sin salto), como teleop.c.
	var v := Input.get_joy_axis(0, axis)
	if absf(v) < ZONA_MUERTA:
		return 0.0
	return signf(v) * (absf(v) - ZONA_MUERTA) / (1.0 - ZONA_MUERTA)


func _publicar_cmd() -> void:
	var lin := -_eje(JOY_AXIS_LEFT_Y) * vel     # stick arriba = eje negativo = adelante
	var ang := -_eje(JOY_AXIS_LEFT_X) * vel     # stick a la izquierda = giro positivo
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP):
		lin = vel
	elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN):
		lin = -vel
	var l := Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)
	var r := Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)
	if l or r:
		ang = (GIRO_LR if l else 0.0) - (GIRO_LR if r else 0.0)   # L+R = 0
	if demo:
		lin = 0.5
		ang = 0.6
	cmd_lin = lin + 0.0   # +0.0 evita publicar -0.0
	cmd_ang = ang + 0.0
	var m := RosMsg.from_type("geometry_msgs/msg/Twist")
	m.linear.x = cmd_lin
	m.angular.z = cmd_ang
	pub_cmd.publish(m)


func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton and event.pressed):
		return
	match event.button_index:
		JOY_BUTTON_Y:   # triángulo
			vel = minf(vel + VEL_PASO, VEL_MAX)
		JOY_BUTTON_A:   # cruz (hasta 0 = stop)
			vel = maxf(vel - VEL_PASO, 0.0)
		JOY_BUTTON_B:   # círculo
			rastro.clear()


# --- /odom ------------------------------------------------------------------------------------
func _on_odom(m: RosMsg) -> void:
	var p = m.pose.pose.position
	var q = m.pose.pose.orientation
	pose = Vector2(p.x, p.y)
	yaw = atan2(2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z))
	odom_v = m.twist.twist.linear.x
	odom_w = m.twist.twist.angular.z
	odom_total += 1
	odom_seg += 1
	tiene_odom = true
	if rastro.is_empty() or rastro[rastro.size() - 1].distance_to(pose) > 0.02:
		rastro.append(pose)
		if rastro.size() > RASTRO_MAX:
			rastro.remove_at(0)


func _process(delta: float) -> void:
	t_hz += delta
	if t_hz >= 1.0:
		odom_hz = odom_seg
		odom_seg = 0
		t_hz -= 1.0
	if not error_txt.is_empty():
		hud.text = error_txt
	elif conectado:
		var estado := "odom %d Hz (%d)" % [odom_hz, odom_total] if tiene_odom else "esperando /odom (¿docker/vita-ros.sh sim?)"
		hud.text = ("ROS 2 conectado · %s%s\n" % [estado, " · DEMO" if demo else ""] +
				"velocidad (Triangulo/Cruz): %.1f%s\n" % [vel, "  STOP" if vel == 0.0 else ""] +
				"/cmd_vel  lineal %+.2f m/s  giro %+.2f rad/s\n" % [cmd_lin, cmd_ang] +
				"pose  x %+.2f  y %+.2f  yaw %+.0f°  ·  v %+.2f  w %+.2f" % [pose.x, pose.y, rad_to_deg(yaw), odom_v, odom_w])
	queue_redraw()


# --- vista cenital (x a la derecha, y hacia arriba, centrada en el robot) -----------------------
func _a_pantalla(p: Vector2) -> Vector2:
	var d := p - pose
	return CENTRO + Vector2(d.x, -d.y) * ESCALA


func _draw() -> void:
	draw_rect(Rect2(0, 0, 960, 544), Color(0.6, 0.1, 0.1) if not error_txt.is_empty() else Color(0.08, 0.09, 0.12))
	if not conectado:
		return
	# Rejilla de 1 m alineada con el marco odom (se desplaza al moverse el robot).
	var gris := Color(0.22, 0.24, 0.3)
	var x0 := floori(pose.x - CENTRO.x / ESCALA) - 1
	var x1 := ceili(pose.x + (960.0 - CENTRO.x) / ESCALA) + 1
	var y0 := floori(pose.y - (544.0 - CENTRO.y) / ESCALA) - 1
	var y1 := ceili(pose.y + CENTRO.y / ESCALA) + 1
	for gx in range(x0, x1 + 1):
		var a := _a_pantalla(Vector2(gx, y0))
		draw_line(Vector2(a.x, 0), Vector2(a.x, 544), Color(0.35, 0.3, 0.3) if gx == 0 else gris, 1.0)
	for gy in range(y0, y1 + 1):
		var b := _a_pantalla(Vector2(x0, gy))
		draw_line(Vector2(0, b.y), Vector2(960, b.y), Color(0.3, 0.35, 0.3) if gy == 0 else gris, 1.0)
	# Rastro
	for i in range(1, rastro.size()):
		draw_line(_a_pantalla(rastro[i - 1]), _a_pantalla(rastro[i]), Color(0.3, 0.7, 1.0), 2.0)
	# Robot: flecha en la dirección de yaw (en pantalla, y va hacia abajo)
	var dir := Vector2(cos(yaw), -sin(yaw))
	var lado := Vector2(-dir.y, dir.x)
	var punta := CENTRO + dir * 22.0
	var robot := PackedVector2Array([punta, CENTRO - dir * 12.0 + lado * 13.0, CENTRO - dir * 6.0, CENTRO - dir * 12.0 - lado * 13.0])
	draw_colored_polygon(robot, Color(1.0, 0.75, 0.2) if tiene_odom else Color(0.5, 0.5, 0.5))
	# Comando actual: línea verde desde el robot (longitud = velocidad lineal)
	if absf(cmd_lin) > 0.01:
		draw_line(CENTRO, CENTRO + dir * cmd_lin * ESCALA, Color(0.3, 1.0, 0.4), 3.0)
