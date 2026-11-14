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
const MapasColor = preload("res://comun/visor/mapas_color.gd")
const D := "res://comun/visor/displays/"


class Vigia:
	extends Logger
	var errores := 0
	var ultimo := ""

	func _log_error(_f: String, file: String, _l: int, code: String, rationale: String, _e: bool, tipo: int,
			_b: Array[ScriptBacktrace]) -> void:
		if tipo == ERROR_TYPE_SCRIPT or tipo == ERROR_TYPE_SHADER or (tipo == ERROR_TYPE_ERROR and (file.contains("/visor/") or file.contains("shader"))):
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
	await _probar_nube()
	await _probar_imagen()
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


# ---------------------------------------------------------------------------------------------------------------
# 2. Nube PointCloud2 en GPU
# ---------------------------------------------------------------------------------------------------------------
## PointCloud2 con `campos` = [[nombre, offset, datatype], …] y los bytes ya armados.
func _nube(campos: Array, step: int, w: int, h: int, datos: PackedByteArray, big := false):
	var m = RosMsg.from_type("sensor_msgs/msg/PointCloud2")
	m.header.frame_id = "map"
	var fs := []
	for c in campos:
		var f = RosMsg.from_type("sensor_msgs/msg/PointField")
		f.name = c[0]
		f.offset = c[1]
		f.datatype = c[2]
		f.count = 1
		fs.append(f)
	m.fields = fs
	m.width = w
	m.height = h
	m.point_step = step
	m.row_step = step * w
	m.is_bigendian = big
	m.data = datos
	var r = RosMsg.from_type("sensor_msgs/msg/PointCloud2")
	r.deserialize(m.serialize())
	return r


## Puntos de prueba (ROS): tres esquinas y un NaN.
const PTS := [Vector3(1.5, 0.0, 0.0), Vector3(0.0, 1.5, 0.0), Vector3(-1.5, -1.5, 0.0), Vector3(NAN, 0.0, 0.0)]


func _pixel_punto(cap: Image, cam: Camera3D, p: Vector3) -> Color:
	return cap.get_pixelv(Vector2i(cam.unproject_position(rclgd.ros_to_godot_vector(p))))


func _probar_nube() -> void:
	var nb: Node3D = load(D + "3d/nube_puntos.gd").new()
	nb.name = "NubePuntos"
	nb.topic = "/points"
	nb.tam_px = 12.0
	nb.rango_auto = true
	var v := _visor(false, [], [], [nb], Vector3.ZERO, 6.0)
	await _esperar(v)
	check(nb.estado == "ok" and nb.solo_pc and nb.canal.tipo_abierto == "sensor_msgs/msg/PointCloud2" and nb.cupo == 1,
			"nube GPU: PointCloud2 directo, solo_pc, 1 instancia")
	check(nb._vis.mesh.get_surface_count() == 1 and nb._vis.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_POINTS,
			"nube GPU: malla de puntos (max_puntos vértices) creada una vez")
	# (a) PCL XYZI: x, y, z, intensity float32, point_step 16 → ruta GPU, color por intensidad (arcoíris de RViz).
	var b := PackedByteArray()
	b.resize(16 * PTS.size())
	for i in PTS.size():
		b.encode_float(16 * i, PTS[i].x)
		b.encode_float(16 * i + 4, PTS[i].y)
		b.encode_float(16 * i + 8, PTS[i].z)
		b.encode_float(16 * i + 12, [0.0, 50.0, 100.0, 7.0][i])
	var xyzi := [["x", 0, 7], ["y", 4, 7], ["z", 8, 7], ["intensity", 12, 7]]
	nb._al_mensaje(_nube(xyzi, 16, PTS.size(), 1, b))
	check(nb.ruta == "gpu" and nb.puntos == 4 and nb.paso == 1 and nb.material_nube.get_shader_parameter("modo") == 1,
			"nube XYZI: ruta GPU (bytes crudos a la textura), modo campo")
	check(nb.rango_usado == Vector2(0, 100), "nube XYZI: rango automático 0–100 (%s)" % nb.rango_usado)
	check(nb.textura.get_width() == 4096 and nb.textura.get_format() == Image.FORMAT_RGBA8, "nube: textura RGBA8 de 4096 palabras")
	if gpu:
		var cap := await _captura()
		var c0 := _pixel_punto(cap, v.camara, PTS[0])
		var c2 := _pixel_punto(cap, v.camara, PTS[2])
		check(_cerca(c0, MapasColor.color(MapasColor.ARCOIRIS, 0), 6) and _cerca(c2, MapasColor.color(MapasColor.ARCOIRIS, 255), 6),
				"GPU nube XYZI: intensidad mínima roja y máxima magenta (RViz) — %s %s" % [c0, c2])
	# (b) XYZRGB (PCL: rgb float32 empaquetado en 16, point_step 32).
	nb.campo_color = "rgb"
	var rgb := [0xFF0000, 0x00FF00, 0x0000FF, 0xFFFFFF]
	var b2 := PackedByteArray()
	b2.resize(32 * PTS.size())
	for i in PTS.size():
		b2.encode_float(32 * i, PTS[i].x)
		b2.encode_float(32 * i + 4, PTS[i].y)
		b2.encode_float(32 * i + 8, PTS[i].z)
		b2.encode_u32(32 * i + 16, rgb[i])
	nb._al_mensaje(_nube([["x", 0, 7], ["y", 4, 7], ["z", 8, 7], ["rgb", 16, 7]], 32, 4, 1, b2))
	check(nb.ruta == "gpu" and nb.material_nube.get_shader_parameter("modo") == 2, "nube XYZRGB: rgb empaquetado en el shader")
	if gpu:
		var cap := await _captura()
		var cs := [_pixel_punto(cap, v.camara, PTS[0]), _pixel_punto(cap, v.camara, PTS[1]), _pixel_punto(cap, v.camara, PTS[2])]
		check(_cerca(cs[0], Color.RED, 6) and _cerca(cs[1], Color.GREEN, 6) and _cerca(cs[2], Color.BLUE, 6),
				"GPU nube XYZRGB: rojo, verde y azul en su sitio (ROS → Godot) — %s" % [cs])
	# (c) x/y/z FLOAT64 (point_step 28, desalineado) → ruta CPU (reempaquetado a 16 B), mismo shader.
	nb.campo_color = "intensity"
	var b3 := PackedByteArray()
	b3.resize(28 * PTS.size())
	for i in PTS.size():
		b3.encode_double(28 * i, PTS[i].x)
		b3.encode_double(28 * i + 8, PTS[i].y)
		b3.encode_double(28 * i + 16, PTS[i].z)
		b3.encode_u16(28 * i + 24, [0, 50, 100, 7][i])
	nb._al_mensaje(_nube([["x", 0, 8], ["y", 8, 8], ["z", 16, 8], ["intensity", 24, 4]], 28, 4, 1, b3))
	check(nb.ruta == "cpu" and nb.material_nube.get_shader_parameter("point_step") == 16 and nb.rango_usado == Vector2(0, 100),
			"nube FLOAT64 desalineada: ruta CPU (16 B por punto) y rango 0–100")
	if gpu:
		var cap := await _captura()
		check(_cerca(_pixel_punto(cap, v.camara, PTS[2]), MapasColor.color(MapasColor.ARCOIRIS, 255), 6),
				"GPU nube ruta CPU: el punto (−1,5, −1,5) con la intensidad máxima")
	# (d) Big endian con todos los campos de 4 B → bswap32 nativo y ruta GPU; con un campo de 2 B → rechazada.
	nb.campo_color = ""
	var b4 := PackedByteArray()
	b4.resize(12 * PTS.size())
	for i in PTS.size():
		b4.encode_float(12 * i, PTS[i].x)
		b4.encode_float(12 * i + 4, PTS[i].y)
		b4.encode_float(12 * i + 8, PTS[i].z)
	b4.bswap32()
	nb._al_mensaje(_nube([["x", 0, 7], ["y", 4, 7], ["z", 8, 7]], 12, 4, 1, b4, true))
	check(nb.ruta == "gpu" and nb.textura.get_image().get_data().slice(0, 4).decode_float(0) == 1.5,
			"nube big endian (campos de 4 B): bswap32 y ruta GPU")
	var r0: int = nb.rechazadas
	nb._al_mensaje(_nube([["x", 0, 7], ["y", 4, 7], ["z", 8, 7], ["intensity", 12, 4]], 16, 1, 1, PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), true))
	check(nb.rechazadas == r0 + 1, "nube big endian con un campo de 2 B: rechazada")
	# (e) Diezmado: 100 000 puntos, max_puntos 60 000 → paso 2, 50 000 dibujados; coste sin bucle por punto.
	var big := PackedFloat32Array()
	big.resize(100000 * 4)
	var bb := big.to_byte_array()
	var nube_100k = _nube(xyzi, 16, 1000, 100, bb)
	nb._al_mensaje(nube_100k)                           # la primera crea la textura de 98 filas
	var t0 := Time.get_ticks_usec()
	nb._al_mensaje(nube_100k)                           # régimen: misma textura (update)
	var us := Time.get_ticks_usec() - t0
	print("nube: 100 000 puntos (1,6 MB) procesados y subidos en %d µs (ruta %s; display %d µs)" % [us, nb.ruta, nb.us_ultimo])
	check(nb.paso == 2 and nb.dibujados == 50000 and nb.ruta == "gpu" and us < 50000,
			"nube 100 k: diezmado uniforme (paso 2, 50 000 vértices) en < 50 ms (%d µs)" % us)
	# (f) Mapas de color: arcoíris de RViz = getRainbowColor literal; turbo y gris.
	check(MapasColor.arcoiris_rviz(0.0) == Color(1, 0, 1) and MapasColor.arcoiris_rviz(1.0) == Color(1, 0, 0)
			and MapasColor.arcoiris_rviz(0.5) == Color(0, 1, 0.5), "mapas de color: getRainbowColor de RViz")
	check(MapasColor.color(MapasColor.GRIS, 255) == Color(1, 1, 1) and MapasColor.textura(MapasColor.TURBO).get_width() == 256,
			"mapas de color: gris y turbo 256×1")
	await _cerrar(v)


# ---------------------------------------------------------------------------------------------------------------
# 3. Imagen cruda con shader: profundidad (16UC1, 32FC1) con mapa de color, bayer, YUV y filas con relleno
# ---------------------------------------------------------------------------------------------------------------
func _cruda(enc: String, w: int, h: int, step: int, datos: PackedByteArray):
	var m = RosMsg.from_type("sensor_msgs/msg/Image")
	m.header.frame_id = "camara"
	m.encoding = enc
	m.width = w
	m.height = h
	m.step = step
	m.data = datos
	return m


## Centro del píxel (i, j) de la imagen en pantalla.
func _px_imagen(im: Control, i: int, j: int) -> Vector2i:
	var r: Rect2 = im.rect_imagen()
	var k: float = r.size.x / im.tam_imagen.x
	return Vector2i(im.get_global_rect().position + r.position + (Vector2(i, j) + Vector2(0.5, 0.5)) * k)


static func _yuv(y: int, u: int, v: int) -> Color:
	var yy := y / 255.0
	var uu := u / 255.0 - 0.5
	var vv := v / 255.0 - 0.5
	return Color(clampf(yy + 1.402 * vv, 0, 1), clampf(yy - 0.344136 * uu - 0.714136 * vv, 0, 1), clampf(yy + 1.772 * uu, 0, 1))


func _probar_imagen() -> void:
	var im: Control = load(D + "hud/imagen_pc.gd").new()
	im.name = "ImagenPC"
	im.topic = "/camera/depth/image_raw"
	im.position = Vector2(560, 20)
	im.size = Vector2(320, 300)                         # 32×24 → 320×240 con bandas de fondo arriba y abajo
	var v := _visor(false, [], [im], [])
	await _esperar(v)
	check(im.estado == "ok" and im.solo_pc and im.canal.tipo_abierto == "sensor_msgs/msg/Image" and im.lienzo != null,
			"imagen PC: sensor_msgs/Image directo, solo_pc, lienzo con material")
	# 16UC1 en mm: columna i = i·100 mm (la 0 = sin dato → transparente).
	var d16 := PackedByteArray()
	d16.resize(32 * 24 * 2)
	for j in 24:
		for i in 32:
			d16.encode_u16(2 * (j * 32 + i), i * 100)
	im._al_mensaje(_cruda("16UC1", 32, 24, 64, d16))
	await _fotogramas(2)
	check(im.modo == im.ESCALAR16 and im.textura.get_format() == Image.FORMAT_RG8 and im.tam_imagen == Vector2i(32, 24),
			"16UC1: textura RG8 sin conversión, modo escalar")
	check(im.rango_usado.is_equal_approx(Vector2(0.1, 3.1)) and is_equal_approx(im.material_imagen.get_shader_parameter("escala"), 0.001),
			"16UC1: rango automático 0,1–3,1 m (mm × 0,001), 0 fuera (%s)" % im.rango_usado)
	check(im.material == null and im.lienzo.material == im.material_imagen, "imagen PC: el fondo sin shader, la imagen en el lienzo")
	if gpu:
		var cap := await _captura()
		var fondo := cap.get_pixelv(Vector2i(im.get_global_rect().position + Vector2(5, 5)))
		var c31 := cap.get_pixelv(_px_imagen(im, 31, 10))
		var c1 := cap.get_pixelv(_px_imagen(im, 1, 10))
		var c0 := cap.get_pixelv(_px_imagen(im, 0, 10))
		var c16 := cap.get_pixelv(_px_imagen(im, 16, 10))
		check(_cerca(c31, im.color_escalar(3.1)) and _cerca(c1, im.color_escalar(0.1)) and _cerca(c16, im.color_escalar(1.6)),
				"GPU 16UC1: mapa turbo (mín., medio y máx.) — %s %s %s" % [c1, c16, c31])
		check(_cerca(c0, fondo), "GPU 16UC1: 0 mm transparente (se ve el fondo)")
	# 32FC1 en m con NaN e Inf.
	var f32 := PackedFloat32Array()
	f32.resize(32 * 24)
	for k in f32.size():
		f32[k] = (k % 32) * 0.1
	f32[10 * 32 + 5] = NAN
	f32[10 * 32 + 6] = INF
	im.rango_auto = false
	im.rango = Vector2(0.0, 3.1)
	im._al_mensaje(_cruda("32FC1", 32, 24, 128, f32.to_byte_array()))
	await _fotogramas(2)
	check(im.modo == im.ESCALAR32 and im.textura.get_format() == Image.FORMAT_RF and im.rango_usado == Vector2(0.0, 3.1),
			"32FC1: textura RF, rango fijo")
	if gpu:
		var cap := await _captura()
		var fondo := cap.get_pixelv(Vector2i(im.get_global_rect().position + Vector2(5, 5)))
		check(_cerca(cap.get_pixelv(_px_imagen(im, 20, 10)), im.color_escalar(2.0)) and _cerca(cap.get_pixelv(_px_imagen(im, 5, 10)), fondo)
				and _cerca(cap.get_pixelv(_px_imagen(im, 6, 10)), fondo), "GPU 32FC1: color por profundidad; NaN e Inf transparentes")
	# Bayer RGGB: superpíxel (R=200, G=100/100, B=50) → Color8(200, 100, 50).
	var bay := PackedByteArray()
	bay.resize(32 * 24)
	for j in 24:
		for i in 32:
			bay[j * 32 + i] = [[200, 100], [100, 50]][j % 2][i % 2]
	im._al_mensaje(_cruda("bayer_rggb8", 32, 24, 32, bay))
	await _fotogramas(2)
	check(im.modo == im.BAYER and im.patron == 0 and im.textura.get_format() == Image.FORMAT_L8, "bayer_rggb8: L8 + demosaico en el shader")
	if gpu:
		var cap := await _captura()
		check(_cerca(cap.get_pixelv(_px_imagen(im, 9, 9)), Color8(200, 100, 50)) and _cerca(cap.get_pixelv(_px_imagen(im, 10, 10)), Color8(200, 100, 50)),
				"GPU bayer_rggb8: superpíxel → (200, 100, 50)")
	# YUYV (Y0 U Y1 V): mitad izquierda gris, mitad derecha rojiza.
	var yu := PackedByteArray()
	for j in 24:
		for i in 16:
			yu.append_array(PackedByteArray([128, 128, 128, 128]) if i < 8 else PackedByteArray([76, 85, 90, 255]))
	im._al_mensaje(_cruda("yuyv", 32, 24, 64, yu))
	await _fotogramas(2)
	check(im.modo == im.YUYV and im.textura.get_width() == 16 and im.tam_imagen == Vector2i(32, 24), "yuyv: RGBA8 de ancho/2")
	if gpu:
		var cap := await _captura()
		check(_cerca(cap.get_pixelv(_px_imagen(im, 3, 5)), _yuv(128, 128, 128)) and _cerca(cap.get_pixelv(_px_imagen(im, 20, 5)), _yuv(76, 85, 255))
				and _cerca(cap.get_pixelv(_px_imagen(im, 21, 5)), _yuv(90, 85, 255)), "GPU yuyv: BT.601 (Y0 y Y1 de cada par)")
	# uyvy (= yuv422 de ROS).
	var uy := PackedByteArray()
	for k in 32 * 24 / 2:
		uy.append_array(PackedByteArray([85, 76, 255, 90]))
	im._al_mensaje(_cruda("yuv422", 32, 24, 64, uy))
	await _fotogramas(2)
	if gpu:
		var cap := await _captura()
		check(_cerca(cap.get_pixelv(_px_imagen(im, 4, 5)), _yuv(76, 85, 255)) and _cerca(cap.get_pixelv(_px_imagen(im, 5, 5)), _yuv(90, 85, 255)),
				"GPU yuv422 (uyvy): BT.601")
	check(im.modo == im.UYVY, "yuv422: modo UYVY")
	# rgb8 con relleno de fila (step 102 = 34 px): región útil 32×24, sin copia por fila.
	var rel := PackedByteArray()
	for j in 24:
		for i in 34:
			rel.append_array(PackedByteArray([0, 0, 255]) if i < 32 else PackedByteArray([255, 255, 0]))
	im._al_mensaje(_cruda("rgb8", 32, 24, 102, rel))
	await _fotogramas(2)
	check(im.textura.get_width() == 34 and im.tam_imagen == Vector2i(32, 24) and im.modo == im.DIRECTO,
			"rgb8 con relleno (step 102): textura de 34 px, se dibujan 32")
	if gpu:
		var cap := await _captura()
		check(_cerca(cap.get_pixelv(_px_imagen(im, 31, 5)), Color.BLUE), "GPU rgb8 con relleno: la última columna útil es azul (el relleno amarillo no se ve)")
	var r0: int = im.rechazadas
	im._al_mensaje(_cruda("16SC1", 32, 24, 64, d16))
	im._al_mensaje(_cruda("rgb8", 32, 24, 100, rel))    # 100 no es múltiplo de 3
	check(im.rechazadas == r0 + 2, "16SC1 y step no múltiplo de bpp: rechazados")
	await _cerrar(v)
