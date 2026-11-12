extends "res://comun/ros/sensor_base.gd"

const VC1 = preload("res://comun/ros/vc1.gd")

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
var _barriendo := false
var _scan_listo := false
var _n := 0
var _presupuesto := 4096
var _incremento := 0.0
var _angulo_max_real := 0.0
var _stamp_barrido   # sello del primer rayo del barrido en curso (revisión R2-A1)
## Último barrido completo, para quien lo lea en memoria (mapeo_2d, revisión R4-C9 / R2-M9).
var scans_completos := 0
var rangos_listos := PackedFloat32Array()
var transform_listo := Transform3D.IDENTITY
var _stamp_listo


func _init() -> void:
	topic = "/scan"
	tipo = "sensor_msgs/msg/LaserScan"
	frame_id = "laser_link"
	hz = 15.0
	hz_vita = 5.0
	hz_xrce = 2.0


func _qos_best_effort() -> bool:
	return _en_vita


func _usa_publicador_estandar() -> bool:
	return not _en_vita or publicar_estandar_en_vita


func _sensor_listo() -> void:
	_n = muestras_vita if _en_vita else muestras
	_presupuesto = maxi(1, rayos_por_fotograma_vita if _en_vita else rayos_por_fotograma)
	_rangos.resize(_n)
	# Barrido de 360°: el último rayo no puede repetir la dirección del primero (revisión R2-B1).
	if angulo_max - angulo_min >= TAU - 1e-3:
		_incremento = TAU / maxf(_n, 1)
	else:
		_incremento = (angulo_max - angulo_min) / maxf(_n - 1, 1)
	_angulo_max_real = angulo_min + _incremento * maxf(_n - 1, 0)
	_msg = RosMsg.from_type(tipo)
	_msg.header.frame_id = frame_id
	_msg.angle_min = angulo_min
	_msg.angle_max = _angulo_max_real
	_msg.angle_increment = _incremento
	_msg.range_min = rango_min
	_msg.range_max = rango_max
	_msg.scan_time = 1.0 / hz
	_msg.time_increment = _msg.scan_time / maxf(_n, 1)
	_msg.intensities = PackedFloat32Array()
	if topic_compacto != "":
		_compacto = RosMsg.from_type("std_msgs/msg/Int16MultiArray")
		# VC/1: el compacto se diezma a ≤ 180 rayos (≤ 384 B de CDR), así que siempre cabe en best effort.
		_pub_compacto = contexto.publicador(topic_compacto, "std_msgs/msg/Int16MultiArray", true)


func _actualizar_sensor(dt: float) -> void:
	if _scan_listo:
		return
	if not _barriendo:
		# R2-A1: antes el barrido empezaba justo DESPUÉS de publicar y esperaba un periodo entero (a 2 Hz,
		# ≈ 0,48 s de antigüedad). Ahora empieza cuando faltan los fotogramas justos para terminarlo antes de
		# la próxima publicación, de modo que los datos tienen como mucho ceil(n/presupuesto) − 1 fotogramas.
		var fotogramas := ceili(float(_n) / float(_presupuesto))
		if hz > 0.0 and _acumulado + fotogramas * dt < 1.0 / hz:
			return
		_barriendo = true
		_indice = 0
		_stamp_barrido = contexto.nodo.now()
	var espacio := get_world_3d().direct_space_state
	var excluir: Array[RID] = []
	if robot is CollisionObject3D:
		excluir.append(robot.get_rid())
	var base := global_basis.orthonormalized()
	var limite := mini(_indice + _presupuesto, _n)
	while _indice < limite:
		var a := angulo_min + _incremento * _indice
		var local := Vector3(-sin(a), 0.0, -cos(a))
		var destino := global_position + base * local * rango_max
		var query := PhysicsRayQueryParameters3D.create(global_position, destino, mascara_colision, excluir)
		var hit := espacio.intersect_ray(query)
		# REP-117 (revisión R2-M8): sin retorno = +Inf y demasiado cerca = -Inf; antes se enviaba range_max o
		# se recortaba a range_min (obstáculo falso pegado al sensor).
		var distancia := INF
		if not hit.is_empty():
			distancia = global_position.distance_to(hit.position)
			if distancia < rango_min:
				distancia = -INF
		_rangos[_indice] = distancia
		_indice += 1
	if _indice >= _n:
		_barriendo = false
		_scan_listo = true
		rangos_listos = _rangos.duplicate()
		transform_listo = global_transform
		_stamp_listo = _stamp_barrido
		scans_completos += 1


func _listo_para_publicar() -> bool:
	return _scan_listo


## Último barrido completo en memoria (sin ida y vuelta por la red): mapeo_2d lo lee de su sensor padre.
func ultimo_scan() -> Dictionary:
	return {"seq": scans_completos, "rangos": rangos_listos, "transform": transform_listo,
		"angulo_min": angulo_min, "incremento": _incremento, "rango_min": rango_min, "rango_max": rango_max}


func _publicar() -> void:
	if pub != null:
		_msg.header.stamp = _stamp_listo   # sello del barrido, no del instante de publicación (R2-A1)
		_msg.header.frame_id = frame_id
		_msg.ranges = rangos_listos
		pub.publish(_msg)
	if _pub_compacto != null:
		# VC/1: seq con máscara 0x7FFF (R2-B8) y 0 = sin dato, también sin impacto (R4 §1.1).
		_compacto.data = VC1.empaquetar_scan(rangos_listos, angulo_min, _incremento, rango_min, rango_max,
			scans_completos)
		_pub_compacto.publish(_compacto)
	_scan_listo = false
