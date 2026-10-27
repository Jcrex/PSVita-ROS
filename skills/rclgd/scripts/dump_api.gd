extends SceneTree
## dump_api.gd — vuelca la API REAL de las clases de rclgd instaladas (o de
## ros2_vita en un Godot que lo traiga compilado), leída de ClassDB.
## Sirve para comprobar que la referencia de la skill coincide con la versión
## que hay en la máquina.
##
## SIN VERIFICAR: escrito sin un Godot disponible (validar en el PC).
##
## Uso (dentro de un proyecto con la extensión rclgd cargada):
##   ros2 run rclgd godot --headless --path <proyecto> --script <ruta>/dump_api.gd
## Opcional:  -- --prefix=Ros     (prefijo de clases a volcar; por defecto "Ros" y "rclgd")

func _initialize() -> void:
	var prefix := "Ros"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--prefix="):
			prefix = a.trim_prefix("--prefix=")
	var classes: Array[String] = []
	for c in ClassDB.get_class_list():
		if c.begins_with(prefix) or c == "rclgd":
			classes.append(c)
	classes.sort()
	print("# API volcada de ClassDB (Godot %s)" % Engine.get_version_info().string)
	for c in classes:
		print("\n## %s (hereda de %s)" % [c, ClassDB.get_parent_class(c)])
		for m in ClassDB.class_get_method_list(c, true):
			if String(m.name).begins_with("_"):
				continue
			var args := PackedStringArray()
			for arg in m.args:
				args.append("%s: %s" % [arg.name, _type(arg)])
			print("- %s(%s) -> %s" % [m.name, ", ".join(args), _type(m["return"])])
		for s in ClassDB.class_get_signal_list(c, true):
			print("- señal %s" % s.name)
		for p in ClassDB.class_get_property_list(c, true):
			if p.usage & PROPERTY_USAGE_EDITOR or p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				print("- propiedad %s: %s" % [p.name, _type(p)])
		for k in ClassDB.class_get_integer_constant_list(c, true):
			print("- const %s = %d" % [k, ClassDB.class_get_integer_constant(c, k)])
	quit(0)


func _type(d: Dictionary) -> String:
	if d.has("class_name") and String(d.class_name) != "":
		return String(d.class_name)
	return type_string(int(d.get("type", TYPE_NIL)))
