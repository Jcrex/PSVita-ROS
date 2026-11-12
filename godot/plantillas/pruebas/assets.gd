extends SceneTree


func _init() -> void:
	for ruta in [
		"res://comun/mundo/assets/city/building-type-a.obj",
		"res://comun/mundo/assets/city/building-type-b.obj",
		"res://comun/mundo/assets/city/building-type-c.obj",
		"res://comun/mundo/assets/nature/tree_default.obj",
		"res://comun/mundo/assets/furniture/table.obj",
		"res://comun/mundo/assets/generados/persona.obj",
		"res://comun/mundo/assets/cars/sedan.obj",
		"res://comun/mundo/assets/furniture/chair.obj",
		"res://comun/mundo/assets/furniture/bench.obj",
		"res://comun/mundo/assets/furniture/kitchenCabinet.obj",
		"res://comun/mundo/assets/furniture/bedDouble.obj",
		"res://comun/mundo/assets/furniture/bear.obj",
		"res://comun/mundo/assets/food/burger.obj",
		"res://comun/mundo/assets/city/tree-small.obj",
		"res://comun/mundo/assets/nature/rock_largeA.obj",
	]:
		var m: Mesh = load(ruta)
		print(ruta, " AABB=", m.get_aabb(), " superficies=", m.get_surface_count())
		if ruta.ends_with("persona.obj"):
			var material = m.surface_get_material(0)
			print("PERSONA material=", material, " color=", material.albedo_color, " textura=", material.albedo_texture, " transparencia=", material.transparency)
	quit()
