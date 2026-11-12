extends CharacterBody3D

const Contexto = preload("res://comun/ros/contexto_ros.gd")
const Util = preload("res://comun/ros/util_ros.gd")

@export var topic_cmd := "/cmd_vel"
@export var topic_cmd_stamped := ""
@export var aceptar_teleop_local := true
@export var timeout_cmd := 0.5
@export var velocidad_max := Vector3(1.0, 1.0, 1.5)
@export var aceleracion_max := Vector3(1.5, 1.5, 7.5)
@export var vuelo := false

var contexto := Contexto.new()
var orden_objetivo := Vector3.ZERO
var orden_actual := Vector3.ZERO
var emergencia := false
var _desde_cmd := -1.0
var _timeout_orden := 0.5           # timeout de la orden en curso (timeout_cmd, o la duración de la API 7105)
var _vel_vertical := 0.0            # caída acumulada (revisión R2-B6)
var _teleop_local_activo := false   # hombre muerto de la teleop local (revisión R2-C3)
var _sub_cmd: RosSubscriber
var _sub_cmd_stamped: RosSubscriber
var _ultima_posicion := Vector3.ZERO
var _velocidad_mundo := Vector3.ZERO
var _velocidad_angular_mundo := Vector3.ZERO
var _yaw_anterior := 0.0


func configurar_ros(nombre: String, espacio: String, transporte: String) -> int:
	var err := contexto.iniciar(nombre, espacio, transporte)
	if err != OK:
		return err
	if topic_cmd != "":
		_sub_cmd = contexto.suscripcion(topic_cmd, "geometry_msgs/msg/Twist", recibir_cmd)
	if topic_cmd_stamped != "":
		_sub_cmd_stamped = contexto.suscripcion(topic_cmd_stamped, "geometry_msgs/msg/TwistStamped", recibir_cmd_stamped)
	return OK


func recibir_cmd(msg) -> void:
	fijar_orden(Vector3(msg.linear.x, msg.linear.y, msg.angular.z))


func recibir_cmd_stamped(msg) -> void:
	fijar_orden(Vector3(msg.twist.linear.x, msg.twist.linear.y, msg.twist.angular.z))


func fijar_emergencia(activa: bool) -> void:
	emergencia = activa
	if emergencia:
		_parar_orden()


## Pone a cero TODA la orden. Los robots con ejes extra (yaw del dron) lo amplían para que el hombre muerto,
## el timeout y la emergencia los paren también (revisión R2-A6).
func _parar_orden() -> void:
	orden_objetivo = Vector3.ZERO


func fijar_orden(orden: Vector3) -> void:
	if emergencia:
		return
	orden_objetivo = Vector3(
			clampf(orden.x, -velocidad_max.x, velocidad_max.x),
			clampf(orden.y, -velocidad_max.y, velocidad_max.y),
			clampf(orden.z, -velocidad_max.z, velocidad_max.z))
	_desde_cmd = 0.0
	_timeout_orden = timeout_cmd


## Orden con duración propia (p. ej. `duration` de la API Unitree 7105, revisión R3-2.4); después, a cero.
func fijar_orden_durante(orden: Vector3, duracion: float) -> void:
	fijar_orden(orden)
	if not emergencia and duracion > 0.0:
		_timeout_orden = duracion


func leer_teleop() -> Vector3:
	var x := -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	var y := -Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if Input.is_key_pressed(KEY_W): x = 1.0
	if Input.is_key_pressed(KEY_S): x = -1.0
	if Input.is_key_pressed(KEY_A): y = 1.0
	if Input.is_key_pressed(KEY_D): y = -1.0
	var z := 0.0
	if Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER) or Input.is_key_pressed(KEY_Q): z += 1.0
	if Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER) or Input.is_key_pressed(KEY_E): z -= 1.0
	var orden := Vector3(x, y, z)
	if orden.length() < 0.2:
		return Vector3.ZERO
	return orden


## Aplica la lectura local; devuelve false si no hay entrada (el dron añade su yaw, revisión R2-A6).
func _aplicar_teleop_local(local: Vector3) -> bool:
	if local == Vector3.ZERO:
		return false
	orden_objetivo = local
	return true


func _physics_process(dt: float) -> void:
	if emergencia:
		_parar_orden()
	if _desde_cmd >= 0.0:
		_desde_cmd += dt
		if _desde_cmd > _timeout_orden:
			_parar_orden()
			_desde_cmd = -1.0
	if aceptar_teleop_local and not emergencia:
		if _aplicar_teleop_local(leer_teleop()):
			_desde_cmd = -1.0
			_teleop_local_activo = true
		elif _teleop_local_activo:
			# Al soltar el mando, parar: antes el robot seguía con la última velocidad indefinidamente.
			_parar_orden()
			_teleop_local_activo = false
	for i in 3:
		orden_actual[i] = move_toward(orden_actual[i], orden_objetivo[i], aceleracion_max[i] * dt)
	_integrar_movimiento(dt)
	_actualizar_estado(dt)


func _integrar_movimiento(dt: float) -> void:
	var local_ros := Vector3(orden_actual.x, orden_actual.y, 0.0)
	var mundial_ros := local_ros.rotated(Vector3(0.0, 0.0, 1.0), rotation.y)
	velocity = Util.vector_godot(mundial_ros)
	if vuelo:
		velocity.y = orden_actual.z
	else:
		rotation.y += orden_actual.z * dt
		# R2-B6: la velocidad se reconstruye cada tick, así que la caída se guarda aparte para que acumule.
		_vel_vertical = 0.0 if is_on_floor() else _vel_vertical - 9.80665 * dt
		velocity.y = _vel_vertical
	move_and_slide()


func _actualizar_estado(dt: float) -> void:
	if dt <= 0.0:
		return
	_velocidad_mundo = (global_position - _ultima_posicion) / dt
	_ultima_posicion = global_position
	_velocidad_angular_mundo = Vector3(0.0, wrapf(rotation.y - _yaw_anterior, -PI, PI) / dt, 0.0)
	_yaw_anterior = rotation.y


func posicion_ros() -> Vector3:
	return Util.vector_ros(global_position)


func orientacion_ros() -> Quaternion:
	return Util.quat_ros(global_basis.get_rotation_quaternion())


## Pose del marco base que publican la odometría y /tf (base_frame). Por defecto, el origen del cuerpo; el G1 la
## sobrescribe con la pelvis (revisión R2-A5).
func posicion_base_ros() -> Vector3:
	return posicion_ros()


func orientacion_base_ros() -> Quaternion:
	return orientacion_ros()


## Tras teletransportar (reinicio R/△): sin esto, Odometry y la IMU veían un pico de decenas de m/s (R2-B5).
func reiniciar_estado() -> void:
	velocity = Vector3.ZERO
	_vel_vertical = 0.0
	_parar_orden()
	orden_actual = Vector3.ZERO
	_ultima_posicion = global_position
	_yaw_anterior = rotation.y
	_velocidad_mundo = Vector3.ZERO
	_velocidad_angular_mundo = Vector3.ZERO


func velocidad_lineal_ros() -> Vector3:
	return Util.vector_ros(_velocidad_mundo)


func velocidad_angular_ros() -> Vector3:
	return Util.vector_ros(_velocidad_angular_mundo)


func velocidad_local_ros() -> Vector3:
	var v := velocidad_lineal_ros()
	return v.rotated(Vector3(0.0, 0.0, 1.0), -Util.yaw_de_quat(orientacion_ros()))


func _exit_tree() -> void:
	contexto.cerrar()
