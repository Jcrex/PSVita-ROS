extends "res://comun/visor/herramienta_visor.gd"
## Publish Point (RViz `point_tool.cpp`; doc 36a §4.8.10, ficha hmi#18): al SOLTAR el clic o el toque publica
## `geometry_msgs/PointStamped` en `/clicked_point` (44 B) con `header.frame_id` = marco fijo.
##
## Dónde cae el punto:
##   - en la planta 2D (si `planta` está visible): el suelo (z = 0) bajo el dedo;
##   - en la vista 3D: rayo de física contra las colisiones del mundo editable (doc 35); si no toca nada, el suelo
##     del marco fijo. El robot horneado no tiene colisiones (`godot/g1-unitree/robot/urdf_robot.gd:2`): sobre el
##     robot cae al suelo. RViz usa el selector de profundidad del render; aquí se sustituye por física [I].
## «Single click» (`un_solo_clic`, por defecto true como RViz, `point_tool.cpp:65-68,111-114`): tras publicar la
## herramienta se desactiva (vuelve a «ninguna»). Sin confirmación con ✕: un punto no mueve el robot.

@export var un_solo_clic := true
@export var mascara_colision := 0xFFFFFFFF

var ultimo_ros = null                          # Vector3 ROS del último punto publicado (pruebas y HUD)


static func nombre_herramienta() -> String:
	return "Punto"


func _init() -> void:
	topic = "/clicked_point"
	tipo = "geometry_msgs/msg/PointStamped"


func _entrada(e: InputEvent) -> bool:
	if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
		return false
	if e.pressed:
		return true                            # RViz publica en leftUp
	var g = _punto_godot(e.position)
	if g == null:
		return true
	var p: Vector3 = rclgd.godot_to_ros_vector(g as Vector3)
	var m = RosMsg.from_type(tipo)
	cabecera(m)
	m.point.x = p.x
	m.point.y = p.y
	m.point.z = p.z
	ultimo_ros = p
	publicar(m)
	if un_solo_clic:
		activar(false)
	return true


## Punto de pantalla → punto de la escena en el marco fijo (ejes Godot): física en 3D, si no el suelo.
func _punto_godot(pos: Vector2):
	if planta != null and planta.is_visible_in_tree():
		return suelo_godot(pos)
	var cam: Camera3D = _camara()
	if cam == null:
		return null
	var o := cam.project_ray_origin(pos)
	var fin := o + cam.project_ray_normal(pos) * alcance
	var q := PhysicsRayQueryParameters3D.create(o, fin, mascara_colision)
	var hit: Dictionary = cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.has("position"):
		return _marco().affine_inverse() * (hit["position"] as Vector3)
	return suelo_godot(pos)
