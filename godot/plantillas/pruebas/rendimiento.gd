extends SceneTree

var segundos := 10
var muestras: Array[int] = []


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("segundos="):
			segundos = maxi(2, arg.substr(9).to_int())
	_iniciar.call_deferred()


func _iniciar() -> void:
	var escena = load("res://main.tscn").instantiate()
	root.add_child(escena)
	for i in segundos:
		await create_timer(1.0).timeout
		muestras.append(Engine.get_frames_per_second())
	var ordenadas := muestras.duplicate()
	ordenadas.sort()
	var mediana := 0
	if not ordenadas.is_empty():
		mediana = ordenadas[int(ordenadas.size() / 2)]
	var info: Dictionary = rclgd.get_transport_info()
	var tasas := {}
	var publicados := {}
	for nombre in escena.sensores:
		tasas[nombre] = escena.sensores[nombre].get("hz")
		publicados[nombre] = escena.sensores[nombre].get("mensajes_publicados")
	var resumen := {
		"tasas_configuradas": tasas,
		"mensajes_por_sensor": publicados,
		"fps_muestras": muestras,
		"fps_mediana": mediana,
		"be_pending": info.get("be_pending", 0),
		"be_dropped": info.get("be_dropped", 0),
		"reliable_pending": info.get("reliable_pending", 0),
		"reliable_dropped": info.get("reliable_dropped", 0),
		"reliable_full": info.get("reliable_full", 0),
		"writes": info.get("writes", 0),
		"write_bytes": info.get("write_bytes", 0),
		"read_packets": info.get("read_packets", 0),
		"topic_dropped": info.get("topic_dropped", 0),
		"sensores": escena.sensores.size(),
	}
	print("RENDIMIENTO_RESUMEN ", JSON.stringify(resumen))
	quit()
