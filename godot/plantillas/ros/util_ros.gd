extends RefCounted

const GRAVEDAD_GODOT := Vector3(0.0, -9.80665, 0.0)


static func vector_ros(v: Vector3) -> Vector3:
	return rclgd.godot_to_ros_vector(v)


static func vector_godot(v: Vector3) -> Vector3:
	return rclgd.ros_to_godot_vector(v)


static func quat_ros(q: Quaternion) -> Quaternion:
	return rclgd.godot_to_ros_quat(q)


static func escribir_vector(destino, v: Vector3) -> void:
	destino.x = v.x
	destino.y = v.y
	destino.z = v.z


static func escribir_quat(destino, q: Quaternion) -> void:
	destino.x = q.x
	destino.y = q.y
	destino.z = q.z
	destino.w = q.w


static func diagonal(varianza: float) -> PackedFloat64Array:
	var v := maxf(varianza, 1e-12)
	return PackedFloat64Array([v, 0.0, 0.0, 0.0, v, 0.0, 0.0, 0.0, v])


static func covarianza_6d(lineal: float, angular: float) -> PackedFloat64Array:
	var c := PackedFloat64Array()
	c.resize(36)
	c.fill(0.0)
	for i in [0, 7, 14]:
		c[i] = lineal
	for i in [21, 28, 35]:
		c[i] = angular
	return c


static func yaw_de_quat(q: Quaternion) -> float:
	return atan2(2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z))


static func quat_de_yaw(yaw: float) -> Quaternion:
	return Quaternion(Vector3(0.0, 0.0, 1.0), yaw)


static func hacer_campo_nube(nombre_campo: String, desplazamiento: int):
	var campo = RosMsg.from_type("sensor_msgs/msg/PointField")
	campo.name = nombre_campo
	campo.offset = desplazamiento
	campo.datatype = 7
	campo.count = 1
	return campo
