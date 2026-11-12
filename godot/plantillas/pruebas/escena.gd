extends SceneTree

var _mallas := 0
var _triangulos := 0


func _init() -> void:
	_contar_deferred.call_deferred()


func _contar_deferred() -> void:
	var escena = load("res://main.tscn").instantiate()
	root.add_child(escena)
	await process_frame
	await process_frame
	_contar(escena)
	print("ESCENA_MALLAS ", _mallas)
	print("ESCENA_TRIANGULOS ", _triangulos)
	print("ESCENA_SENSORES ", escena.sensores.size())
	quit()


func _contar(n: Node) -> void:
	if n is MeshInstance3D and n.mesh != null:
		_mallas += 1
		for s in n.mesh.get_surface_count():
			var arrays: Array = n.mesh.surface_get_arrays(s)
			var indices = arrays[Mesh.ARRAY_INDEX]
			if indices != null and indices.size() > 0:
				_triangulos += indices.size() / 3
			else:
				_triangulos += arrays[Mesh.ARRAY_VERTEX].size() / 3
	for hijo in n.get_children():
		_contar(hijo)
