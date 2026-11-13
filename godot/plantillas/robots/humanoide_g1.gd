extends "res://comun/robots/robot_ros.gd"
## Unitree G1 de las plantillas (godot/g1-sensores): mismo control y misma marcha que godot/g1-unitree/main.gd.
##
## Dos fuentes de movimiento (campo "fuente_movimiento" de robot.json; ✕/Espacio alterna en marcha):
##  - "local":  Godot es la planta. La orden (mando local, /cmd_vel, API 7105 o demo) elige un clip con
##              `_clip_para` (la MISMA función que g1-unitree/main.gd:201) y el desplazamiento sale del root motion
##              de marcha.gd (clips de la política oficial de Unitree), no de la velocidad pedida. Ese
##              desplazamiento se convierte en `velocity` y `move_and_slide()` lo choca con el mundo de las plantillas.
##  - "g1_sim": docker/vita-ros.sh g1 (MuJoCo + política oficial) es la planta. Este cuerpo sigue la pose y las
##              piernas de /g1/estado (como g1-unitree/main.gd:303 `_on_estado`) y la orden local se publica en
##              /cmd_vel, que es lo que escucha g1_sim. Los sensores siguen publicando con prefijo g1s desde esa pose.

const POSE_DEFECTO := {
	"left_hip_pitch_joint": -0.1, "left_knee_joint": 0.3, "left_ankle_pitch_joint": -0.2,
	"right_hip_pitch_joint": -0.1, "right_knee_joint": 0.3, "right_ankle_pitch_joint": -0.2,
}
const MOTORES := [
	"left_hip_pitch_joint", "left_hip_roll_joint", "left_hip_yaw_joint", "left_knee_joint",
	"left_ankle_pitch_joint", "left_ankle_roll_joint", "right_hip_pitch_joint", "right_hip_roll_joint",
	"right_hip_yaw_joint", "right_knee_joint", "right_ankle_pitch_joint", "right_ankle_roll_joint",
	"waist_yaw_joint", "waist_roll_joint", "waist_pitch_joint", "left_shoulder_pitch_joint",
	"left_shoulder_roll_joint", "left_shoulder_yaw_joint", "left_elbow_joint", "left_wrist_roll_joint",
	"left_wrist_pitch_joint", "left_wrist_yaw_joint", "right_shoulder_pitch_joint", "right_shoulder_roll_joint",
	"right_shoulder_yaw_joint", "right_elbow_joint", "right_wrist_roll_joint", "right_wrist_pitch_joint",
	"right_wrist_yaw_joint",
]
## Zona muerta por eje del stick, la misma que g1-unitree/main.gd:31.
const ZONA_MUERTA := 0.25
const ALTURA_PELVIS := 0.78   # m (pose por defecto; g1-unitree/main.gd:30)

## R2-M5: mientras lleguen LowCmd, la marcha no pisa las piernas; si dejan de llegar, vuelve la marcha.
@export var timeout_lowcmd := 0.5
## "local" o "g1_sim" (ver cabecera). Se lee de robot.json en inicializar_modelo().
@export var fuente_movimiento := "local"
@export var g1_sim_topic_estado := "/g1/estado"
@export var g1_sim_topic_cmd := "/cmd_vel"
## "relativo": al entrar en g1_sim, la pose actual del cuerpo se hace coincidir con la primera pose recibida y desde
## ahí se siguen los incrementos (el G1 no aparece dentro de una pared del mundo de las plantillas).
## "absoluto": x, y, yaw de /g1/estado se usan tal cual (marco odom de g1_sim = mundo de Godot).
@export var g1_sim_anclaje := "relativo"

var marcha = null   # instancia de marcha.gd (RefCounted); sin tipo porque es un script cargado por ruta
var _modelo: Node3D
var _pelvis: Node3D
var _desde_lowcmd := -1.0
var _nombres := PackedStringArray()
var _posiciones := PackedFloat32Array()
var _indices_piernas := PackedInt32Array()   # marcha.joints[i] → índice en _nombres (precalculado)
var _bloqueado := false

# Estado del modo g1_sim
var _pub_cmd_sim: RosPublisher
var _sub_estado_sim: RosSubscriber   # guardar la referencia: si se suelta, la suscripción se cancela
var _estado_sim := PackedFloat32Array()
var _estado_nuevo := false
var _estados_recibidos := 0
var _t_ultimo_estado := -1.0
var _t := 0.0
var _cmd_t := 0.0
var _ceros_pendientes := 0
var _anclado := false
var _ancla_yaw := 0.0
var _ancla_pos := Vector2.ZERO
var _t_estado_anterior := -1.0
var _pos_estado_anterior := Vector3.ZERO
var _yaw_estado_anterior := 0.0


func inicializar_modelo(config: Dictionary) -> void:
	_modelo = get_node("Modelo")
	_nombres = _modelo.call("nombres_joints_movibles")
	_pelvis = _modelo.find_child("pelvis", true, false)
	_posiciones.resize(_nombres.size())
	for i in _nombres.size():
		_posiciones[i] = POSE_DEFECTO.get(_nombres[i], 0.0)
	# load() y no preload(): res://marcha.gd solo existe en g1-sensores (enlace a g1-unitree); con preload, abrir
	# las plantillas desde rbkairos-plus o dron-mapeo daría error al analizar este script.
	var script_marcha: Script = load("res://marcha.gd")
	marcha = script_marcha.new()
	if not marcha.cargar("res://anim/g1_marcha.json"):
		push_error("No se pudo cargar la marcha del G1")
	for nombre in marcha.joints:
		_indices_piernas.append(_nombres.find(nombre))
	fuente_movimiento = config.get("fuente_movimiento", fuente_movimiento)
	g1_sim_topic_estado = config.get("g1_sim_topic_estado", g1_sim_topic_estado)
	g1_sim_topic_cmd = config.get("g1_sim_topic_cmd", g1_sim_topic_cmd)
	g1_sim_anclaje = config.get("g1_sim_anclaje", g1_sim_anclaje)
	_sincronizar_marcha()
	_aplicar_marcha_al_modelo()


# ---------------------------------------------------------------- mando local (= g1-unitree/main.gd:177)

## Mismo mapeo que g1-unitree `_leer_orden`: stick izq. ↑↓ / W·S avanza (a tope o con Mayús = correr), stick
## izq. ←→ / A·D GIRA, L·R / Q·E paso lateral. Antes (robot_ros.gd:196) A/D daban paso lateral y Q/E giro, el
## stick lateral iba a vy y no había zona muerta por eje: por eso «no concordaba» con g1-unitree.
## Devuelve Vector3.ZERO sin entrada → robot_ros.gd aplica el hombre muerto al soltar.
func leer_teleop() -> Vector3:
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
	var vx := 0.0
	if absf(ly) > ZONA_MUERTA:
		vx = ly * (1.0 if ly > 0 else 0.6)
	var wz := lx if absf(lx) > ZONA_MUERTA else 0.0
	return Vector3(vx, vy, wz)


## Elige el clip grabado más parecido a la orden: copia literal de g1-unitree/main.gd:201 (antes se usaban
## umbrales de ±0,05 sobre la orden RAMPEADA, así que el clip cambiaba con retraso respecto al mando).
static func _clip_para(o: Vector3) -> String:
	if o.x > 0.85: return "correr"
	if o.x > 0.0: return "andar"
	if o.x < 0.0: return "atras"
	if o.z > 0.0: return "girar_izq"
	if o.z < 0.0: return "girar_der"
	if o.y > 0.0: return "izquierda"
	if o.y < 0.0: return "derecha"
	return "quieto"


## ✕/Espacio alterna local ↔ g1_sim (en g1-unitree ✕ recorría sus modos «marcha», «ros», …).
func _unhandled_input(ev: InputEvent) -> void:
	var pulsado: bool = (ev is InputEventJoypadButton and ev.pressed and ev.button_index == JOY_BUTTON_A) \
			or (ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_SPACE)
	if pulsado:
		fijar_fuente("g1_sim" if fuente_movimiento == "local" else "local")


func fijar_fuente(fuente: String) -> void:
	if fuente == fuente_movimiento:
		return
	if fuente_movimiento == "g1_sim":
		_publicar_cmd_sim(Vector3.ZERO)   # que g1_sim se pare al dejar de mandarle
	fuente_movimiento = fuente
	_anclado = false
	_estado_nuevo = false
	_t_estado_anterior = -1.0
	if fuente == "g1_sim":
		_preparar_g1_sim()
	else:
		_sincronizar_marcha()


# ---------------------------------------------------------------- ROS

func configurar_ros(nombre: String, espacio: String, transporte: String) -> int:
	var err := super.configurar_ros(nombre, espacio, transporte)
	if err == OK and fuente_movimiento == "g1_sim":
		_preparar_g1_sim()
	return err


## Crea (una vez) el publicador de /cmd_vel y la suscripción a /g1/estado. Best effort en los dos: g1_sim
## publica /g1/estado y se suscribe a /cmd_vel en best effort (docker/g1/g1_sim.py:229 y :267).
func _preparar_g1_sim() -> void:
	if contexto.nodo == null or _sub_estado_sim != null:
		return
	_pub_cmd_sim = contexto.publicador(g1_sim_topic_cmd, "geometry_msgs/msg/Twist", true)
	_sub_estado_sim = contexto.suscripcion(g1_sim_topic_estado, "std_msgs/msg/Float32MultiArray", _on_estado_sim, true)


## En g1_sim, /cmd_vel lo consume g1_sim directamente; si este nodo además lo recogiera, lo reenviaría (y
## recibiría sus propias publicaciones). Solo la teleop local, la API 7105 y la demo se reenvían.
func recibir_cmd(msg) -> void:
	if fuente_movimiento == "g1_sim":
		return
	super.recibir_cmd(msg)


func recibir_cmd_stamped(msg) -> void:
	if fuente_movimiento == "g1_sim":
		return
	super.recibir_cmd_stamped(msg)


## /g1/estado = [x, y, z, qx, qy, qz, qw, q0..q11] (docker/g1/g1_sim.py:119). Se guarda y se aplica en el tick
## de física, para que move/velocidades se calculen en un solo sitio.
func _on_estado_sim(m) -> void:
	var d: PackedFloat32Array = m.data
	if d.size() < 19:
		return
	_estado_sim = d
	_estado_nuevo = true
	_estados_recibidos += 1
	_t_ultimo_estado = _t


func _publicar_cmd_sim(o: Vector3) -> void:
	if _pub_cmd_sim == null:
		return
	var m := RosMsg.from_type("geometry_msgs/msg/Twist")
	m.linear.x = o.x + 0.0   # +0.0 evita publicar -0.0 (como g1-unitree/main.gd:318)
	m.linear.y = o.y + 0.0
	m.angular.z = o.z + 0.0
	_pub_cmd_sim.publish(m)


# ---------------------------------------------------------------- tick

func _physics_process(dt: float) -> void:
	_t += dt
	# robot_ros.gd: emergencia, timeout de /cmd_vel, teleop local con hombre muerto, rampa y _integrar_movimiento.
	super._physics_process(dt)


func _integrar_movimiento(dt: float) -> void:
	if marcha == null:
		super._integrar_movimiento(dt)
		return
	if fuente_movimiento == "g1_sim":
		_seguir_g1_sim(dt)
	else:
		_marcha_local(dt)


## Modo local: root motion de marcha.gd como en g1-unitree/main.gd:218-224, pero el paso lo da move_and_slide.
func _marcha_local(dt: float) -> void:
	# La orden SIN rampa elige el clip, como g1-unitree (allí `cmd` va directo a `_clip_para`). La rampa de
	# robot_ros (orden_actual) solo la usan la batería y la telemetría; la suavidad la pone la mezcla de 0,25 s.
	marcha.pedir(_clip_para(orden_objetivo))
	_sincronizar_marcha()   # parte de la pose real del cuerpo (tras chocar o tras reiniciar con R/△)
	var antes: Vector2 = marcha.pos
	# Sin colisión dentro de marcha.gd: la hace la física. g1-unitree usa colision_casa.libre (rejilla 2D).
	marcha.avanzar(dt, func(_p): return true)
	var paso: Vector2 = marcha.pos - antes
	# Root motion → velocidad: move_and_slide recorre exactamente `paso` si no choca y desliza si choca.
	velocity = Util.vector_godot(Vector3(paso.x, paso.y, 0.0)) / maxf(dt, 1e-6)
	rotation.y = marcha.yaw   # guiñada ROS = rotation.y (misma convención que robot_ros.gd:244)
	_vel_vertical = 0.0 if is_on_floor() else _vel_vertical - 9.80665 * dt
	velocity.y = _vel_vertical
	move_and_slide()
	_bloqueado = is_on_wall()
	_aplicar_marcha_al_modelo()


func _sincronizar_marcha() -> void:
	if marcha == null:
		return
	var p := posicion_ros()
	marcha.pos = Vector2(p.x, p.y)
	marcha.yaw = rotation.y


## Pose y piernas del clip en el modelo. La guiñada la lleva el CharacterBody3D (rotation.y), así que al modelo
## solo se le da la altura y la inclinación del clip (sin su guiñada).
func _aplicar_marcha_al_modelo() -> void:
	var pose: Array = marcha.pose_base()
	var q_local: Quaternion = Quaternion(Vector3(0.0, 0.0, 1.0), -marcha.yaw) * pose[1]
	_modelo.call("set_base_pose_ros", Vector3(0.0, 0.0, pose[0].z), q_local)
	if _desde_lowcmd >= 0.0:
		_desde_lowcmd += get_physics_process_delta_time()
		if _desde_lowcmd > timeout_lowcmd:
			_desde_lowcmd = -1.0
	if _desde_lowcmd < 0.0:
		_copiar_piernas(marcha.q_joints())
	_modelo.call("set_joints", _nombres, _posiciones)


func _copiar_piernas(q: PackedFloat32Array) -> void:
	for i in mini(_indices_piernas.size(), q.size()):
		if _indices_piernas[i] >= 0:
			_posiciones[_indices_piernas[i]] = q[i]


## Modo g1_sim: publica la orden a 20 Hz (como g1-unitree/main.gd:227) y copia la última pose de /g1/estado.
func _seguir_g1_sim(dt: float) -> void:
	velocity = Vector3.ZERO
	_cmd_t += dt
	if _cmd_t >= 0.05:
		_cmd_t = 0.0
		# Solo mientras hay orden y unos ceros al soltar (hombre muerto): publicar ceros siempre, como hace
		# g1-unitree, taparía cualquier otro /cmd_vel (Nav2, teleop_twist_keyboard) que mande a g1_sim.
		if orden_objetivo != Vector3.ZERO:
			_publicar_cmd_sim(orden_objetivo)
			_ceros_pendientes = 5
		elif _ceros_pendientes > 0:
			_publicar_cmd_sim(Vector3.ZERO)
			_ceros_pendientes -= 1
	if not _estado_nuevo:
		return
	_estado_nuevo = false
	var d := _estado_sim
	var yaw_sim := Util.yaw_de_xyzw(d[3], d[4], d[5], d[6])
	if not _anclado:
		_anclado = true
		if g1_sim_anclaje == "absoluto":
			_ancla_yaw = 0.0
			_ancla_pos = Vector2.ZERO
		else:
			# Transformación 2D que lleva la primera pose de g1_sim a la pose actual del cuerpo.
			var p := posicion_ros()
			_ancla_yaw = wrapf(rotation.y - yaw_sim, -PI, PI)
			_ancla_pos = Vector2(p.x, p.y) - Vector2(d[0], d[1]).rotated(_ancla_yaw)
	var xy := Vector2(d[0], d[1]).rotated(_ancla_yaw) + _ancla_pos
	# g1_sim no conoce el mundo de las plantillas (su casa es otra): el cuerpo se teletransporta en x, y y la altura
	# la da el suelo de Godot bajo ese punto (rayo vertical), para no hundir los pies en tarimas o rampas.
	global_position = Util.vector_godot(Vector3(xy.x, xy.y, _altura_suelo(xy)))
	rotation.y = wrapf(yaw_sim + _ancla_yaw, -PI, PI)
	# Al modelo: altura real de la pelvis (d[2]) e inclinación sin guiñada, como en el modo local.
	var q_sim := Quaternion(d[3], d[4], d[5], d[6]).normalized()
	_modelo.call("set_base_pose_ros", Vector3(0.0, 0.0, d[2]), Quaternion(Vector3(0.0, 0.0, 1.0), -yaw_sim) * q_sim)
	_copiar_piernas(d.slice(7, 19))
	_modelo.call("set_joints", _nombres, _posiciones)


## Altura ROS (z) del suelo bajo (x, y): rayo de 2 m hacia abajo desde 0,4 m sobre la altura actual (sube escalones
## de hasta 0,4 m, pero no se sube a mesas ni muebles), sin chocar con el
## propio cuerpo. Sin suelo debajo, mantiene la altura actual. Solo se usa en g1_sim (25 Hz, 1 rayo).
func _altura_suelo(xy: Vector2) -> float:
	var z_actual := posicion_ros().z
	var espacio := get_world_3d().direct_space_state
	var desde := Util.vector_godot(Vector3(xy.x, xy.y, z_actual + 0.4))
	var rayo := PhysicsRayQueryParameters3D.create(desde, desde + Vector3(0.0, -2.0, 0.0))
	rayo.exclude = [get_rid()]
	var choque := espacio.intersect_ray(rayo)
	if choque.is_empty():
		return z_actual
	return Util.vector_ros(choque.position).z


## En g1_sim el cuerpo salta a 25 Hz (ritmo de /g1/estado) y el tick de física va a 60 Hz: derivar la posición
## cada tick daría 0, 0, pico… Se deriva solo cuando llega un estado, con el tiempo entre estados.
func _actualizar_estado(dt: float) -> void:
	if fuente_movimiento != "g1_sim":
		super._actualizar_estado(dt)
		return
	if _t_estado_anterior >= 0.0 and _t_ultimo_estado > _t_estado_anterior:
		var h := _t_ultimo_estado - _t_estado_anterior
		_velocidad_mundo = (global_position - _pos_estado_anterior) / h
		_velocidad_angular_mundo = Vector3(0.0, wrapf(rotation.y - _yaw_estado_anterior, -PI, PI) / h, 0.0)
	if _t_ultimo_estado != _t_estado_anterior:
		_t_estado_anterior = _t_ultimo_estado
		_pos_estado_anterior = global_position
		_yaw_estado_anterior = rotation.y
	_ultima_posicion = global_position
	_yaw_anterior = rotation.y


## R/△ (aplicacion_robot.gd) teletransporta el cuerpo y llama aquí: la marcha vuelve al fotograma 0 y, en g1_sim,
## se re-ancla (la próxima pose de g1_sim cae en el punto de reinicio).
func reiniciar_estado() -> void:
	super.reiniciar_estado()
	_anclado = false
	_t_estado_anterior = -1.0
	if marcha != null:
		marcha.f = 0.0
		marcha.pedir("quieto")
		_sincronizar_marcha()


## Línea extra del HUD (aplicacion_robot.gd la añade si existe).
func linea_hud() -> String:
	if fuente_movimiento == "g1_sim":
		var estado := "sin ROS"
		if contexto.nodo != null:
			if _t_ultimo_estado < 0.0 or _t - _t_ultimo_estado > 1.0:
				estado = "sin %s: arranca docker/vita-ros.sh g1" % g1_sim_topic_estado
			else:
				estado = "%s recibidos: %d" % [g1_sim_topic_estado, _estados_recibidos]
		return "Movimiento: g1_sim (✕/Espacio → local) · %s · orden (%.1f, %.1f, %.1f)" % [
			estado, orden_objetivo.x, orden_objetivo.y, orden_objetivo.z]
	var clip: String = marcha.actual if marcha != null else "?"
	return "Movimiento: local (✕/Espacio → g1_sim) · clip %s%s" % [clip, "  [pared]" if _bloqueado else ""]


## R2-A5: la odometría y /tf publican odom→pelvis con la pose REAL de la pelvis (~0,79 m y su balanceo), no el
## origen del CharacterBody3D a la altura de los pies.
func posicion_base_ros() -> Vector3:
	if _pelvis == null:
		return posicion_ros()
	return Util.vector_ros(_pelvis.global_position)


func orientacion_base_ros() -> Quaternion:
	if _pelvis == null:
		return orientacion_ros()
	# La pelvis cuelga de RosFrame (ejes ROS): su base global lleva ejes ROS a Godot; quat_ros(G·C⁻¹) = C⁻¹·G.
	var g := _pelvis.global_basis.orthonormalized() * Util.BASE_ROS_A_GODOT.inverse()
	return Util.quat_ros(g.get_rotation_quaternion())


func nombres_joints() -> PackedStringArray:
	return _nombres


func posiciones_joints(nombres: PackedStringArray) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	for nombre in nombres:
		var i := _nombres.find(nombre)
		r.append(_posiciones[i] if i >= 0 else 0.0)
	return r


func fijar_motor(indice: int, q: float) -> void:
	if emergencia or fuente_movimiento == "g1_sim":
		return   # en g1_sim las piernas las manda MuJoCo; LowCmd no tendría efecto real
	if indice < 0 or indice >= MOTORES.size():
		return
	var i := _nombres.find(MOTORES[indice])
	if i >= 0:
		_posiciones[i] = q
		_desde_lowcmd = 0.0   # modo bajo nivel: la marcha queda en pausa (R2-M5)


# Los sensores se montan en sus links con el campo «link» de robot.json, que resuelve aplicacion_robot.gd
# (revisión R2-A3: antes un diccionario fijo dejaba mid360_scan e imu_mid360 a ras de suelo y montaba los demás
# con la base identidad, es decir, con los ejes Godot del sensor sobre los ejes ROS del link).
