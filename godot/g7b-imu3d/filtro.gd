extends RefCounted
## Filtro complementario: calcula la orientación de la Vita a partir de /vita/imu.
##
## Escrito por el usuario (reto de la lección docs/tutorial/09-godot-visor-3d-imu.md):
##   ángulo = alfa · (ángulo_anterior + ω·dt) + (1 − alfa) · ángulo_según_la_gravedad
## El giroscopio aporta rapidez y suavidad; el acelerómetro corrige la deriva de roll y pitch.
##
## Todo en el sistema de ROS (REP-103): x adelante, y izquierda, z arriba; ángulos en radianes.
##   roll  = giro sobre x (ladear a izquierda o derecha)
##   pitch = giro sobre y (cabecear: el morro sube o baja)
##   yaw   = giro sobre z (girar sobre la mesa)
##
## RefCounted = objeto ligero que Godot borra solo cuando nadie lo usa (no es un nodo de la escena).
## main.gd lo crea con `Filtro.new()` y le pasa cada mensaje.

## Cuánto te fías del giroscopio en cada paso (0..1). 0.98 = 98 % giroscopio, 2 % acelerómetro.
var alfa := 0.98

var roll := 0.0
var pitch := 0.0
var yaw := 0.0


## Se llama con cada mensaje Imu recibido.
##   acel: linear_acceleration en m/s² (en reposo mide +9,8 hacia ARRIBA: la reacción a la gravedad)
##   giro: angular_velocity en rad/s (ya sin sesgo: la tara la hace g7-imu con Triángulo)
##   dt:   segundos desde el mensaje anterior
func actualizar(acel: Vector3, giro: Vector3, dt: float) -> void:
	# Inclinación según la gravedad (solo es fiable si la consola no está acelerando).
	var roll_acel := atan2(acel.y, acel.z)
	var pitch_acel := atan2(-acel.x, sqrt(acel.y ** 2 + acel.z ** 2))

	# Mezcla: el valor de la derecha es el del mensaje ANTERIOR (por eso roll/pitch/yaw viven fuera).
	roll = alfa * (roll + giro.x * dt) + (1.0 - alfa) * roll_acel
	pitch = alfa * (pitch + giro.y * dt) + (1.0 - alfa) * pitch_acel
	# El yaw solo se integra: la gravedad no cambia al girar sobre la mesa, así que deriva (R lo pone a 0).
	yaw = yaw + giro.z * dt


## Vuelve a la posición inicial (tecla R).
func reiniciar() -> void:
	roll = 0.0
	pitch = 0.0
	yaw = 0.0
