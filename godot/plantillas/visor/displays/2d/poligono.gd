extends "res://comun/visor/display_ros_2d.gd"
## Polígono en planta (V5; doc 36a §4.2.9, V geom#11): contorno cerrado con `draw_polyline` (1 comando, H17) y
## relleno opcional `draw_colored_polygon`. Topic típico: `/local_costmap/published_footprint` (huella de Nav2,
## casi estática: solo se redibuja si cambia la forma). `PolygonStamped` = 28 + 12·n B ⇒ n ≤ 38 cabe en directo.
## Dato intermedio: PackedVector2Array (m, marco del mensaje). Cupo: `max_puntos` + 1 *quads*.

@export var color := Color(0.2, 0.9, 0.3)
@export var relleno := false
@export var max_puntos := 38                    # lo que cabe en un datagrama de 488 B

var _pts := PackedVector2Array()
var _px := PackedVector2Array()


static func nombre_display() -> String:
	return "Poligono"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["geometry_msgs/msg/PolygonStamped", "geometry_msgs/msg/Polygon"])


func _init() -> void:
	hz = 2.0


func _procesar(msg):
	var poli = msg.polygon if "polygon" in msg else msg
	var out := PackedVector2Array()
	for p in poli.points:
		var q := Vector2(p.x, p.y)
		if not q.is_finite():
			return null                                 # T2: un vértice inválido invalida el contorno
		out.append(q)
		if out.size() >= max_puntos:
			break
	if out == _pts and not _px.is_empty():
		return null                                     # sin cambio de forma: no redibujar
	return out


func _pintar(pts) -> void:
	_pts = pts
	_px.resize(_pts.size())
	for i in _pts.size():
		_px[i] = px(_pts[i])
	queue_redraw()


func _draw() -> void:
	if _px.size() < 2:
		return
	if relleno and _px.size() >= 3 and not Geometry2D.triangulate_polygon(_px).is_empty():
		draw_colored_polygon(_px, Color(color, 0.3))   # solo si triangula (evita «Invalid polygon» con autocortes)
	var cerrado := _px.duplicate()
	cerrado.append(_px[0])
	draw_polyline(cerrado, color, -1.0)


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": max_puntos + (2 if relleno else 0)}
