extends SceneTree
## Prueba de host de V14 (extras solo PC; doc 36 §10 V14, doc 36a §4.5.3, §4.5.5, §4.6.1, §4.6.6 y §4.7.5;
## ADR 0013, displays `solo_pc`). Transporte `loopback`. Dos modos:
##   - `--headless` (como las demás pruebas del visor): lógica, decodificadores, materiales y registro;
##   - con ventana (binario `.gui` y `--rendering-driver opengl3`): ADEMÁS dibuja con la GPU y compara píxeles
##     (el *shader* de verdad: paleta del mapa, nube desde la textura de bytes, imagen de profundidad/YUV).
## Secciones:
##   1. mapa/costmap con *shader* + paleta 256×1 (sin bucle por celda): índices R8, píxeles = paleta de RViz;
##   2. nube PointCloud2 en GPU: bytes crudos → textura RGBA8 → *vertex shader* (x/y/z/intensity/rgb, mapas de color,
##      diezmado, NaN fuera, big endian, ruta CPU para campos desalineados);
##   3. imagen cruda con *shader*: 16UC1/mono16/32FC1 (profundidad con mapa de color), bayer (demosaico) y YUV;
##   4. cliente de marcadores interactivos: update/erase/seq, controles mover/rotar, feedback FIABLE profundidad 1;
##   5. octomap (decodificador binario) y grid_map (malla de alturas);
##   6. `solo_pc`: en la Vita simulada todos quedan desactivados y el registro no los ofrece.
##
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_pc.gd
##   set GG toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64.gui
##   $GG --rendering-driver opengl3 --path godot/visor-ros --script res://comun/pruebas/visor_pc.gd    # + GPU

const VisorRos = preload("res://comun/visor/visor_ros.gd")
const Texto = preload("res://comun/visor/texto_superpuesto.gd")
const Registro = preload("res://comun/visor/registro_displays.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")
const D := "res://comun/visor/displays/"


class Vigia:
	extends Logger
	var errores := 0
	var ultimo := ""

	func _log_error(_f: String, file: String, _l: int, code: String, rationale: String, _e: bool, tipo: int,
			_b: Array[ScriptBacktrace]) -> void:
		if tipo == ERROR_TYPE_SCRIPT or tipo == ERROR_TYPE_SHADER or (tipo == ERROR_TYPE_ERROR and file.contains("/visor/")):
			errores += 1
			ultimo = "%s: %s %s" % [file, code, rationale]

	func _log_message(m: String, e: bool) -> void:
		if e and (m.contains("SHADER ERROR") or m.contains("Shader compilation failed")):
			errores += 1
			ultimo = m


var fallos := 0
var pruebas := 0
var vigia := Vigia.new()
var gpu := false


func check(condicion: bool, nombre: String) -> void:
	pruebas += 1
	if not condicion:
		fallos += 1
		push_error(nombre)
	else:
		print("OK ", nombre)


func _init() -> void:
	OS.add_logger(vigia)
	_correr.call_deferred()


func _correr() -> void:
	RosMsg.load_schema_file(String(ProjectSettings.get_setting("ros/schema_path", "res://ros/schema.rsch")))
	gpu = DisplayServer.get_name() != "headless" and RenderingServer.get_video_adapter_name() != ""
	print("V14: ", "con GPU (" + RenderingServer.get_video_adapter_name() + ")" if gpu else "sin GPU (headless): se saltan los píxeles")
	await _probar_mapa()
	check(vigia.errores == 0, "sin errores de script ni de shader (%s)" % vigia.ultimo)
	OS.remove_logger(vigia)
	print("RESULTADO: ", pruebas - fallos, "/", pruebas)
	quit(0 if fallos == 0 else 1)


# ---------------------------------------------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------------------------------------------
func _fotogramas(n: int) -> void:
	for _i in n:
		await process_frame


func _esperar(v: Node) -> void:
	for _i in 60:
		if v.estado != "sin conectar":
			return
		await process_frame


## Imagen de lo que se ve (solo con GPU).
func _captura() -> Image:
	await _fotogramas(3)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


static func _cerca(a: Color, b: Color, tol := 3) -> bool:
	return absi(a.r8 - b.r8) <= tol and absi(a.g8 - b.g8) <= tol and absi(a.b8 - b.b8) <= tol


## VisorRos de prueba (PC salvo `en_vita`): `planos` bajo la CanvasLayer «Planta», `hud` bajo «Hud», `tres_d` bajo
## el visor. Cámara ortográfica mirando hacia abajo (−Y de Godot) sobre `centro`.
func _visor(en_vita: bool, planos: Array, hud: Array, tres_d: Array, centro := Vector3.ZERO, tam := 8.0) -> Node:
	var v: Node = VisorRos.new()
	v.name = "VisorPrueba"
	v.transporte = "loopback"
	v.config_json = ""
	v.reintento_s = 0.0
	v.en_vita = en_vita
	v.px_por_m = 20.0
	var capa := CanvasLayer.new()
	capa.name = "Planta"
	var vista := Node2D.new()
	vista.name = "Vista"
	vista.position = Vector2(20, 530)
	capa.add_child(vista)
	v.add_child(capa)
	for d in planos:
		vista.add_child(d)
	var h := CanvasLayer.new()
	h.name = "Hud"
	h.layer = 2
	v.add_child(h)
	var t: Control = Texto.new()
	t.name = "Texto"
	h.add_child(t)
	v.texto = t
	for w in hud:
		h.add_child(w)
	for d in tres_d:
		v.add_child(d)
	var raiz := Node3D.new()
	raiz.name = "Escena"
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = tam
	raiz.add_child(cam)
	cam.look_at_from_position(centro + Vector3(0, 20, 0), centro, Vector3.FORWARD)
	raiz.add_child(v)
	root.add_child(raiz)
	cam.current = true
	v.camara = cam
	return v


func _cerrar(v: Node) -> void:
	v.get_parent().queue_free()
	await _fotogramas(2)


func _rejilla(w: int, h: int, datos: Array, res := 1.0, org := Vector2.ZERO):
	var g = RosMsg.from_type("nav_msgs/msg/OccupancyGrid")
	g.header.frame_id = "map"
	g.info.resolution = res
	g.info.width = w
	g.info.height = h
	g.info.origin.position.x = org.x
	g.info.origin.position.y = org.y
	g.info.origin.orientation.w = 1.0
	g.data = PackedInt32Array(datos)
	var r = RosMsg.from_type("nav_msgs/msg/OccupancyGrid")
	r.deserialize(g.serialize())                        # como llega del middleware
	return r


# ---------------------------------------------------------------------------------------------------------------
# 1. Mapa y costmap con shader + paleta (resuelve el DESAFÍO de V1: sin bucle por celda en el PC)
# ---------------------------------------------------------------------------------------------------------------
func _probar_mapa() -> void:
	var m2: Node2D = load(D + "2d/mapa.gd").new()
	m2.name = "Mapa"
	m2.topic = "/map"
	m2.tipo = "nav_msgs/msg/OccupancyGrid"
	m2.alfa = 1.0
	var c2: Node2D = load(D + "2d/costmap.gd").new()
	c2.name = "Costmap"
	c2.topic = "/global_costmap/costmap"
	c2.tipo = "nav_msgs/msg/OccupancyGrid"
	c2.alfa = 1.0
	var m3: Node3D = load(D + "3d/mapa.gd").new()
	m3.name = "Mapa3D"
	m3.topic = "/map"
	m3.tipo = "nav_msgs/msg/OccupancyGrid"
	var v := _visor(false, [m2, c2], [], [m3], Vector3(-2, 0, -4), 9.0)
	await _esperar(v)
	check(m2.mapa.gpu and m3.mapa.gpu and c2.mapa.gpu, "mapa: PC → índices en GPU (gpu = true)")
	# 8×4 celdas de 1 m: valores de la rampa map (0 libre, 50, 100 ocupado, −1 desconocido, ilegal 120).
	var vals := [0, 25, 50, 75, 100, -1, 120, -100,
			10, 20, 30, 40, 60, 70, 80, 90,
			0, 0, 100, 100, -1, -1, 50, 50,
			5, 15, 35, 45, 55, 65, 85, 95]
	var g = _rejilla(8, 4, vals, 1.0, Vector2(0, 0))
	var t0 := Time.get_ticks_usec()
	var d = m2.mapa.de_grid(g)
	var us := Time.get_ticks_usec() - t0
	check(d != null and d["indices"] and d["img"].get_format() == Image.FORMAT_R8, "mapa: dato intermedio = índices R8")
	check(d["img"].get_pixel(0, 3).r8 == 0 and d["img"].get_pixel(5, 3).r8 == 255 and d["img"].get_pixel(4, 3).r8 == 100,
			"mapa: fila 0 abajo (flip_y), −1 → 255, 100 → 100")
	m2._al_mensaje(g)
	m3._al_mensaje(g)
	await _fotogramas(2)
	check(m2.material is ShaderMaterial and m2.material.get_shader_parameter("paleta") is ImageTexture,
			"mapa 2D: material canvas_item con la paleta 256×1")
	check(m3._vis.material_override is ShaderMaterial and m3.textura_actual() == m3.mapa.textura,
			"mapa 3D: material spatial con la textura de índices")
	var ref: Image = m2.mapa.imagen_colores()
	var rampa := Paleta.rampa_mapa(Paleta.ESQUEMA_MAP)
	check(ref.get_pixel(0, 3) == rampa.get_pixel(0, 0) and ref.get_pixel(5, 3) == rampa.get_pixel(255, 0),
			"mapa: referencia CPU = paleta map de RViz")
	# Grande: 1024² celdas sin bucle por celda (antes ≈ 1 M iteraciones GDScript).
	var grande := PackedInt32Array()
	grande.resize(1024 * 1024)
	grande.fill(-1)
	var gg = _rejilla(1024, 1024, grande, 0.05)
	t0 = Time.get_ticks_usec()
	var dg = m2.mapa.de_grid(gg)
	var us_g := Time.get_ticks_usec() - t0
	print("mapa: 8×4 = %d µs; 1024² = %d µs (sin bucle por celda)" % [us, us_g])
	check(dg != null and dg["img"].get_size() == Vector2i(1024, 1024) and us_g < 150000,
			"mapa: 1024² decodificado en < 150 ms (%d µs)" % us_g)
	# Esquema en caliente: solo cambia la paleta (binaria con umbral 50).
	var p0: ImageTexture = m2.mapa.textura_paleta()
	m2.mapa.poner_esquema(Paleta.ESQUEMA_MAP, true, 50)
	check(m2.mapa.textura_paleta() != p0 and m2.material.get_shader_parameter("paleta") == m2.mapa.textura_paleta(),
			"mapa: binaria/umbral cambian solo la paleta del material")
	m2.mapa.poner_esquema(Paleta.ESQUEMA_MAP)
	# Costmap con la paleta costmap.
	var gc = _rejilla(4, 2, [0, 50, 99, 100, -1, 0, 0, 0], 1.0, Vector2(0, 4))
	c2._al_mensaje(gc)
	await _fotogramas(2)
	var rc: Image = c2.mapa.imagen_colores()
	check(c2.material is ShaderMaterial and rc.get_pixel(0, 1).a8 == 0
			and rc.get_pixel(2, 1).to_rgba32() == Color8(0, 255, 255).to_rgba32(), "costmap: shader + paleta costmap (0 transparente, 99 cian)")
	if gpu:
		var cap := await _captura()
		# Planta 2D: centro de cada celda (i, j) → pantalla.
		var malos := 0
		var xf: Transform2D = m2.get_global_transform_with_canvas()
		for j in 4:
			for i in 8:
				var p: Vector2 = xf * m2.px(Vector2(i + 0.5, j + 0.5))
				var esperado: Color = ref.get_pixel(i, 3 - j)
				var visto := cap.get_pixelv(Vector2i(p))
				if not _cerca(visto, esperado):
					malos += 1
					if malos < 4:
						print("  celda %d,%d: visto %s esperado %s" % [i, j, visto, esperado])
		check(malos == 0, "GPU mapa 2D: las 32 celdas con el color de la paleta map (%d mal)" % malos)
		# Costmap: (2,0) cian, (3,0) magenta, (0,0) transparente → se ve el fondo (no cian).
		var xc: Transform2D = c2.get_global_transform_with_canvas()
		var cian := cap.get_pixelv(Vector2i(xc * c2.px(Vector2(2.5, 4.5))))
		var magenta := cap.get_pixelv(Vector2i(xc * c2.px(Vector2(3.5, 4.5))))
		check(_cerca(cian, Color8(0, 255, 255)) and _cerca(magenta, Color8(255, 0, 255)), "GPU costmap: 99 cian y 100 magenta")
		# Quad 3D: ROS (x, y) → Godot (−y, 0, −x); cámara ortográfica cenital.
		var cam: Camera3D = v.camara
		var malos3 := 0
		for j in 4:
			for i in 8:
				var w := rclgd.ros_to_godot_vector(Vector3(i + 0.5, j + 0.5, 0.01))
				var p3 := cam.unproject_position(w)
				var e3: Color = ref.get_pixel(i, 3 - j)
				var v3 := cap.get_pixelv(Vector2i(p3))
				# Las celdas de la planta 2D tapan parte del 3D: solo se comparan las que no caen bajo la planta.
				if Rect2(xf * m2.px(Vector2(0, 4)), Vector2(8, 4) * 20.0).grow(4).has_point(p3) \
						or Rect2(xc * c2.px(Vector2(0, 6)), Vector2(4, 2) * 20.0).grow(4).has_point(p3):
					continue
				if not _cerca(v3, e3, 6):                  # sRGB↔lineal en 8 bit: ±6 en los grises oscuros
					malos3 += 1
					if malos3 < 4:
						print("  3D celda %d,%d: visto %s esperado %s" % [i, j, v3, e3])
		check(malos3 == 0, "GPU mapa 3D: celdas visibles con el color de la paleta (%d mal)" % malos3)
	await _cerrar(v)
	# Vita simulada: sin shaders (gpu = false) y el compacto intacto.
	var mv: Node2D = load(D + "2d/mapa.gd").new()
	mv.name = "MapaVita"
	var vv := _visor(true, [mv], [], [])
	await _esperar(vv)
	check(not mv.mapa.gpu and mv.canal.compacto and mv.material == null, "mapa en la Vita: sin shader, camino compacto")
	await _cerrar(vv)
