extends Control
## Puerta G7 (docs/18 §8) — primer SENSOR de la Vita publicado en ROS 2: la IMU.
##
## Qué hace:
##   - Lee el acelerómetro y el giroscopio de la Vita con la API normal de Godot
##     (Input.get_accelerometer / get_gyroscope). El port godot4-vita los rellena en cada
##     fotograma con sceMotionGetState (toolchains/godot4-vita/engine/platform/vita/display_server_vita.cpp).
##   - Los publica como sensor_msgs/msg/Imu en /vita/imu (por defecto 30 Hz, QoS best effort,
##     que es lo normal para sensores en ROS 2).
##   - Muestra en pantalla los valores CRUDOS (tal cual llegan del sensor) y los ya convertidos
##     a ROS, y un nivel de burbuja con la gravedad (nivel.gd).
##
## Botones: Triángulo = tara del giroscopio (estando quieta, mide 1 s y resta ese sesgo)
##          Cruz      = pausar / reanudar la publicación
##
## Lección que explica este archivo línea a línea: docs/tutorial/08-godot-imu-primer-sensor.md
##
## ESTADO (2026-11-01): corre en la Vita. Unidades y ejes MEDIDOS en hardware (lección 08, retos 1–2):
## la Vita da g y rad/s con ejes de Sony (x derecha, y hacia los gatillos, z saliendo de la pantalla) y
## el acelerómetro mide la GRAVEDAD (z ≈ −1 g con la pantalla arriba). Ver escala_acel y ejes.

# --- Constantes -----------------------------------------------------------------------------------
# `const` = valor fijo que no cambia nunca. `:=` deja que GDScript deduzca el tipo (aquí float).
const G := 9.80665                        # 1 g en m/s² (valor estándar)

# REP-145 (convención de ROS para IMUs): si el sensor NO da orientación, se pone -1 en el primer
# elemento de orientation_covariance. Quien lea /vita/imu sabrá que debe ignorar `orientation`.
# Las otras dos matrices en ceros significan «covarianza desconocida».
const SIN_ORIENTACION := [-1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

const TARA_SEGUNDOS := 1.0

# --- Referencias a nodos de la escena (main.tscn) -------------------------------------------------
# @onready = «rellena esta variable cuando el nodo esté listo». $Estado es un atajo de
# get_node("Estado"): busca el hijo llamado Estado en el árbol de escena.
@onready var lbl_estado: Label = $Estado
@onready var lbl_datos: Label = $Datos
# preload carga el script nivel.gd al compilar; usarlo como tipo (Nivel) le dice a GDScript que ese
# nodo tiene la propiedad `gravedad`. Con el tipo genérico Control daría error al escribirla.
const Nivel := preload("res://nivel.gd")
@onready var nivel: Nivel = $Nivel

# --- Objetos ROS --------------------------------------------------------------------------------
# Todos los objetos Ros* son RefCounted: Godot los borra cuando nadie los referencia. Por eso se
# guardan en variables del script; si fueran variables locales de _ready(), el publicador y el timer
# desaparecerían al terminar la función y no se publicaría nada.
var node: RosNode
var pub_imu: RosPublisher
var t_pub: RosTimer

# --- Parámetros (se pueden cambiar sin recompilar: `-- -p hz:=50`) -----------------------------
var hz := 30.0
var topic := "/vita/imu"
var frame_id := "vita_imu"
# Medido en la Vita el 2026-11-01:
var escala_acel := -G         # da g; el − pasa de gravedad a REACCIÓN (+9,8 hacia arriba, REP-145)
var escala_giro := 1.0        # ya da rad/s
var ejes: Array = [[1, 1.0], [0, -1.0], [2, 1.0]]  # = "y,-x,z": ejes de Sony → REP-103 (ver _parsear_ejes)

# --- Estado ---------------------------------------------------------------------------------------
var conectado := false
var error_txt := ""
var demo := false
var pausado := false
var t_demo := 0.0

var acel_crudo := Vector3.ZERO     # tal cual lo da Input (unidades del sensor)
var giro_crudo := Vector3.ZERO
var grav_cruda := Vector3.ZERO
var acel_ros := Vector3.ZERO       # ya en m/s² y ejes ROS
var giro_ros := Vector3.ZERO       # ya en rad/s, ejes ROS y sin sesgo

var sesgo_giro := Vector3.ZERO     # lo que mide el giroscopio estando quieto (se resta)
var tara_restante := 0.0           # > 0 mientras se está midiendo la tara
var tara_suma := Vector3.ZERO
var tara_n := 0

var enviados := 0
var enviados_seg := 0
var hz_real := 0
var t_hz := 0.0


# _ready() se llama UNA vez, cuando el nodo y todos sus hijos ya están en el árbol.
func _ready() -> void:
	demo = "demo" in OS.get_cmdline_user_args()
	lbl_estado.text = "Conectando con el agente %s..." % ProjectSettings.get_setting("ros/agent_ip", "?")
	# `await` pausa esta función hasta que ocurra la señal; aquí, hasta el siguiente fotograma.
	# Así se ve el texto «Conectando...» antes de que rclgd.init() bloquee un momento.
	await get_tree().process_frame

	# 1) Arrancar ROS. En la Vita esto abre la sesión XRCE con el agente micro-ROS (UDP 8888).
	var args := PackedStringArray(["-p", "transport:=xrce"])
	for a in OS.get_cmdline_user_args():
		if a != "demo":
			args.append(a)
	var err := rclgd.init(args)
	if err != OK:
		var d: Dictionary = rclgd.get_transport_info()
		error_txt = "Sin conexión con el agente (%s): %s\npaso: %s · WiFi netctl=%s" % [
				d.get("agent", "?"), error_string(err), d.get("step", "?"), d.get("netctl_state", "?")]
		return

	# 2) Crear el nodo ROS y leer sus parámetros. declare_parameter(nombre, valor_por_defecto)
	#    devuelve el valor de la línea de órdenes si se pasó `-p nombre:=valor`.
	node = RosNode.new()
	node.init("vita_imu", "")
	node.declare_parameter("hz", hz)
	node.declare_parameter("topic", topic)
	node.declare_parameter("frame_id", frame_id)
	node.declare_parameter("escala_acel", escala_acel)
	node.declare_parameter("escala_giro", escala_giro)
	node.declare_parameter("ejes", "y,-x,z")
	hz = node.get_parameter("hz")
	topic = node.get_parameter("topic")
	frame_id = node.get_parameter("frame_id")
	escala_acel = node.get_parameter("escala_acel")
	escala_giro = node.get_parameter("escala_giro")
	var ejes_nuevos := _parsear_ejes(node.get_parameter("ejes"))
	if ejes_nuevos.is_empty():
		error_txt = "Parámetro 'ejes' inválido: %s (ejemplo válido: -y,x,z)" % node.get_parameter("ejes")
		return
	ejes = ejes_nuevos

	# 3) Publicador con QoS de sensor: BEST_EFFORT = si un mensaje se pierde, no se reenvía
	#    (para un sensor vale más el dato nuevo que el viejo). Un Imu ocupa ~320 bytes, cabe en
	#    un datagrama de 512 (en best effort ros2_vita no trocea mensajes).
	var qos := RosQoS.new()
	qos.set_reliability(RosQoS.BEST_EFFORT)
	qos.set_depth(5)
	pub_imu = node.create_publisher(topic, "sensor_msgs/msg/Imu", qos)
	if pub_imu == null:
		error_txt = "El agente rechazó %s" % topic
		return

	# 4) Timer de ROS: llama a _publicar cada 1/hz segundos, en el hilo principal.
	t_pub = node.create_timer(1.0 / hz, _publicar)
	conectado = true


# --- Ejes -----------------------------------------------------------------------------------------
## Convierte un texto como "-y,x,z" en una lista de 3 pares [índice, signo].
## Posición i del texto = eje ROS i (x adelante, y izquierda, z arriba, REP-103).
## Cada entrada dice de qué eje del SENSOR sale, y con qué signo.
## Ejemplo: "-y,x,z" ⇒ ros.x = -sensor.y, ros.y = sensor.x, ros.z = sensor.z.
## Devuelve [] si el texto no es válido.
func _parsear_ejes(spec: String) -> Array:
	var out := []
	for parte: String in spec.split(","):   # `parte: String` = el bucle declara el tipo
		var p := parte.strip_edges()
		var signo := -1.0 if p.begins_with("-") else 1.0
		var nombre := p.trim_prefix("-").trim_prefix("+")
		if nombre.length() != 1 or not (nombre in ["x", "y", "z"]):
			return []
		out.append(["xyz".find(nombre), signo])
	return out if out.size() == 3 else []


## Aplica la reordenación de ejes. Un Vector3 se puede indexar: v[0] = v.x, v[1] = v.y, v[2] = v.z.
func _a_ros(v: Vector3) -> Vector3:
	return Vector3(
			v[ejes[0][0]] * ejes[0][1],
			v[ejes[1][0]] * ejes[1][1],
			v[ejes[2][0]] * ejes[2][1])


# --- Lectura del sensor (cada fotograma) -----------------------------------------------------------
# _process(delta) se llama en CADA fotograma; delta = segundos desde el anterior (≈0.016 a 60 fps).
func _process(delta: float) -> void:
	if demo:
		# Sin sensores (PC): señal inventada — la consola cabecea despacio (el morro sube y baja).
		# Se inventa COMO LA DARÍA LA VITA (ejes de Sony, gravedad, g y rad/s), para que el demo
		# pase por la misma conversión escala_acel + ejes que los datos reales.
		# Objetivo en ROS: acel = G·(sin i, 0, cos i) y giro = (0, −di/dt, 0)  (morro arriba ⇒ pitch = −i).
		# Invirtiendo ROS = −G·(s.y, −s.x, s.z):  s = (0, −sin i, −cos i).
		# Invirtiendo ROS = (g.y, −g.x, g.z):      g = (di/dt, 0, 0), con di/dt = 0,5·cos(t).
		t_demo += delta
		var inclinacion := sin(t_demo) * 0.5                       # radianes
		acel_crudo = Vector3(0.0, -sin(inclinacion), -cos(inclinacion))   # en g, ejes de Sony
		giro_crudo = Vector3(cos(t_demo) * 0.5, 0.0, 0.0)                 # rad/s, ejes de Sony
		grav_cruda = acel_crudo
	else:
		acel_crudo = Input.get_accelerometer()
		giro_crudo = Input.get_gyroscope()
		grav_cruda = Input.get_gravity()

	# Tara del giroscopio: acumular muestras durante TARA_SEGUNDOS y luego promediar.
	if tara_restante > 0.0:
		tara_suma += giro_crudo
		tara_n += 1
		tara_restante -= delta
		if tara_restante <= 0.0 and tara_n > 0:
			sesgo_giro = tara_suma / tara_n

	acel_ros = _a_ros(acel_crudo * escala_acel)
	giro_ros = _a_ros((giro_crudo - sesgo_giro) * escala_giro)
	nivel.gravedad = grav_cruda      # nivel.gd redibuja solo (setter)

	_contar_hz(delta)
	_pintar_hud()


# --- Publicación (la llama el RosTimer) ------------------------------------------------------------
func _publicar() -> void:
	if pausado:
		return
	# RosMsg.from_type crea un mensaje vacío del tipo pedido, usando el esquema ros/schema.rsch.
	var m := RosMsg.from_type("sensor_msgs/msg/Imu")
	m.header.stamp = node.now()      # hora del reloj de la Vita (no está sincronizado con el PC)
	m.header.frame_id = frame_id
	m.orientation_covariance = PackedFloat64Array(SIN_ORIENTACION)
	m.linear_acceleration.x = acel_ros.x
	m.linear_acceleration.y = acel_ros.y
	m.linear_acceleration.z = acel_ros.z
	m.angular_velocity.x = giro_ros.x
	m.angular_velocity.y = giro_ros.y
	m.angular_velocity.z = giro_ros.z
	pub_imu.publish(m)
	enviados += 1
	enviados_seg += 1


# --- Mandos ---------------------------------------------------------------------------------------
# _input recibe cada evento (botón pulsado/soltado, toque, etc.).
func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton and event.pressed):
		return
	match event.button_index:
		JOY_BUTTON_Y:   # Triángulo
			tara_restante = TARA_SEGUNDOS
			tara_suma = Vector3.ZERO
			tara_n = 0
		JOY_BUTTON_A:   # Cruz
			pausado = not pausado


# --- Pantalla -------------------------------------------------------------------------------------
func _contar_hz(delta: float) -> void:
	t_hz += delta
	if t_hz >= 1.0:
		hz_real = enviados_seg
		enviados_seg = 0
		t_hz -= 1.0


func _pintar_hud() -> void:
	if not error_txt.is_empty():
		lbl_estado.text = error_txt
		lbl_estado.modulate = Color(1.0, 0.4, 0.4)
		return
	if not conectado:
		return
	var estado := "PAUSADO (Cruz)" if pausado else "%s a %d Hz (%d enviados)" % [topic, hz_real, enviados]
	if tara_restante > 0.0:
		estado += " · TARA: no muevas la consola"
	lbl_estado.text = "ROS 2 conectado · %s%s" % [estado, " · DEMO" if demo else ""]
	lbl_datos.text = (
			"CRUDO (unidades del sensor)\n" +
			"  acel  %+.3f  %+.3f  %+.3f   |a| = %.3f\n" % [acel_crudo.x, acel_crudo.y, acel_crudo.z, acel_crudo.length()] +
			"  giro  %+.3f  %+.3f  %+.3f\n" % [giro_crudo.x, giro_crudo.y, giro_crudo.z] +
			"  grav  %+.3f  %+.3f  %+.3f\n\n" % [grav_cruda.x, grav_cruda.y, grav_cruda.z] +
			"ROS (/vita/imu, frame %s)\n" % frame_id +
			"  linear_acceleration  %+.2f  %+.2f  %+.2f m/s²\n" % [acel_ros.x, acel_ros.y, acel_ros.z] +
			"  angular_velocity     %+.3f  %+.3f  %+.3f rad/s\n\n" % [giro_ros.x, giro_ros.y, giro_ros.z] +
			"sesgo del giro  %+.4f  %+.4f  %+.4f\n" % [sesgo_giro.x, sesgo_giro.y, sesgo_giro.z] +
			"escala acel %.3f · escala giro %.3f" % [escala_acel, escala_giro])
