extends "res://comun/visor/display_ros_3d.gd"
## Fuerza / tornillo 3D (V5; doc 36a §4.2.6 `tornillo.gd`, V geom#6–8; `fuerza.gd` es el nombre de la sentencia
## W13, doc 36 §10): display «screw» de RViz (`wrench_visual.cpp`). FLECHA lineal (o fuerza, roja) + FLECHA angular
## (o par, amarilla) + ANILLO abierto alrededor del eje angular, a mitad de la flecha y de radio |par|/4.
## Tipos: `Twist`, `TwistStamped`, `AccelStamped`, `WrenchStamped` (en el esquema; las variantes
## `WithCovariance` no). `Twist` sin cabecera (p. ej. `/cmd_vel`) se pinta en `frame_id` (`base_link` por defecto).
## El angular es pseudovector: la flecha va por el eje de giro (regla de la mano derecha). NaN → descartar (RViz
## *Accept NaN* = false). Dato intermedio: `[Vector3 lineal, Vector3 angular]` (ejes Godot, ya escalados).
## Capa «poses»: 3 instancias (24 + 24 + 56 tri); con menos cupo: lineal, angular, anillo.

const Prim = preload("res://comun/visor/primitivas_viz.gd")

@export var escala_lineal := 1.0
@export var escala_angular := 1.0
@export var ocultar_pequenos := true           # RViz *Hide Small Values*
@export var color_lineal := Color(0.8, 0.2, 0.2)
@export var color_angular := Color(0.8, 0.8, 0.2)

var _lin: MeshInstance3D
var _ang: MeshInstance3D
var _anillo: MeshInstance3D


static func nombre_display() -> String:
	return "Fuerza"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["geometry_msgs/msg/WrenchStamped", "geometry_msgs/msg/AccelStamped",
			"geometry_msgs/msg/TwistStamped", "geometry_msgs/msg/Twist"])


func _init() -> void:
	capa = "poses"
	hz = 10.0


func conectar(v) -> void:
	if frame_id == "" and tipo == "geometry_msgs/msg/Twist":
		frame_id = "base_link"                         # Twist no lleva cabecera (doc 36a §4.2.6)
	super.conectar(v)
	if _lin != null:
		return
	if cupo >= 1:
		_lin = _nuevo(Prim.FLECHA, color_lineal)
	if cupo >= 2:
		_ang = _nuevo(Prim.FLECHA, color_angular)
	if cupo >= 3:
		_anillo = _nuevo(Prim.ANILLO, color_angular)


func _nuevo(forma: int, c: Color) -> MeshInstance3D:
	var mi := Prim.instancia(forma, c)
	mi.visible = false
	add_child(mi)
	return mi


func _procesar(msg):
	var t: String = msg.get_ros_interface_name()
	var w := t.contains("Wrench")
	var c = msg
	if t.ends_with("Stamped"):                         # TwistStamped.twist / AccelStamped.accel / WrenchStamped.wrench
		c = msg.get_member("wrench" if w else ("twist" if t.contains("Twist") else "accel"))
	var a = c.get_member("force" if w else "linear")
	var b = c.get_member("torque" if w else "angular")
	var vl := Vector3(a.x, a.y, a.z)
	var va := Vector3(b.x, b.y, b.z)
	if not (vl.is_finite() and va.is_finite()):
		return null
	return [rclgd.ros_to_godot_vector(vl) * escala_lineal, rclgd.ros_to_godot_vector(va) * escala_angular]


func _pintar(d) -> void:
	var umbral := 0.01 if ocultar_pequenos else 1e-6
	var vl: Vector3 = d[0]
	var va: Vector3 = d[1]
	var tl = Prim.flecha_hacia(vl) if vl.length() > umbral else null
	var ta = Prim.flecha_hacia(va) if va.length() > umbral else null
	if _lin != null:
		_lin.visible = tl != null
		if tl != null:
			_lin.transform = tl
	if _ang != null:
		_ang.visible = ta != null
		if ta != null:
			_ang.transform = ta
	if _anillo != null:
		_anillo.visible = ta != null
		if ta != null:
			# El ANILLO unidad (radio 0,5) está en el plano XZ de Godot con eje +Y: se gira para que +Y vaya por el
			# eje angular y se escala a radio |va|/4, centrado a mitad de la flecha.
			var dir := va.normalized()
			var arriba := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
			var b := Basis.looking_at(dir, arriba) * Basis(Vector3.RIGHT, -PI / 2.0)
			_anillo.transform = Transform3D(b.scaled_local(Vector3.ONE * va.length() * 0.5), va * 0.5)


func _coste() -> Dictionary:
	return {"instancias": 3, "triangulos": 2 * Prim.TRIANGULOS[Prim.FLECHA] + Prim.TRIANGULOS[Prim.ANILLO], "quads": 0}
