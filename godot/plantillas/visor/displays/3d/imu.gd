extends "res://comun/visor/display_ros_3d.gd"
## IMU 3D (V5; doc 36a §4.4.1, V geom#18): EJES con la orientación ABSOLUTA en la posición del IMU (no se compone
## con la rotación del marco, como `rviz_imu_plugin`) [I] + FLECHA de aceleración lineal (amarilla, m/s² ×
## `escala_acel`; en reposo +9,81 en Z) + FLECHA de velocidad angular (cian, rad/s × `escala_giro`).
## `orientation_covariance[0] == -1` ⇒ sin orientación (Imu.msg) ⇒ ejes ocultos. 316–324 B: cabe en directo a
## 30–60 Hz (`docs/27:83`); con un IMU a 100 Hz, `hz` limita la entrega (el relay `ritmo/imu` llega con V6).
## Dato intermedio: `[Quaternion Godot o null, Vector3 acel (Godot, escalada), Vector3 giro (Godot, escalada)]`.
## Capa «poses»: 3 instancias (≈ 84 tri); con menos cupo se crean por orden: ejes, aceleración, giro.

const Prim = preload("res://comun/visor/primitivas_viz.gd")

@export var largo_ejes := 0.3
@export var escala_acel := 0.05                # m por m/s²
@export var escala_giro := 0.5                 # m por rad/s

var _ejes: MeshInstance3D
var _acel: MeshInstance3D
var _giro: MeshInstance3D
var con_orientacion := false


static func nombre_display() -> String:
	return "Imu"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["sensor_msgs/msg/Imu"])


func _init() -> void:
	capa = "poses"
	hz = 20.0


func conectar(v) -> void:
	super.conectar(v)
	if _ejes != null:
		return
	if cupo >= 1:
		_ejes = _nuevo(Prim.EJES, Color.WHITE)
	if cupo >= 2:
		_acel = _nuevo(Prim.FLECHA, Color(1.0, 0.8, 0.0))
	if cupo >= 3:
		_giro = _nuevo(Prim.FLECHA, Color(0.0, 0.8, 1.0))


func _nuevo(forma: int, c: Color) -> MeshInstance3D:
	var mi := Prim.instancia(forma, c)
	mi.visible = false
	add_child(mi)
	return mi


func _procesar(msg):
	var o = msg.orientation
	var a = msg.linear_acceleration
	var w = msg.angular_velocity
	var va := Vector3(a.x, a.y, a.z)
	var vw := Vector3(w.x, w.y, w.z)
	if not (va.is_finite() and vw.is_finite()):
		return null                                        # T2
	var q = null
	var cov: PackedFloat64Array = msg.orientation_covariance
	var qr := Quaternion(o.x, o.y, o.z, o.w)
	var q_ok := is_finite(qr.x) and is_finite(qr.y) and is_finite(qr.z) and is_finite(qr.w) and qr.length_squared() > 1e-6
	if (cov.is_empty() or cov[0] != -1.0) and q_ok:
		q = rclgd.ros_to_godot_quat(qr.normalized())
	return [q, rclgd.ros_to_godot_vector(va) * escala_acel, rclgd.ros_to_godot_vector(vw) * escala_giro]


func _pintar(d) -> void:
	con_orientacion = d[0] != null
	if _ejes != null:
		_ejes.visible = con_orientacion
		if con_orientacion:                                # absoluta: se anula la rotación del marco
			_ejes.transform = Transform3D(transform.basis.inverse() * Basis(d[0] as Quaternion), Vector3.ZERO) \
					.scaled_local(Vector3.ONE * largo_ejes)
	for par in [[_acel, d[1]], [_giro, d[2]]]:
		var mi: MeshInstance3D = par[0]
		if mi == null:
			continue
		var t = Prim.flecha_hacia(par[1])
		mi.visible = t != null
		if t != null:
			mi.transform = t


func _coste() -> Dictionary:
	return {"instancias": 3, "triangulos": Prim.TRIANGULOS[Prim.EJES] + 2 * Prim.TRIANGULOS[Prim.FLECHA], "quads": 0}
