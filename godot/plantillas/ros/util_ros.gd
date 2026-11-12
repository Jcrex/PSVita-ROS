extends RefCounted

const GRAVEDAD_GODOT := Vector3(0.0, -9.80665, 0.0)
## Columnas = ejes X, Y, Z de ROS (REP-103) expresados en Godot: X delante (-Z), Y izquierda (-X), Z arriba (+Y).
## Es la misma matriz que el nodo RosFrame de las escenas de tools/urdf2godot.
const BASE_ROS_A_GODOT := Basis(Vector3(0.0, 0.0, -1.0), Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0))


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


## Única fórmula de yaw de las plantillas (revisión R4 §2: estaba repetida). Cuaternión ROS → yaw ROS.
static func yaw_de_quat(q: Quaternion) -> float:
	return yaw_de_xyzw(q.x, q.y, q.z, q.w)


## Misma fórmula sobre componentes sueltas (p. ej. los floats 3..6 de /g1/estado), igual que
## `yaw_de_quat` de docker/scripts/vita_relay.py.
static func yaw_de_xyzw(x: float, y: float, z: float, w: float) -> float:
	return atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))


## Rotación roll-pitch-yaw de ROS (fija X, luego Y, luego Z; REP-103) como matriz en coordenadas ROS.
static func rotacion_rpy_ros(roll: float, pitch: float, yaw: float) -> Basis:
	return Basis(Vector3(0.0, 0.0, 1.0), yaw) * Basis(Vector3(0.0, 1.0, 0.0), pitch) * Basis(Vector3(1.0, 0.0, 0.0), roll)


## Base de un nodo-sensor (convención Godot: delante = -Z, arriba = +Y) colgado de un link de URDF horneado
## (ejes ROS). Sin rpy, los ejes del sensor coinciden con los del link (revisión R2-A3).
static func base_sensor_en_link(roll: float, pitch: float, yaw: float) -> Basis:
	return rotacion_rpy_ros(roll, pitch, yaw) * BASE_ROS_A_GODOT.inverse()


static func quat_de_yaw(yaw: float) -> Quaternion:
	return Quaternion(Vector3(0.0, 0.0, 1.0), yaw)


static func hacer_campo_nube(nombre_campo: String, desplazamiento: int):
	var campo = RosMsg.from_type("sensor_msgs/msg/PointField")
	campo.name = nombre_campo
	campo.offset = desplazamiento
	campo.datatype = 7
	campo.count = 1
	return campo
