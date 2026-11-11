extends RefCounted
## Filtro complementario «F2»: la misma idea que g7b-imu3d/filtro.gd, pero guardando la orientación
## como una MATRIZ DE GIRO (Basis) en vez de tres ángulos (roll, pitch, yaw).
##
## ¿Por qué? Con ángulos, cerca de pitch = ±90° (la Vita en vertical) roll y yaw se mezclan y el
## filtro se vuelve loco («bloqueo de cardán»). Una Basis no tiene ese problema y gasta menos
## trigonometría (ni atan2 ni construir tres Basis por fotograma).
##
## Escrito por Claude a petición del usuario (2026-11-01); el reto de la lección 10 queda como
## ejercicio de LECTURA: explicar cada paso y responder las preguntas.
##
## Todo en ejes de ROS (REP-103): x adelante (gatillos), y izquierda (cruceta), z arriba (pantalla).
## `orientacion` lleva vectores del CUERPO (la Vita) al MUNDO: orientacion * v_cuerpo = v_mundo.

## Cuánto te fías del giroscopio en cada paso (0..1), igual que en g7b.
var alfa := 0.98

## Orientación actual. Basis.IDENTITY = «sin girar»: la Vita plana con los gatillos al fondo.
var orientacion := Basis.IDENTITY


## Se llama en cada fotograma desde main.gd.
##   acel: m/s², ejes ROS (en reposo ≈ (0, 0, +9,8) con la pantalla arriba)
##   giro: rad/s, ejes ROS, ya sin sesgo (tara con Triángulo)
##   dt:   segundos desde el fotograma anterior
func actualizar(acel: Vector3, giro: Vector3, dt: float) -> void:
	# Paso 1 — GIROSCOPIO (predicción): en este fotograma la Vita giró |giro|·dt radianes alrededor
	# del eje giro/|giro|, medido en ejes del CUERPO ⇒ se multiplica por la DERECHA.
	var w := giro.length()
	if w > 1e-6:
		orientacion = orientacion * Basis(giro / w, w * dt)

	# Paso 2 — ACELERÓMETRO (corrección): «arriba» creído vs medido, los dos en ejes del cuerpo.
	var a := acel.length()
	if a > 1e-6:
		var arriba_creido := orientacion.transposed() * Vector3(0, 0, 1)   # mundo → cuerpo
		var arriba_medido := acel / a
		var eje := arriba_medido.cross(arriba_creido)
		var s := eje.length()                     # = seno del ángulo entre los dos
		if s > 1e-6:
			var angulo := arriba_medido.angle_to(arriba_creido)
			# Una fracción (1 − alfa) del giro que lleva lo medido hasta lo creído. Ese giro C cumple
			# Cᵀ·creído = medido, así que orientacion·C hace que lo «creído» se acerque a lo medido.
			orientacion = orientacion * Basis(eje / s, angulo * (1.0 - alfa))

	# Paso 3 — limpiar el redondeo acumulado (que la matriz siga siendo un giro puro).
	orientacion = orientacion.orthonormalized()


## Vuelve a «sin girar» (botón Círculo). El paso 2 recoloca la inclinación en ~1-2 s.
func reiniciar() -> void:
	orientacion = Basis.IDENTITY
