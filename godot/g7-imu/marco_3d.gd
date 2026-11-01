@tool
extends Control
## Marco3D: rectángulo GUÍA que dice dónde y de qué tamaño se ve el modelo 3D.
##
## ¿Por qué no un SubViewport? El renderizador GXM de la Vita solo dibuja 3D en la pantalla principal:
## los viewports «fuera de pantalla» se ignoran (toolchains/godot4-vita/engine/platform/vita/
## rasterizer_scene_gxm_vita.inc:839-840, «offscreen 3D viewports are not implemented»; también
## GXM_BACKEND.md:47). Así que el 3D ocupa toda la pantalla y main.gd mueve y escala la CÁMARA para
## que el modelo caiga dentro de este rectángulo (_encuadrar_3d).
##
## En el editor se dibuja el borde (para que coordines la interfaz); al ejecutar no se dibuja nada.


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var borde := Color(0.4, 0.8, 1.0, 0.8)
	draw_rect(Rect2(Vector2.ZERO, size), borde, false, 1.0)
	draw_line(Vector2.ZERO, size, Color(borde, 0.3), 1.0)
	draw_line(Vector2(size.x, 0), Vector2(0, size.y), Color(borde, 0.3), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(3, 12), "3D", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, borde)
