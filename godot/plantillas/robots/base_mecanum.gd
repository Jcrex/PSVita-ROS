extends "res://comun/robots/robot_ros.gd"

@export var radio_rueda := 0.11
@export var distancia_ruedas_x := 0.458
@export var distancia_ruedas_y := 0.47

var angulos_ruedas := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


func velocidades_ruedas() -> PackedFloat32Array:
	var a := (distancia_ruedas_x + distancia_ruedas_y) * 0.5
	var vx := orden_actual.x
	var vy := orden_actual.y
	var w := orden_actual.z
	return PackedFloat32Array([
		(vx - vy - a * w) / radio_rueda,
		(vx + vy + a * w) / radio_rueda,
		(vx + vy - a * w) / radio_rueda,
		(vx - vy + a * w) / radio_rueda])


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	var velocidades := velocidades_ruedas()
	for i in 4:
		angulos_ruedas[i] = wrapf(angulos_ruedas[i] + velocidades[i] * dt, -PI, PI)
