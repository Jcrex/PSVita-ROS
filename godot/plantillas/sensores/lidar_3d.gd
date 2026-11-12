extends "res://comun/ros/sensor_base.gd"

const Util = preload("res://comun/ros/util_ros.gd")

@export var anillos := 16
@export var muestras_azimut := 90
@export var elevacion_min := deg_to_rad(-15.0)
@export var elevacion_max := deg_to_rad(15.0)
@export var rango_min := 0.1
@export var rango_max := 20.0
@export_flags_3d_physics var mascara_colision := 1

var _msg: RosMsg


func _init() -> void:
	topic = "/lidar/points"
	tipo = "sensor_msgs/msg/PointCloud2"
	frame_id = "lidar_3d_link"
	hz = 5.0
	hz_xrce = 1.0
	best_effort = false
	solo_pc = true


func _sensor_listo() -> void:
	if contexto.transporte == "xrce":
		anillos = mini(anillos, 8)
		muestras_azimut = mini(muestras_azimut, 30)
	_msg = RosMsg.from_type(tipo)
	_msg.header.frame_id = frame_id
	_msg.height = 1
	_msg.fields = [Util.hacer_campo_nube("x", 0), Util.hacer_campo_nube("y", 4),
		Util.hacer_campo_nube("z", 8), Util.hacer_campo_nube("intensity", 12)]
	_msg.is_bigendian = false
	_msg.point_step = 16
	_msg.is_dense = true


func _publicar() -> void:
	var espacio := get_world_3d().direct_space_state
	var excluir: Array[RID] = []
	if robot is CollisionObject3D:
		excluir.append(robot.get_rid())
	var datos := PackedByteArray()
	datos.resize(anillos * muestras_azimut * 16)
	var n := 0
	for ring in anillos:
		var elev := lerpf(elevacion_min, elevacion_max, float(ring) / maxf(anillos - 1, 1))
		for i in muestras_azimut:
			var az := -PI + TAU * float(i) / muestras_azimut
			var local_ros := Vector3(cos(elev) * cos(az), cos(elev) * sin(az), sin(elev))
			var direccion := global_basis.orthonormalized() * Util.vector_godot(local_ros)
			var query := PhysicsRayQueryParameters3D.create(global_position,
				global_position + direccion * rango_max, mascara_colision, excluir)
			var hit := espacio.intersect_ray(query)
			if hit.is_empty():
				continue
			var distancia := global_position.distance_to(hit.position)
			if distancia < rango_min:
				continue
			var p := Util.vector_ros(global_basis.orthonormalized().inverse() * (hit.position - global_position))
			var offset := n * 16
			datos.encode_float(offset, p.x)
			datos.encode_float(offset + 4, p.y)
			datos.encode_float(offset + 8, p.z)
			datos.encode_float(offset + 12, clampf(1.0 - distancia / rango_max, 0.0, 1.0))
			n += 1
	datos.resize(n * 16)
	_sellar_y_fijar_frame(_msg)
	_msg.width = n
	_msg.row_step = n * 16
	_msg.data = datos
	pub.publish(_msg)
