extends Control
# teleop.gd — UI del teleop Godot (docs/12). La lógica del mapeo vive en
# vita-app/src/teleop.c dentro del singleton nativo MicroROS; aquí solo se
# leen los mandos, se llama a teleop_step() a ~20 Hz y se pinta el estado.
# En la laptop (editor sin el módulo) corre MicroROSStub para probar la UI.

const PUB_PERIODO := 0.05        # ~20 Hz, la cadencia de la app nativa
const REINTENTO_PERIODO := 3.0   # backoff del reintento de conexión (docs/12)
const IP_DEFECTO := "192.168.1.108"   # la laptop (agente + netlog)
const CONFIG_PATH := "user://vitaros.cfg"

# Índices de botones según platform/vita/joypad_vita.cpp (pad_mapping):
const BTN_CROSS := 0
const BTN_TRIANGLE := 3
const BTN_L := 6      # gatillo L de la Vita
const BTN_R := 7      # gatillo R de la Vita
const BTN_START := 11
const BTN_UP := 12
const BTN_DOWN := 13
const BTN_LEFT := 14
const BTN_RIGHT := 15

var ros = null                   # singleton MicroROS (Vita) o stub (laptop)
var es_stub := false
var acumulado := 0.0
var auto_reintento := false      # tras un Conectar fallido, reintenta solo
var reintento_t := 0.0

onready var ip_agente: LineEdit = $VBox/FilaIP/IpAgente
onready var ip_netlog: LineEdit = $VBox/FilaIP/IpNetlog
onready var btn_conectar: Button = $VBox/FilaIP/BtnConectar
onready var lbl_estado: Label = $VBox/Estado
onready var lbl_twist: Label = $VBox/Twist
onready var lbl_escalas: Label = $VBox/Escalas
onready var consola: RichTextLabel = $VBox/Consola


# Stub de laptop: misma interfaz que el singleton nativo. El "mapeo" de
# aquí es SOLO un apaño visual para desarrollar la UI; el real es teleop.c.
class MicroROSStub:
	func setup(_agent_ip: String, _netlog_ip: String) -> bool:
		return true

	func connect_agent() -> bool:
		return true

	func is_session_active() -> bool:
		return true

	func teleop_step(entrada: Dictionary, _dt: float) -> Dictionary:
		return {
			"lin_x": -entrada.get("ly", 0.0) * 0.5,
			"lin_y": 0.0,
			"ang_z": -entrada.get("lx", 0.0) * 0.5,
			"vel_lineal": 0.5,
			"vel_lateral": 0.5,
			"published": false,
		}

	func spin(_ms: int) -> void:
		pass

	func netlog(msg: String) -> void:
		print("[stub-netlog] ", msg)

	func shutdown() -> void:
		pass


func _ready() -> void:
	if Engine.has_singleton("MicroROS"):
		ros = Engine.get_singleton("MicroROS")
	else:
		ros = MicroROSStub.new()
		es_stub = true
		log_linea("modo SIMULADO (sin modulo nativo): UI ok, no se publica")
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # si no existe, se quedan los defectos
	ip_agente.text = cfg.get_value("red", "agent_ip", IP_DEFECTO)
	ip_netlog.text = cfg.get_value("red", "netlog_ip", IP_DEFECTO)
	btn_conectar.connect("pressed", self, "_on_conectar")
	_pinta_estado()


func _on_conectar() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("red", "agent_ip", ip_agente.text)
	cfg.set_value("red", "netlog_ip", ip_netlog.text)
	cfg.save(CONFIG_PATH)
	if not ros.setup(ip_agente.text, ip_netlog.text):
		log_linea("setup() fallo: IP invalida o red no disponible")
		_pinta_estado()
		return
	log_linea("conectando al agente %s:8888..." % ip_agente.text)
	if ros.connect_agent():
		log_linea("*** SESION XRCE ESTABLECIDA ***")
		auto_reintento = false
	else:
		log_linea("connect_agent() fallo (agente accesible? v2.4.3?); "
				+ "reintento cada %.0f s" % REINTENTO_PERIODO)
		auto_reintento = true
		reintento_t = 0.0
	_pinta_estado()


func _process(delta: float) -> void:
	# START sale de la app, como en la app nativa.
	if Input.is_joy_button_pressed(0, BTN_START):
		ros.shutdown()
		get_tree().quit()
		return
	# Reintento automático con backoff (docs/12 §manejo de errores). Ojo:
	# connect_agent() bloquea unos segundos mientras negocia — el frame se
	# congela durante el intento, aceptable en pantalla de conexión.
	if auto_reintento and not ros.is_session_active():
		reintento_t += delta
		if reintento_t >= REINTENTO_PERIODO:
			reintento_t = 0.0
			log_linea("reintentando conexion...")
			if ros.connect_agent():
				log_linea("*** SESION XRCE ESTABLECIDA ***")
				auto_reintento = false
			_pinta_estado()
	acumulado += delta
	if acumulado < PUB_PERIODO:
		return
	var resultado: Dictionary = ros.teleop_step(_leer_mandos(), acumulado)
	acumulado = 0.0
	ros.spin(5)  # atiende heartbeats/ACKs de la sesión XRCE
	lbl_twist.text = "cmd_vel  lin.x %+.2f  lin.y %+.2f  ang.z %+.2f" % [
		resultado.get("lin_x", 0.0), resultado.get("lin_y", 0.0),
		resultado.get("ang_z", 0.0),
	]
	lbl_escalas.text = "vel_lineal %.1f   vel_lateral %.1f" % [
		resultado.get("vel_lineal", 0.0), resultado.get("vel_lateral", 0.0),
	]


func _leer_mandos() -> Dictionary:
	# En la Vita el pad es el joypad 0 (joypad_vita.cpp). En la laptop,
	# fallback de teclado para probar la UI sin mando: flechas = cruceta,
	# Q/E = L/R, X = cruz, T = triángulo.
	var entrada := {
		"lx": Input.get_joy_axis(0, JOY_ANALOG_LX),
		"ly": Input.get_joy_axis(0, JOY_ANALOG_LY),
		"rx": Input.get_joy_axis(0, JOY_ANALOG_RX),
		"ry": Input.get_joy_axis(0, JOY_ANALOG_RY),
		"up": Input.is_joy_button_pressed(0, BTN_UP),
		"down": Input.is_joy_button_pressed(0, BTN_DOWN),
		"left": Input.is_joy_button_pressed(0, BTN_LEFT),
		"right": Input.is_joy_button_pressed(0, BTN_RIGHT),
		"l": Input.is_joy_button_pressed(0, BTN_L),
		"r": Input.is_joy_button_pressed(0, BTN_R),
		"cross": Input.is_joy_button_pressed(0, BTN_CROSS),
		"triangle": Input.is_joy_button_pressed(0, BTN_TRIANGLE),
	}
	if es_stub:
		entrada.up = entrada.up or Input.is_key_pressed(KEY_UP)
		entrada.down = entrada.down or Input.is_key_pressed(KEY_DOWN)
		entrada.left = entrada.left or Input.is_key_pressed(KEY_LEFT)
		entrada.right = entrada.right or Input.is_key_pressed(KEY_RIGHT)
		entrada.l = entrada.l or Input.is_key_pressed(KEY_Q)
		entrada.r = entrada.r or Input.is_key_pressed(KEY_E)
		entrada.cross = entrada.cross or Input.is_key_pressed(KEY_X)
		entrada.triangle = entrada.triangle or Input.is_key_pressed(KEY_T)
	return entrada


func _pinta_estado() -> void:
	if es_stub:
		lbl_estado.text = "SIMULADO (laptop, sin modulo nativo)"
		lbl_estado.modulate = Color.yellow
	elif ros.is_session_active():
		lbl_estado.text = "CONECTADO (sesion XRCE activa)"
		lbl_estado.modulate = Color.green
	else:
		lbl_estado.text = "SIN SESION - pulsa Conectar"
		lbl_estado.modulate = Color.red


func log_linea(msg: String) -> void:
	consola.add_text(msg + "\n")
	ros.netlog("[godot-ui] " + msg)
