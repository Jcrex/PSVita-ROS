extends "res://comun/ros/sensor_base.gd"

@export var muestras := 270
@export var muestras_vita := 60
@export var angulo_min := -2.1
@export var angulo_max := 2.1
@export var rango_min := 0.05
@export var rango_max := 10.0
@export var rayos_por_fotograma := 4096
@export var rayos_por_fotograma_vita := 30
@export_flags_3d_physics var mascara_colision := 1
@export var topic_compacto := ""
@export var publicar_estandar_en_vita := true

var _msg: RosMsg
var _compacto: RosMsg
var _pub_compacto: RosPublisher
var _rangos := PackedFloat32Array()
var _indice := 0
var _scan_activo := true
var _scan_listo := false
var _secuencia := 0
var _n := 0
var _presupuesto := 4096


func _init() -> void:
	topic = "/scan"
	tipo = "sensor_msgs/msg/LaserScan"
	frame_id = "laser_link"
	hz = 15.0
	hz_vita = 5.0
	hz_xrce = 2.0


func _qos_best_effort() -> bool:
	return _en_vita


func _sensor_listo() -> void:
	_n = muestras_vita if _en_vita else muestras
	_presupuesto = rayos_por_fotograma_vita if _en_vita else rayos_por_fotograma
	_rangos.resize(_n)
	_msg = RosMsg.from_type(tipo)
	_msg.header.frame_id = frame_id
	_msg.angle_min = angulo_min
	_msg.angle_max = angulo_max
	_msg.angle_increment = (angulo_max - angulo_min) / maxf(_n - 1, 1)
	_msg.range_min = rango_min
	_msg.range_max = rango_max
	_msg.scan_time = 1.0 / hz
	_msg.time_increment = _msg.scan_time / maxf(_n, 1)
	_msg.intensities = PackedFloat32Array()
	if topic_compacto != "":
		_compacto = RosMsg.from_type("std_msgs/msg/Int16MultiArray")
		_pub_compacto = contexto.publicador(topic_compacto, "std_msgs/msg/Int16MultiArray", _n <= 118)


func _actualizar_sensor(_dt: float) -> void:
	if not _scan_activo or _scan_listo:
		return
	var espacio := get_world_3d().direct_space_state
	var excluir: Array[RID] = []
	if robot is CollisionObject3D:
		excluir.append(robot.get_rid())
	var limite := mini(_indice + _presupuesto, _n)
	while _indice < limite:
		var a := angulo_min + (_angulo_incremento() * _indice)
		var local := Vector3(-sin(a), 0.0, -cos(a))
		var destino := global_position + global_basis.orthonormalized() * local * rango_max
		var query := PhysicsRayQueryParameters3D.create(global_position, destino, mascara_colision, excluir)
		var hit := espacio.intersect_ray(query)
		var distancia := rango_max
		if not hit.is_empty():
			distancia = clampf(global_position.distance_to(hit.position), rango_min, rango_max)
		_rangos[_indice] = distancia
		_indice += 1
	if _indice >= _n:
		_scan_listo = true


func _listo_para_publicar() -> bool:
	return _scan_listo


func _angulo_incremento() -> float:
	return (angulo_max - angulo_min) / maxf(_n - 1, 1)


func _publicar() -> void:
	if not _en_vita or publicar_estandar_en_vita:
		_sellar_y_fijar_frame(_msg)
		_msg.ranges = _rangos.duplicate()
		pub.publish(_msg)
	if _pub_compacto != null:
		var datos := PackedInt32Array([_secuencia, int(round(rad_to_deg(angulo_min) * 100.0)),
			int(round(rad_to_deg(_angulo_incremento()) * 100.0)), _n])
		for r in _rangos:
			datos.append(int(round(r * 100.0)) if is_finite(r) else 0)
		_compacto.data = datos
		_pub_compacto.publish(_compacto)
	_secuencia += 1
	_scan_listo = false
	_indice = 0
