extends "res://comun/visor/display_ros_3d.gd"
## Ejes 3D (V5; doc 36a §4.2.7 `orientacion.gd` y §4.2.8 `transformada.gd`, V geom#9–10; el nombre `ejes.gd` es el
## de la sentencia W13, doc 36 §10): EJES (36 tri) de una orientación o de una transformada.
##   `QuaternionStamped` (60 B): ejes girados por el cuaternión en el origen del marco + `rpy_grados` para el HUD.
##   `TransformStamped` (≈ 100 B): ejes del hijo (`child_frame_id`) en el marco del padre (`header.frame_id`) +
##   FLECHA del hijo al padre + nombre del hijo en `visor.texto` (TextoSuperpuesto, D11) si `mostrar_nombre`.
## Cuaternión nulo → se ignora (RViz lo rechaza, T14); no unitario → se normaliza. NaN/Inf → se ignora (T2).
## Dato intermedio: `[Transform3D del hijo en el marco (ejes Godot), nombre]`. Capa «poses»: 1 instancia (EJES) +
## 1 opcional (la flecha, solo con TransformStamped y cupo).

const Prim = preload("res://comun/visor/primitivas_viz.gd")

@export var largo := 0.5                       # m de cada eje
@export var mostrar_flecha := true             # TransformStamped: flecha hijo → padre
@export var mostrar_nombre := true             # TransformStamped: nombre del hijo (gasta glifos del texto, D11)
@export var color_flecha := Color(1.0, 1.0, 0.0)

var rpy_grados := Vector3.ZERO                  # último roll, pitch, yaw (grados, ROS)
var hijo := ""
var _ejes: MeshInstance3D
var _flecha: MeshInstance3D


static func nombre_display() -> String:
	return "Ejes"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["geometry_msgs/msg/QuaternionStamped", "geometry_msgs/msg/TransformStamped"])


func _init() -> void:
	capa = "poses"
	hz = 10.0


func conectar(v) -> void:
	super.conectar(v)
	if cupo > 0 and _ejes == null:
		_ejes = Prim.instancia(Prim.EJES)
		_ejes.visible = false
		add_child(_ejes)
	if cupo > 1 and _flecha == null and mostrar_flecha:
		_flecha = Prim.instancia(Prim.FLECHA, color_flecha)
		_flecha.visible = false
		add_child(_flecha)


func _procesar(msg):
	var o
	var pos := Vector3.ZERO
	var nombre := ""
	if "transform" in msg:                                       # TransformStamped
		o = msg.transform.rotation
		var t = msg.transform.translation
		pos = Vector3(t.x, t.y, t.z)
		nombre = String(msg.child_frame_id).trim_prefix("/")
	else:                                                        # QuaternionStamped
		o = msg.quaternion
	var q := Quaternion(o.x, o.y, o.z, o.w)
	if not (pos.is_finite() and is_finite(q.x) and is_finite(q.y) and is_finite(q.z) and is_finite(q.w)):
		return null
	if q.length_squared() < 1e-6:
		return null
	q = q.normalized()
	rpy_grados = Vector3(atan2(2.0 * (q.w * q.x + q.y * q.z), 1.0 - 2.0 * (q.x * q.x + q.y * q.y)),
			asin(clampf(2.0 * (q.w * q.y - q.z * q.x), -1.0, 1.0)),
			atan2(2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z))) * (180.0 / PI)
	return [Transform3D(Basis(rclgd.ros_to_godot_quat(q)), rclgd.ros_to_godot_vector(pos)), nombre]


func _pintar(d) -> void:
	if _ejes == null:
		return
	var t: Transform3D = d[0]
	hijo = d[1]
	_ejes.transform = t.scaled_local(Vector3.ONE * largo)
	_ejes.visible = true
	if _flecha != null:
		var f = Prim.flecha_hacia(-t.origin) if hijo != "" else null     # del hijo al padre (origen del nodo)
		_flecha.visible = f != null
		if f != null:
			_flecha.transform = Transform3D((f as Transform3D).basis, t.origin)
	if mostrar_nombre and hijo != "" and visor != null and visor.texto != null:
		visor.texto.poner(name, marco * t.origin, hijo)


func _caducar() -> void:
	super._caducar()
	if visor != null and visor.texto != null:
		visor.texto.quitar(name)


func _coste() -> Dictionary:
	var n := 2 if mostrar_flecha else 1
	return {"instancias": n, "triangulos": Prim.TRIANGULOS[Prim.EJES] + (Prim.TRIANGULOS[Prim.FLECHA] if n == 2 else 0),
			"quads": 0}
