@tool
extends Control
## Nivel: un círculo con una bola que se comporta como una CANICA: rueda hacia el lado más bajo
## de la consola. main.gd solo le da el dato (`nivel.gravedad = ...`) y este nodo decide cómo dibujarlo.
##
## @tool = este script también se ejecuta DENTRO DEL EDITOR. Así el círculo se ve en el lienzo 2D
## mientras compones la interfaz (antes solo aparecía al ejecutar). En el editor la bola se dibuja
## en el centro, como muestra.
##
## Todo se dibuja proporcional a `size`: si cambias el tamaño del nodo en el editor, se reescala solo.
##
## Dato de entrada (2026-11-01, optimización O4): la aceleración ya en ejes ROS y suavizada
## (antes era basicOrientation, que solo vale −1/0/1 y hacía que la bola fuera a saltos).

## Por debajo de este cambio (en m/s²) no se redibuja: ahorra trabajo con la consola quieta.
const UMBRAL := 0.02

var gravedad := Vector3.ZERO:
	set(valor):
		if valor.distance_to(gravedad) < UMBRAL:
			return
		gravedad = valor
		queue_redraw()


func _draw() -> void:
	var centro := size / 2.0
	var radio := minf(size.x, size.y) / 2.0 - 2.0
	var linea := Color(0.3, 0.33, 0.4)
	draw_arc(centro, radio, 0.0, TAU, 48, Color(0.5, 0.55, 0.65), 1.5)
	draw_arc(centro, radio * 0.5, 0.0, TAU, 32, linea, 1.0)
	draw_line(centro - Vector2(radio, 0), centro + Vector2(radio, 0), linea, 1.0)
	draw_line(centro - Vector2(0, radio), centro + Vector2(0, radio), linea, 1.0)

	var bola_radio := radio * 0.18
	var largo := gravedad.length()
	if largo < 0.0001:
		if Engine.is_editor_hint():
			draw_circle(centro, bola_radio, Color(1.0, 0.75, 0.2))   # muestra para el editor
		return
	var g := gravedad / largo
	# ROS: x adelante (gatillos, ARRIBA en la pantalla), y izquierda (cruceta).
	# Levantar los gatillos ⇒ g.x > 0 ⇒ la canica baja (+y en pantalla).
	# Levantar la cruceta   ⇒ g.y > 0 ⇒ la canica va a la derecha (+x en pantalla).
	var bola := centro + Vector2(g.y, g.x) * radio
	draw_circle(bola, bola_radio, Color(1.0, 0.75, 0.2))
