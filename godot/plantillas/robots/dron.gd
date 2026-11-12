extends "res://comun/robots/robot_ros.gd"

var yaw_objetivo := 0.0
var yaw_actual := 0.0
var _yaw_local := 0.0
var _rotores := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


func _init() -> void:
	vuelo = true
	velocidad_max = Vector3(3.0, 3.0, 2.0)
	aceleracion_max = Vector3(3.0, 3.0, 3.0)


func recibir_cmd(msg) -> void:
	if emergencia:
		return
	fijar_orden(Vector3(msg.linear.x, msg.linear.y, msg.linear.z))
	yaw_objetivo = clampf(msg.angular.z, -1.5, 1.5)


func recibir_cmd_stamped(msg) -> void:
	if emergencia:
		return
	fijar_orden(Vector3(msg.twist.linear.x, msg.twist.linear.y, msg.twist.linear.z))
	yaw_objetivo = clampf(msg.twist.angular.z, -1.5, 1.5)


func fijar_orden(orden: Vector3) -> void:
	super.fijar_orden(orden)
	yaw_objetivo = 0.0


## R2-A6: el yaw es la cuarta componente de la orden; el timeout, la emergencia y el hombre muerto de la
## teleop local lo paran igual que x/y/z (antes seguía girando tras el timeout y en emergencia).
func _parar_orden() -> void:
	super._parar_orden()
	yaw_objetivo = 0.0


func leer_teleop() -> Vector3:
	var x := -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	# R2-M4: REP-103, +y = izquierda. Antes el stick/tecla D daban +y (derecha invertida).
	var y := -Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var z := -Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if Input.is_key_pressed(KEY_W): x = 1.0
	if Input.is_key_pressed(KEY_S): x = -1.0
	if Input.is_key_pressed(KEY_A): y = 1.0
	if Input.is_key_pressed(KEY_D): y = -1.0
	if Input.is_key_pressed(KEY_E) or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER): z = 1.0
	if Input.is_key_pressed(KEY_Q) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER): z = -1.0
	# Yaw local (stick izquierdo X o flechas). Ya no se escribe yaw_objetivo aquí: antes se ponía a 0 cada tick
	# y borraba el angular.z de /drone/cmd_vel (R2-A6).
	var yaw := -Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if absf(yaw) < 0.2: yaw = 0.0
	if Input.is_key_pressed(KEY_LEFT): yaw = 1.0
	if Input.is_key_pressed(KEY_RIGHT): yaw = -1.0
	_yaw_local = yaw
	var orden := Vector3(x, y, z)
	return orden if orden.length() >= 0.2 else Vector3.ZERO


func _aplicar_teleop_local(local: Vector3) -> bool:
	if local == Vector3.ZERO and _yaw_local == 0.0:
		return false
	orden_objetivo = local
	yaw_objetivo = _yaw_local
	return true


func _integrar_movimiento(dt: float) -> void:
	yaw_actual = move_toward(yaw_actual, yaw_objetivo, 2.0 * dt)
	rotation.y += yaw_actual * dt
	var mundial_ros := orden_actual.rotated(Vector3(0.0, 0.0, 1.0), rotation.y)
	velocity = Util.vector_godot(mundial_ros)
	move_and_slide()
	for i in 4:
		var rpm := 5000.0 + orden_actual.length() * 400.0 + (i - 1.5) * yaw_actual * 80.0
		# R2-B7: rpm·dt/60 son vueltas; ×2π para radianes.
		_rotores[i] = wrapf(_rotores[i] + rpm * dt / 60.0 * TAU, 0.0, TAU)


func angulos_rotores() -> PackedFloat32Array:
	return _rotores
