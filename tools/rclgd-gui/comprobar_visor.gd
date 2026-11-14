extends SceneTree
## Comprobación SIN pantalla del visor con rclgd (doc 37 §5.1). `tools/rclgd-gui.sh puente` la copia al proyecto
## puente como res://comprobar_rclgd.gd. Carga UNA escena del visor, la deja correr unos segundos y vuelca, por
## display: topic, tipo abierto, estado, mensajes recibidos y mostrados. Una escena por proceso (rclgd.shutdown()
## al salir de la escena y otro init() en el mismo proceso no es lo que se quiere probar aquí).
##
##   tools/rclgd-gui.sh comprobar [escena] [segundos]
##   (= godot --headless --path <puente> --script res://comprobar_rclgd.gd -- res://main_pc.tscn 8)
##
## Verde: «[visor] ros_listo=true», ningún SCRIPT ERROR y recibidos > 0 en los displays cuyo topic publica la
## fuente lanzada. La última línea es «[comprobar] FIN <escena> displays=N con_datos=M».

const CLASES := ["RosSensorMsgsLaserScan", "RosNavMsgsOccupancyGrid", "RosVisualizationMsgsMarkerArray",
		"RosVisualizationMsgsInteractiveMarkerUpdate", "RosOctomapMsgsOctomap", "RosGridMapMsgsGridMap",
		"RosVisionMsgsDetection2dArray", "RosDiagnosticMsgsDiagnosticArray"]

var escena := "res://main_pc.tscn"
var segundos := 8.0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		escena = a[0]
	if a.size() > 1:
		segundos = float(a[1])
	_correr.call_deferred()


func _correr() -> void:
	print("[comprobar] Godot %s, rclgd=%s, escena %s, %.0f s" % [Engine.get_version_info().string,
			Engine.has_singleton("rclgd"), escena, segundos])
	for c in CLASES:
		print("[clase] %s %s" % [c, "sí" if ClassDB.class_exists(c) else "NO"])
	var ps = load(escena)
	if ps == null:
		print("[comprobar] FALLO: no carga %s" % escena)
		quit(1)
		return
	var raiz: Node = ps.instantiate()
	root.add_child(raiz)
	await create_timer(segundos).timeout
	var visor := _buscar_visor(raiz)
	if visor == null:
		print("[comprobar] FALLO: sin VisorRos en %s" % escena)
		quit(1)
		return
	var tf = visor.get("tf")
	var tf_txt := "null"
	if tf != null:
		tf_txt = tf.get_class()
		if tf.get_script() != null:
			tf_txt += " (" + String(tf.get_script().resource_path).get_file() + ")"
	print("[visor] ros_listo=%s estado=«%s» compacto=%s tf=%s" % [visor.ros_listo, visor.estado,
			visor.usa_compactos(), tf_txt])
	var n := 0
	var con := 0
	for d in _displays(raiz):
		n += 1
		var c = d.get("canal")
		var rec: int = c.recibidos if c != null else -1
		if rec > 0:
			con += 1
		print("[display] %-28s %-34s %-44s estado=«%s» recibidos=%d mostrados=%d hz=%.1f" % [d.name,
				String(d.get("topic")), c.tipo_abierto if c != null else "", d.get("estado"), rec,
				c.mostrados if c != null else -1, c.hz_medido if c != null else 0.0])
		if "ims" in d:   # marcadores interactivos (V14): estado inicial por el servicio get_interactive_markers
			if d.ims.size() > 0:
				con += 1
			print("[im] con_servicio=%s estados_pedidos=%d marcadores=%s seq=%d huecos=%d" % [d.con_servicio,
					d.estados_pedidos, d.ims.keys(), d.seq, d.huecos])
	for e in _con_metodo(raiz, "tiene_grafo"):   # ExploradorTopics (V12): en el PC, descubrimiento por el grafo
		print("[explorador] tiene_grafo=%s desde_grafo=%s topics=%d: %s" % [e.tiene_grafo(), e.desde_grafo,
				e.topics.size(), ", ".join(PackedStringArray(e.topics.keys().slice(0, 12)))])
	print("[comprobar] FIN %s displays=%d con_datos=%d" % [escena, n, con])
	raiz.queue_free()
	await process_frame
	quit(0)


func _buscar_visor(n: Node) -> Node:
	if "displays" in n and "contexto" in n:
		return n
	for h in n.get_children():
		var r := _buscar_visor(h)
		if r != null:
			return r
	return null


func _con_metodo(n: Node, metodo: String) -> Array:
	var r: Array = []
	if n.has_method(metodo):
		r.append(n)
	for h in n.get_children():
		r.append_array(_con_metodo(h, metodo))
	return r


func _displays(n: Node) -> Array:
	var r: Array = []
	if "canal" in n and "estado" in n:
		r.append(n)
	for h in n.get_children():
		r.append_array(_displays(h))
	return r
