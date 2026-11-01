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
##     a ROS, un nivel (nivel.gd) y — G7c — un modelo 3D de la Vita que gira con la propia IMU
##     (filtro.gd, sin pasar por ROS).
##
## Botones: Triángulo = tara del giroscopio (estando quieta, mide 1 s y resta ese sesgo)
##          Cruz      = pausar / reanudar la publicación
##          Círculo   = reiniciar la orientación del modelo 3D
##
## Lección que explica este archivo línea a línea: docs/tutorial/08-godot-imu-primer-sensor.md
##
## ESTADO (2026-11-01): corre en la Vita. Unidades y ejes MEDIDOS en hardware (lección 08, retos 1–2):
## la Vita da g y rad/s con ejes de Sony (x derecha, y hacia los gatillos, z saliendo de la pantalla) y
## el acelerómetro mide la GRAVEDAD (z ≈ −1 g con la pantalla arriba). Ver escala_acel y ejes.
## G7c (2026-11-01): optimizaciones O1–O4 (guion docs/ia/guion-g7c-3d-en-la-vita.md) y modelo 3D.
## El 3D de Godot en la Vita es EXPERIMENTAL: validar en hardware los FPS (se muestran en el HUD).

# --- Constantes -----------------------------------------------------------------------------------
# `const` = valor fijo que no cambia nunca. `:=` deja que GDScript deduzca el tipo (aquí float).
const G := 9.80665                        # 1 g en m/s² (valor estándar)

# REP-145 (convención de ROS para IMUs): si el sensor NO da orientación, se pone -1 en el primer
# elemento de orientation_covariance. Quien lea /vita/imu sabrá que debe ignorar `orientation`.
# Las otras dos matrices en ceros significan «covarianza desconocida».
const SIN_ORIENTACION := [-1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

const TARA_SEGUNDOS := 1.0
const HUD_PERIODO := 0.1          # O1: el texto del HUD se rehace 10 veces por segundo, no 60
const NIVEL_TAU := 0.15           # O4: constante de tiempo (s) del suavizado del nivel

# Cambio de ejes ROS → Godot (el mismo que g7b-imu3d/main.gd): columnas = adónde va cada eje ROS.
#   ROS x (adelante) → Godot (0,0,−1) · ROS y (izquierda) → Godot (−1,0,0) · ROS z (arriba) → Godot (0,1,0)
const ROS_A_GODOT := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))
const Filtro := preload("res://filtro.gd")

# --- Referencias a nodos de la escena (main.tscn) -------------------------------------------------
# @onready = «rellena esta variable cuando el nodo esté listo». $Estado es un atajo de
# get_node("Estado"): busca el hijo llamado Estado en el árbol de escena.
@onready var lbl_estado: Label = $Estado
@onready var lbl_datos: Label = $Datos
# preload carga el script nivel.gd al compilar; usarlo como tipo (Nivel) le dice a GDScript que ese
# nodo tiene la propiedad `gravedad`. Con el tipo genérico Control daría error al escribirla.
const Nivel := preload("res://nivel.gd")
@onready var nivel: Nivel = $Nivel
# 3D: la escena va en la pantalla principal (la Vita no dibuja 3D en SubViewport, ver marco_3d.gd);
# Marco3D es solo la guía de dónde y de qué tamaño se ve el modelo.
@onready var vita3d: Node3D = $Escena/Vita
@onready var camara: Camera3D = $Escena/Camara
@onready var marco: Control = $Marco3D
const MODELO_ALTO := 2.4          # unidades del mundo que deben caber en el alto del Marco3D

# --- Objetos ROS --------------------------------------------------------------------------------
# Todos los objetos Ros* son RefCounted: Godot los borra cuando nadie los referencia. Por eso se
# guardan en variables del script; si fueran variables locales de _ready(), el publicador y el timer
# desaparecerían al terminar la función y no se publicaría nada.
var node: RosNode
var pub_imu: RosPublisher
var t_pub: RosTimer
var msg_imu: RosMsg               # O3: UN solo mensaje, creado en _ready y reutilizado

# --- Parámetros (se pueden cambiar sin recompilar: `-- -p hz:=50`) -----------------------------
var hz := 30.0
var topic := "/vita/imu"
var frame_id := "vita_imu"
# Medido en la Vita el 2026-11-01:
var escala_acel := -G         # da g; el − pasa de gravedad a REACCIÓN (+9,8 hacia arriba, REP-145)
var escala_giro := 1.0        # ya da rad/s
# O2: la reordenación de ejes es una MATRIZ (Basis): convertir = una multiplicación, `ejes * v`.
# Columnas = adónde va en ROS cada eje del sensor. Esta es "y,-x,z" (ver _parsear_ejes).
var ejes := Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1))

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

var nivel_suave := Vector3.ZERO   # O4: aceleración ROS suavizada para el nivel
var filtro := Filtro.new()

var sesgo_giro := Vector3.ZERO     # lo que mide el giroscopio estando quieto (se resta)
var tara_restante := 0.0           # > 0 mientras se está midiendo la tara
var tara_suma := Vector3.ZERO
var tara_n := 0

var enviados := 0
var enviados_seg := 0
var hz_real := 0
var t_hz := 0.0
var t_hud := 0.0


# _ready() se llama UNA vez, cuando el nodo y todos sus hijos ya están en el árbol.
func _ready() -> void:
	_encuadrar_3d()
	marco.item_rect_changed.connect(_encuadrar_3d)   # si el marco cambia, se recoloca la cámara
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
	ejes = _ejes_a_basis(ejes_nuevos)

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

	# O3: el mensaje se crea UNA vez. Lo que no cambia (frame_id, covarianza) se rellena aquí;
	#     _publicar solo toca el sello y 6 números. Es seguro reutilizarlo porque publish()
	#     serializa el mensaje en el momento (godot/ros2_vita/ros_runtime.cpp:106).
	msg_imu = RosMsg.from_type("sensor_msgs/msg/Imu")
	msg_imu.header.frame_id = frame_id
	msg_imu.orientation_covariance = PackedFloat64Array(SIN_ORIENTACION)

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


## Coloca la cámara ortográfica para que el origen (el modelo) caiga en el centro de Marco3D y
## MODELO_ALTO unidades ocupen su alto. En ortográfica, `size` = unidades visibles en el alto de la
## pantalla ⇒ unidades por píxel = size / alto_pantalla.
##   h_offset > 0 mueve la cámara a la derecha ⇒ la escena se ve más a la IZQUIERDA (por eso el −).
##   v_offset > 0 mueve la cámara arriba     ⇒ la escena se ve más ABAJO.
func _encuadrar_3d() -> void:
	var pantalla := get_viewport_rect().size
	var r := marco.get_global_rect()
	if r.size.y < 1.0:
		return
	var alto := minf(r.size.x, r.size.y)     # el modelo cabe entero aunque el marco no sea cuadrado
	camara.size = MODELO_ALTO * pantalla.y / alto
	var upp := camara.size / pantalla.y
	var c := r.get_center()
	camara.h_offset = -(c.x - pantalla.x / 2.0) * upp
	camara.v_offset = (c.y - pantalla.y / 2.0) * upp


## O2: convierte la lista de _parsear_ejes en una Basis (una sola vez, al arrancar).
## Par i = [índice del sensor, signo] para el eje ROS i ⇒ la columna `índice` lleva `signo` en la fila i.
## Ejemplo "y,-x,z": columnas (0,−1,0), (1,0,0), (0,0,1) ⇒ ejes * v = (v.y, −v.x, v.z).
func _ejes_a_basis(pares: Array) -> Basis:
	var cols: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for i in 3:
		cols[pares[i][0]][i] = pares[i][1]
	return Basis(cols[0], cols[1], cols[2])


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

	acel_ros = ejes * (acel_crudo * escala_acel)                 # O2: una multiplicación
	giro_ros = ejes * ((giro_crudo - sesgo_giro) * escala_giro)

	# O4: el nivel recibe la aceleración ROS suavizada (paso bajo). 1 − exp(−dt/τ) hace que el
	# suavizado sea igual a 30 o a 60 fps. El setter de nivel.gd solo redibuja si cambia.
	nivel_suave = nivel_suave.lerp(acel_ros, 1.0 - exp(-delta / NIVEL_TAU))
	nivel.gravedad = nivel_suave

	# G7c: orientación con el filtro (reto) → girar el modelo 3D. La misma rotación, vista con los
	# ejes de Godot: cambio de base ROS_A_GODOT · R · ROS_A_GODOTᵀ (como en g7b-imu3d).
	filtro.actualizar(acel_ros, giro_ros, delta)
	vita3d.basis = ROS_A_GODOT * filtro.orientacion * ROS_A_GODOT.transposed()

	_contar_hz(delta)
	t_hud += delta                   # O1: el HUD solo se rehace cada HUD_PERIODO
	if t_hud >= HUD_PERIODO:
		t_hud = 0.0
		_pintar_hud()


# --- Publicación (la llama el RosTimer) ------------------------------------------------------------
func _publicar() -> void:
	if pausado:
		return
	var m := msg_imu                 # O3: el mismo mensaje de siempre (creado en _ready)
	m.header.stamp = node.now()      # hora del reloj de la Vita (no está sincronizado con el PC)
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
		JOY_BUTTON_B:   # Círculo
			filtro.reiniciar()


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
			"escala acel %.3f · escala giro %.3f\n" % [escala_acel, escala_giro] +
			"FPS %d" % Engine.get_frames_per_second())
