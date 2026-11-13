extends "res://comun/visor/display_ros_3d.gd"
## Punto 3D (V5; doc 36a §4.2.1, V geom#1): una ESFERA (octaedro, 8 tri) por punto con historial circular (RViz
## *History Length*). Directo en PC y Vita: `PointStamped` = 44 B (cabe en 488). `Point` sin cabecera se pinta en
## `frame_id`. Contraparte que publica: herramienta Publish Point (V7, `/clicked_point`).
## Dato intermedio: Vector3 (ejes de Godot) en el marco del mensaje. Capa «poses» (HMI 4, Viz 16): el historial
## real es min(`historial`, cupo concedido). Las esferas son `top_level`: el historial se queda en el mundo aunque
## el marco se mueva (como RViz).

const Prim = preload("res://comun/visor/primitivas_viz.gd")

@export var radio := 0.1                       # m (RViz 0,2 de diámetro)
@export var historial := 10
@export var color := Color(1.0, 0.0, 1.0)      # magenta, como el defecto de RViz

var _pool: Array[MeshInstance3D] = []
var _i := 0
var ultimo := Vector3.ZERO                      # último punto en el marco fijo (ejes Godot), para pruebas y HUD


static func nombre_display() -> String:
	return "Punto"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["geometry_msgs/msg/PointStamped", "geometry_msgs/msg/Point"])


func _init() -> void:
	capa = "poses"
	hz = 10.0


func conectar(v) -> void:
	super.conectar(v)
	if not _pool.is_empty():
		return
	for k in cupo:
		var e := Prim.instancia(Prim.ESFERA, color)
		e.visible = false
		e.top_level = true
		add_child(e)                                    # sin owner: no se guarda en la escena (doc 35)
		_pool.append(e)


func _procesar(msg):
	var p = msg.point if "point" in msg else msg        # PointStamped o Point suelto
	var v := Vector3(p.x, p.y, p.z)
	return rclgd.ros_to_godot_vector(v) if v.is_finite() else null     # NaN/Inf: ignorar (T2)


func _pintar(pos) -> void:
	if _pool.is_empty():
		return
	ultimo = marco * (pos as Vector3)
	var e := _pool[_i]
	_i = (_i + 1) % _pool.size()
	e.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * radio * 2.0), ultimo)
	e.visible = true


func _coste() -> Dictionary:
	return {"instancias": historial, "triangulos": Prim.TRIANGULOS[Prim.ESFERA] * historial, "quads": 0}
