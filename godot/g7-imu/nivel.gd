extends Control
## Nivel de burbuja: un círculo con una bola que se mueve según la gravedad que mide la Vita.
## Es un nodo Control con su propio script: main.gd solo le da el dato (`nivel.gravedad = ...`)
## y este nodo decide cómo dibujarlo. Separar así cada pieza es la forma normal de trabajar en Godot.
##
## HIPÓTESIS: el signo de los ejes del sensor. Si la bola se mueve al revés de lo esperado,
## cambia los signos en `_draw` (validar en hardware; lección docs/tutorial/08, reto 2).

# Variable con «setter»: cada vez que alguien escribe `gravedad = algo`, se ejecuta el bloque set,
# que guarda el valor y pide redibujar (queue_redraw hace que Godot llame a _draw en este fotograma).
var gravedad := Vector3.ZERO:
	set(valor):
		gravedad = valor
		queue_redraw()


func _draw() -> void:
	var centro := size / 2.0
	var radio := minf(size.x, size.y) / 2.0 - 4.0
	draw_arc(centro, radio, 0.0, TAU, 64, Color(0.5, 0.55, 0.65), 2.0)
	draw_arc(centro, radio * 0.5, 0.0, TAU, 48, Color(0.3, 0.33, 0.4), 1.0)
	draw_line(centro - Vector2(radio, 0), centro + Vector2(radio, 0), Color(0.3, 0.33, 0.4), 1.0)
	draw_line(centro - Vector2(0, radio), centro + Vector2(0, radio), Color(0.3, 0.33, 0.4), 1.0)

	var largo := gravedad.length()
	if largo < 0.0001:
		return   # sin dato todavía
	var g := gravedad / largo   # vector unitario: solo nos importa la dirección
	# En pantalla la y crece hacia ABAJO, por eso el signo menos en la y.
	var bola := centro + Vector2(g.x, -g.y) * radio
	draw_circle(bola, 14.0, Color(1.0, 0.75, 0.2))
	draw_string(ThemeDB.fallback_font, Vector2(4, size.y - 4), "gravedad (sensor x, y)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.65, 0.75))
