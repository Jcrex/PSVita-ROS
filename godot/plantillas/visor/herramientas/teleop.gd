extends "res://comun/visor/herramienta_visor.gd"
## Teleop (Foxglove Teleop, rqt_robot_steering, teleop_twist_joy; doc 36a §4.8.10, ficha hmi#19): stick izquierdo
## de la Vita o flechas del PC → `geometry_msgs/Twist` en `/cmd_vel` (52 B) a 20 Hz, SOLO con hombre muerto
## (R mantenido en la Vita, Mayús en el PC; `enable_button` de teleop_twist_joy). Al soltar sale **un** Twist cero y
## luego silencio (la puerta del robot para sola, docs/32 §Q5). △/✕ suben/bajan la escala (como g6-hmi; ✕ hasta 0).
##
## QoS (doc 36 §6): fiable, profundidad 1, volátil, como g6-hmi (validado en hardware, `godot/g6-hmi/main.gd:65`):
## turtlesim y diff_drive se suscriben fiables. Con el G1, `fiabilidad = BEST_EFFORT` en la escena
## (`godot/plantillas/robots/humanoide_g1.gd:163-164`). Con robots reales el camino es `/vita/mando` (ADR 0012 §3).
##
## Mapeo (REP-103, `g6-hmi/main.gd:90-91`): linear.x = −eje Y × v_max; angular.z = −eje X × w_max (izquierda
## positiva); zona muerta reescalada (`g6-hmi/main.gd:76-81`). `+ 0.0` evita publicar −0,0 (`g6-hmi/main.gd:98`).
##
## Decisiones no cubiertas (las más conservadoras; visor/README.md):
##   - solo publica con la herramienta ACTIVA (SELECT); al desactivarla en marcha manda el Twist cero;
##   - escala multiplicativa sobre v_max/w_max: 1,0 al empezar, paso 0,25, tope 2,0 (g6-hmi usa m/s absolutos);
##   - el `RosTimer` de 0,05 s se crea en `conectar()` (tras la base); `tick()` es público para las pruebas;
##   - el R de hombre muerto choca con el R de cambio de pestaña de GestorHud: en `visor-ros/main.tscn` la
##     pestaña cambia solo con L (`boton_siguiente = -1`).

@export var v_max := 0.5                       # m/s
@export var w_max := 1.0                       # rad/s
@export var zona_muerta := 0.12                # g6-hmi/main.gd:19
@export var periodo_s := 0.05                  # 20 Hz
@export var boton_hombre_muerto := JOY_BUTTON_RIGHT_SHOULDER
@export var tecla_hombre_muerto := KEY_SHIFT
@export var escala_paso := 0.25
@export var escala_max := 2.0

var escala := 1.0
var en_marcha := false                         # el último Twist publicado no era el cero de parada
var ultimo_lin := 0.0
var ultimo_ang := 0.0
var _timer = null                              # RosTimer (guardar la referencia: si se suelta, se cancela)
var _simulado = null                           # [lin −1..1, ang −1..1, hombre_muerto] (pruebas de host)


static func nombre_herramienta() -> String:
	return "Teleop"


func _init() -> void:
	topic = "/cmd_vel"
	tipo = "geometry_msgs/msg/Twist"


func _profundidad_tabla() -> int:
	return 1                                   # doc 36 §6: teleop directo, historial 1 en PC y Vita


func conectar(v) -> void:
	super.conectar(v)
	if estado == "ok" and v.contexto.nodo.has_method("create_timer"):
		_timer = v.contexto.nodo.create_timer(periodo_s, tick)


func desconectar() -> void:
	super.desconectar()
	if _timer != null:
		_timer.cancel()
	_timer = null


## Entrada simulada para las pruebas (null = mandos reales).
func simular(lin: float, ang: float, hombre_muerto: bool) -> void:
	_simulado = [lin, ang, hombre_muerto]


func _eje(a: JoyAxis) -> float:
	var v := Input.get_joy_axis(0, a)
	if absf(v) < zona_muerta:
		return 0.0
	return signf(v) * (absf(v) - zona_muerta) / (1.0 - zona_muerta)


## [lin −1..1, ang −1..1, hombre_muerto]
func _leer() -> Array:
	if _simulado != null:
		return _simulado
	var hm := Input.is_joy_button_pressed(0, boton_hombre_muerto) or Input.is_key_pressed(tecla_hombre_muerto)
	var lin := clampf(-_eje(JOY_AXIS_LEFT_Y) + Input.get_axis("ui_down", "ui_up"), -1.0, 1.0)
	var ang := clampf(-_eje(JOY_AXIS_LEFT_X) + Input.get_axis("ui_right", "ui_left"), -1.0, 1.0)
	return [lin, ang, hm]


## Una vuelta del temporizador (20 Hz): Twist con hombre muerto; al soltar, un cero y silencio.
func tick() -> void:
	if pub == null:
		return
	var e := _leer()
	var hm: bool = activa and e[2]
	if not hm and not en_marcha:
		return
	var m = RosMsg.from_type(tipo)
	ultimo_lin = 0.0
	ultimo_ang = 0.0
	if hm:
		ultimo_lin = float(e[0]) * v_max * escala + 0.0
		ultimo_ang = float(e[1]) * w_max * escala + 0.0
	m.linear.x = ultimo_lin
	m.angular.z = ultimo_ang
	publicar(m)
	en_marcha = hm


func _al_activar(on: bool) -> void:
	if not on and en_marcha:
		tick()                                  # activa = false ⇒ sale el Twist cero


func _entrada(e: InputEvent) -> bool:
	if not (e is InputEventJoypadButton and e.pressed):
		return false
	if e.button_index == JOY_BUTTON_Y:          # △
		escala = minf(escala + escala_paso, escala_max)
		return true
	if e.button_index == JOY_BUTTON_A:          # ✕ (hasta 0 = parado)
		escala = maxf(escala - escala_paso, 0.0)
		return true
	return false
