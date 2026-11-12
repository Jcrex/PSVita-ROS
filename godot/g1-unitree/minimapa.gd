extends Control
## Minimapa 2D (abajo a la derecha) del modo «ros»: el mapa de la casa llega por teselas desde el relay del PC
## (`docker/vita-ros.sh relay`, doc 27) y la pose del robot por /vita/pose2d. Todo en 2D (CanvasItem), la ruta
## validada del port; el mapa es una ImageTexture actualizada como mucho 4 veces por segundo.

const Relay := preload("res://comun/vita_relay.gd")

var relay := Relay.new()
var pose := {}
var path := PackedVector2Array()
var escala := 1.0              # píxeles de pantalla por píxel de mapa


func _ready() -> void:
	relay.mapa_cambiado.connect(_ajustar)
	visible = false


func _ajustar() -> void:
	if relay.ancho > 0:
		escala = minf(size.x / relay.ancho, size.y / relay.alto)
	visible = true


func on_pose(m) -> void:
	pose = Relay.pose2d(m)


func on_path(m) -> void:
	path = Relay.path_puntos(m)


func _process(_dt: float) -> void:
	if visible:
		relay.actualizar_textura()
		queue_redraw()


func _draw() -> void:
	if relay.mapa_tex == null:
		return
	var tam := Vector2(relay.ancho, relay.alto) * escala
	draw_rect(Rect2(Vector2(-3, -3), tam + Vector2(6, 6)), Color(0, 0, 0, 0.6))
	draw_texture_rect(relay.mapa_tex, Rect2(Vector2.ZERO, tam), false)
	if path.size() >= 2:
		var pts := PackedVector2Array()
		for p in path:
			pts.append(relay.mundo_a_pixel(p) * escala)
		draw_polyline(pts, Color(0.2, 0.8, 0.3), 2.0)
	if not pose.is_empty():
		var c: Vector2 = relay.mundo_a_pixel(pose["pos"]) * escala
		var yaw: float = pose["yaw"]
		var f := Vector2(cos(yaw), -sin(yaw))          # norte arriba: y de ROS hacia arriba en pantalla
		var l := Vector2(-f.y, f.x)
		draw_colored_polygon(PackedVector2Array([c + f * 9, c - f * 5 + l * 5, c - f * 5 - l * 5]), Color(1, 0.55, 0.1))
	draw_string(ThemeDB.fallback_font, Vector2(2, tam.y + 14), "mapa %d×%d · teselas %d" % [
			relay.ancho, relay.alto, relay.teselas_recibidas], HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
