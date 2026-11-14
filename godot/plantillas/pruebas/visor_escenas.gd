extends SceneTree
## Prueba de host de las escenas de prueba de `godot/visor-ros` (juez Fable, desafíos de la fase V2;
## `docs/ia/workshops/posts/V2-juez-fable.md`):
##   - `banco_v5.tscn` (gate V5): los 10 displays directos de V5 son nodos de la escena, todos suscriben («ok») y
##     caben enteros en los cupos del perfil Viz con la Vita simulada (`en_vita = true`);
##   - `main_viz.tscn` (gate G-W13-M1 en Viz): hereda `main.tscn` con `perfil = VIZ`; el gestor de marcadores recibe
##     32 nodos (12 en `main.tscn`, HMI);
##   - `selector_escena.gd`: orden de la lista, guardar/leer el archivo y rechazo de rutas que no están en la lista.
##
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_escenas.gd

const VisorRos = preload("res://comun/visor/visor_ros.gd")

var fallos := 0
var pruebas := 0


func check(condicion: bool, nombre: String) -> void:
	pruebas += 1
	if not condicion:
		fallos += 1
		push_error(nombre)
	else:
		print("OK ", nombre)


func _init() -> void:
	_correr.call_deferred()


func _correr() -> void:
	RosMsg.load_schema_file(String(ProjectSettings.get_setting("ros/schema_path", "res://ros/schema.rsch")))
	await _probar_banco_v5()
	await _probar_perfiles()
	_probar_selector()
	print("RESULTADO: %d/%d" % [pruebas - fallos, pruebas])
	quit(0 if fallos == 0 else 1)


## Instancia la escena con el visor en `loopback` y la Vita simulada; devuelve [raíz, visor] ya conectado.
func _abrir(ruta: String) -> Array:
	var raiz: Node = load(ruta).instantiate()
	var v: Node = raiz.get_node("VisorRos")
	v.transporte = "loopback"
	v.config_json = ""
	v.reintento_s = 0.0
	v.en_vita = true
	root.add_child(raiz)
	for _i in 60:
		if v.estado != "sin conectar":
			break
		await process_frame
	return [raiz, v]


func _cerrar(raiz: Node) -> void:
	raiz.queue_free()
	await process_frame
	await process_frame


func _probar_banco_v5() -> void:
	var r: Array = await _abrir("res://banco_v5.tscn")
	var v: Node = r[1]
	check(v.perfil == VisorRos.Perfil.VIZ, "banco_v5: perfil Viz")
	check(v.displays.size() == 10, "banco_v5: 10 displays de V5 en la escena (%d)" % v.displays.size())
	var todos_ok := true
	var enteros := true
	for d in v.displays:
		todos_ok = todos_ok and d.estado == "ok"
		var c: Dictionary = d._coste()
		var pide: int = c.get("instancias", 0) if d is Node3D else c.get("quads", 0)
		enteros = enteros and d.cupo == pide
		if d.estado != "ok" or d.cupo != pide:
			print("  ", d.name, ": ", d.estado, " cupo ", d.cupo, " de ", pide)
	check(todos_ok, "banco_v5: todos los displays suscriben en directo en la Vita simulada")
	check(enteros, "banco_v5: cada display recibe todo su cupo (perfil Viz)")
	var cupos: Dictionary = VisorRos.CUPOS[VisorRos.Perfil.VIZ]
	check(v._usados.get("poses", 0) == 12 and v._usados.get("poses", 0) <= cupos["poses"],
			"banco_v5: capa poses = 12 de 16 (%d)" % v._usados.get("poses", 0))
	check(v._usados.get("marcadores", 0) == 8, "banco_v5: capa marcadores = 8 de 32")
	check(v._usados.get("sensores_2d", 0) <= cupos["sensores_2d"],
			"banco_v5: sensores_2d dentro del cupo (%d)" % v._usados.get("sensores_2d", 0))
	check(not v.usa_compactos() or not v.displays[0].canal.compacto, "banco_v5: sin relay (todo directo)")
	check(raiz_tiene_selector(r[0]), "banco_v5: lleva SelectorEscena")
	await _cerrar(r[0])


func raiz_tiene_selector(raiz: Node) -> bool:
	return raiz.has_node("SelectorEscena") and raiz.get_node("SelectorEscena").has_method("siguiente")


func _probar_perfiles() -> void:
	var r: Array = await _abrir("res://main_viz.tscn")
	var v: Node = r[1]
	var m: Node = v.get_node("Marcadores")
	check(v.perfil == VisorRos.Perfil.VIZ, "main_viz: perfil Viz heredando main.tscn")
	check(m.cupo == 32 and m.tope() == 32, "main_viz: Marcadores con 32 nodos (cupo %d, tope %d)" % [m.cupo, m.tope()])
	check(v.get_node("TF").cupo == 32, "main_viz: TF con 32 marcos (%d)" % v.get_node("TF").cupo)
	check(raiz_tiene_selector(r[0]), "main_viz: lleva SelectorEscena (heredado)")
	await _cerrar(r[0])
	r = await _abrir("res://main.tscn")
	v = r[1]
	m = v.get_node("Marcadores")
	check(v.perfil == VisorRos.Perfil.HMI and m.cupo == 12 and m.tope() == 12,
			"main: perfil HMI, Marcadores con 12 nodos (cupo %d)" % m.cupo)
	check(raiz_tiene_selector(r[0]), "main: lleva SelectorEscena")
	await _cerrar(r[0])


func _probar_selector() -> void:
	var s: Node = load("res://selector_escena.gd").new()
	s.archivo = "user://prueba_visor_escena.txt"
	check(s.siguiente("res://main.tscn") == "res://main_viz.tscn"
			and s.siguiente("res://main_viz.tscn") == "res://banco_v5.tscn"
			and s.siguiente("res://banco_v5.tscn") == "res://main.tscn", "selector: ciclo main → main_viz → banco_v5 → main")
	check(s.siguiente("res://otra.tscn") == "res://main.tscn", "selector: escena desconocida → la primera")
	var existen := true
	for e in s.escenas:
		existen = existen and ResourceLoader.exists(e)
	check(existen, "selector: todas las escenas de la lista existen")
	check(s.guardar("res://banco_v5.tscn") and s.leer() == "res://banco_v5.tscn", "selector: guardar y leer")
	s.guardar("res://no_esta.tscn")
	check(s.leer() == "", "selector: una ruta fuera de la lista no se carga")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(s.archivo))
	check(s.leer() == "", "selector: sin archivo no hay salto")
	s.free()
