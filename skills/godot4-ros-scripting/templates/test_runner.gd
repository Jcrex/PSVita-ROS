extends SceneTree
## Plantilla: runner headless mínimo (patrón de rclgd/test/project/runner.gd, MIT).
##   godot --headless --path <proyecto> --script res://test_runner.gd
## Ejecuta cada método test_* de res://tests/test_*.gd; una suite es un Node con `var failures: Array`.
## SIN EJECUTAR en este repo.

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame  # root entra en el árbol tras _initialize
	if not rclgd.ok():
		rclgd.init(PackedStringArray())
	var failed := 0
	var dir := DirAccess.open("res://tests")
	for file in dir.get_files():
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var suite: Node = load("res://tests/" + file).new()
		root.add_child(suite)
		for m in suite.get_method_list():
			if not String(m.name).begins_with("test_"):
				continue
			suite.failures = []
			await suite.call(m.name)
			var ok: bool = suite.failures.is_empty()
			print("%s %s::%s %s" % ["PASS" if ok else "FAIL", file, m.name, "" if ok else str(suite.failures)])
			failed += 0 if ok else 1
		suite.queue_free()
	rclgd.shutdown()
	quit(1 if failed else 0)
