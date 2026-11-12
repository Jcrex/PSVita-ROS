extends "res://comun/ros/sensor_base.gd"

@export var rango_min := 0.05
@export var rango_max := 8.0
@export var campo_visual := deg_to_rad(20.0)
@export var direccion_ros := Vector3(1.0, 0.0, 0.0)
@export var infrarrojo := false
@export_flags_3d_physics var mascara_colision := 1

var _msg: RosMsg


func _init() -> void:
	topic = "/range"
	tipo = "sensor_msgs/msg/Range"
	frame_id = "range_link"
	hz = 10.0
	hz_vita = 5.0
	hz_xrce = 2.0


func _sensor_listo() -> void:
	_msg = RosMsg.from_type(tipo)
	_msg.header.frame_id = frame_id
	_msg.radiation_type = 1 if infrarrojo else 0
	_msg.field_of_view = campo_visual
	_msg.min_range = rango_min
	_msg.max_range = rango_max


func _publicar() -> void:
	var direccion := global_basis.orthonormalized() * rclgd.ros_to_godot_vector(direccion_ros.normalized())
	var excluir: Array[RID] = []
	if robot is CollisionObject3D:
		excluir.append(robot.get_rid())
	var query := PhysicsRayQueryParameters3D.create(global_position,
		global_position + direccion * rango_max, mascara_colision, excluir)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_sellar_y_fijar_frame(_msg)
	_msg.range = clampf(global_position.distance_to(hit.position), rango_min, rango_max) if not hit.is_empty() else rango_max + 1.0
	pub.publish(_msg)
