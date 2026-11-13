extends "res://comun/visor/display_ros_3d.gd"
## Vector 3D (V5; doc 36a §4.2.2, V geom#2): FLECHA desde el origen del marco, largo = |v| × `escala`; oculta si
## |v| ≈ 0 (`looking_at` con vector nulo da error, T13). Sin display en RViz de serie. `Vector3Stamped` = 52 B.
## Dato intermedio: Vector3 (ejes de Godot, ya escalado). Una instancia (capa «poses»), 24 tri.

const Prim = preload("res://comun/visor/primitivas_viz.gd")

@export var escala := 1.0
@export var color := Color(0.2, 0.6, 1.0)

var _f: MeshInstance3D
var ultimo := Vector3.ZERO


static func nombre_display() -> String:
	return "Vector"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["geometry_msgs/msg/Vector3Stamped", "geometry_msgs/msg/Vector3"])


func _init() -> void:
	capa = "poses"
	hz = 10.0


func conectar(v) -> void:
	super.conectar(v)
	if cupo > 0 and _f == null:
		_f = Prim.instancia(Prim.FLECHA, color)
		_f.visible = false
		add_child(_f)


func _procesar(msg):
	var a = msg.vector if "vector" in msg else msg      # Vector3Stamped o Vector3 suelto
	var v := Vector3(a.x, a.y, a.z)
	return rclgd.ros_to_godot_vector(v) * escala if v.is_finite() else null


func _pintar(v) -> void:
	if _f == null:
		return
	ultimo = v
	var t = Prim.flecha_hacia(v)
	_f.visible = t != null
	if t != null:
		_f.transform = t


func _coste() -> Dictionary:
	return {"instancias": 1, "triangulos": Prim.TRIANGULOS[Prim.FLECHA], "quads": 0}
