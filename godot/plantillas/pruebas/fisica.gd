extends SceneTree


func _init() -> void:
	_probar.call_deferred()


func _probar() -> void:
	var escena = load("res://main.tscn").instantiate()
	root.add_child(escena)
	var robot: CharacterBody3D = escena.robot
	print("FISICA antes=", robot.global_position)
	await process_frame
	escena.robot.aceptar_teleop_local = false
	var inicio := robot.global_position
	for i in 120:
		await physics_frame
	print("FISICA inicio=", inicio, " final=", robot.global_position, " suelo=", robot.is_on_floor(), " velocidad=", robot.velocity)
	var espacio: PhysicsDirectSpaceState3D = robot.get_world_3d().direct_space_state
	var origen := Vector3(robot.global_position.x, 5.0, robot.global_position.z)
	var query := PhysicsRayQueryParameters3D.create(origen, origen + Vector3.DOWN * 20.0, 1)
	var hit := espacio.intersect_ray(query)
	print("FISICA rayo=", hit)
	print("FISICA layer=", robot.collision_layer, " mask=", robot.collision_mask)
	for i in robot.get_slide_collision_count():
		var col := robot.get_slide_collision(i)
		print("FISICA contacto=", col.get_collider(), " en=", col.get_position(), " normal=", col.get_normal())
	for hijo in robot.get_children():
		if hijo is CollisionShape3D and hijo.shape is CapsuleShape3D:
			print("FISICA capsula r=", hijo.shape.radius, " h=", hijo.shape.height, " pos=", hijo.position)
	quit()
