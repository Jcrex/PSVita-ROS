extends SceneTree
## Prueba de host de V11 (doc 36 §10; 36a §4.6.2): costmap por teselas de 4 bit y su composición sobre el mapa.
##   - prueba de bytes Python = GDScript: `vc1.gd` (reducción por máximo + tesela 32×16 a 4 bit) da la huella
##     HUELLA_COSTMAP de `docker/scripts/test_vita_relay.py`; niveles = LUT de 16 colores de la paleta costmap;
##   - CostmapTextura: repaso completo (imagen = referencia celda a celda), actualización parcial (solo cambia la
##     tesela que llega), época (teselas de otra época descartadas; época nueva = imagen vacía);
##   - composición en CPU: recomponer por regiones sucias (teselas del mapa y del costmap) = componer todo de cero
##     (byte a byte), y píxeles sueltos = mezcla del mapa con la celda del costmap (± 2/255);
##   - displays en la Vita simulada (loopback): Mapa + Costmap → el Mapa dibuja la textura compuesta (1 *quad*);
##     Costmap sin Mapa → su propia textura; PC: OccupancyGrid con la paleta costmap; RegistroDisplays.
##
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_costmap.gd

const VisorRos = preload("res://comun/visor/visor_ros.gd")
const Registro = preload("res://comun/visor/registro_displays.gd")
const CostmapTextura = preload("res://comun/visor/costmap_textura.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")
const VC1 = preload("res://comun/ros/vc1.gd")
const D := "res://comun/visor/displays/"

# De `docker/scripts/test_vita_relay.py` (HUELLA_COSTMAP: 70×37 a 5 cm → 35×19 a 10 cm, 2×2 teselas, época 513).
const HUELLA_COSTMAP := "3814fb5781c2a0f19d936fc85e5b6d87"

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
	_probar_bytes()
	_probar_textura()
	_probar_composicion()
	_probar_registro()
	await _probar_vita()
	await _probar_pc()
	print("RESULTADO: ", pruebas - fallos, "/", pruebas)
	quit(0 if fallos == 0 else 1)


# ---------------------------------------------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------------------------------------------
func _arr(tipo: String, datos):
	var m = RosMsg.from_type(tipo)
	m.data = datos
	return m


## −2 … 100 (la misma fórmula que `rejilla_costmap` de test_vita_relay.py).
func _rejilla(w: int, h: int) -> PackedInt32Array:
	var r := PackedInt32Array()
	for y in h:
		for x in w:
			r.append((x * 7 + y * 13) % 103 - 2)
	return r


func _md5(datos) -> String:
	var partes := PackedStringArray()
	for v in datos:
		partes.append(str(int(v)))
	return ",".join(partes).md5_text()


## Costmap reducido + todas sus teselas (como el relay): {"d", "w", "h", "teselas": [PackedByteArray]}.
func _teselas(rej: PackedInt32Array, w: int, h: int, res: float, epoca: int) -> Dictionary:
	var r: Array = VC1.reducir_costmap(rej, w, h, VC1.factor_costmap(res))
	var n := VC1.teselas_costmap(r[1], r[2])
	var out := []
	for ty in n.y:
		for tx in n.x:
			out.append(VC1.empaquetar_tesela_costmap(r[0], r[1], r[2], tx, ty, epoca))
	return {"d": r[0], "w": r[1], "h": r[2], "n": n, "teselas": out}


func _meta(res: float, w: int, h: int, ox: float, oy: float, epoca: int):
	return _arr("std_msgs/msg/Float32MultiArray", VC1.meta_costmap(res, w, h, ox, oy, epoca))


## Imagen esperada del costmap: cada celda con el color de su nivel (norte arriba).
func _referencia(c, d: PackedInt32Array, w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, h - 1 - y, c.color_nivel(VC1.celda_costmap_4bit(d[y * w + x])))
	return img


func _display(ruta: String, nombre: String, props: Dictionary) -> Node:
	var d: Node = load(ruta).new()
	d.name = nombre
	for k in props:
		d.set(k, props[k])
	return d


func _visor(en_vita: bool, d2: Array) -> Node:
	var v: Node = VisorRos.new()
	v.name = "VisorPrueba"
	v.transporte = "loopback"
	v.config_json = ""
	v.reintento_s = 0.0
	v.en_vita = en_vita
	var planta := CanvasLayer.new()
	planta.name = "Planta"
	v.add_child(planta)
	var vista := Node2D.new()
	vista.name = "Vista"
	planta.add_child(vista)
	for d in d2:
		vista.add_child(d)
	var raiz := Node3D.new()
	raiz.name = "Escena"
	raiz.add_child(v)
	root.add_child(raiz)
	return v


func _esperar(v: Node) -> void:
	for _i in 60:
		if v.estado != "sin conectar":
			return
		await process_frame


func _fotogramas(n: int) -> void:
	for _i in n:
		await process_frame


## La subida de la composición está limitada a 4 Hz: esperar (≤ 1 s) a que no quede nada sucio.
func _esperar_composicion(c) -> void:
	for _i in 50:
		if not c._todo and c._regiones.is_empty() and c._regiones_base.is_empty():
			return
		await create_timer(0.02).timeout


func _cerrar(v: Node) -> void:
	v.get_parent().queue_free()
	await _fotogramas(2)


# ---------------------------------------------------------------------------------------------------------------
# Bytes: vc1.gd = vita_relay_formatos.py
# ---------------------------------------------------------------------------------------------------------------
func _probar_bytes() -> void:
	var niveles := []
	for v in [-1, 0, 1, 50, 92, 93, 98, 99, 100, 120]:
		niveles.append(VC1.celda_costmap_4bit(v))
	check(niveles == [0, 1, 2, 7, 12, 13, 13, 14, 15, 15], "niveles de 4 bit = Python (%s)" % [niveles])
	check(VC1.factor_costmap(0.05) == 2 and VC1.factor_costmap(0.1) == 1 and VC1.factor_costmap(0.03) == 4,
			"factor de reducción a ≥ 10 cm")
	var r: Array = VC1.reducir_costmap(PackedInt32Array([-1, 5, -1, -1, 100, 0, 0, 0, -1]), 3, 3, 2)
	check(r[0] == PackedInt32Array([100, 0, 0, -1]) and r[1] == 2 and r[2] == 2, "reducción por máximo (lo conocido gana)")
	var t := _teselas(_rejilla(70, 37), 70, 37, 0.05, 513)
	var plano := PackedByteArray()
	for b: PackedByteArray in t.teselas:
		plano.append_array(b)
	check(t.w == 35 and t.h == 19 and t.n == Vector2i(2, 2) and plano.size() == 4 * 260, "70×37 a 5 cm → 35×19, 2×2 teselas de 260 B")
	check(_md5(plano) == HUELLA_COSTMAP, "tesela de 4 bit: huella Python = GDScript (%s)" % _md5(plano))
	check(VC1.meta_costmap(0.1, 35, 19, -1.0, -2.0, 1) == PackedFloat32Array([0.1, 35, 19, -1, -2, 2, 2, 1]),
			"costmap_meta = Python")
	# LUT de 16: la de PaletaViz (índices 255, 0, 8 … 88, 98, 99, 100) con la alfa del display.
	var c = CostmapTextura.new()
	c.alfa = 1.0
	var lut := Paleta.lut16_costmap()
	check(c.color_nivel(1).a8 == 0 and c.color_nivel(15).to_rgba32() == Color8(255, 0, 255).to_rgba32()
			and c.color_nivel(14).to_rgba32() == Color8(0, 255, 255).to_rgba32()
			and c.color_nivel(0).to_rgba32() == Color8(0x70, 0x89, 0x86).to_rgba32()
			and c.color_nivel(7).to_rgba32() == lut[7].to_rgba32(), "LUT: libre transparente, inscrito cian, letal magenta, −1 gris")
	var c2 = CostmapTextura.new()
	c2.alfa = 0.5
	check(c2.color_nivel(15).a8 == 128 and c2.color_nivel(1).a8 == 0, "LUT: alfa del costmap en el canal A")


# ---------------------------------------------------------------------------------------------------------------
# CostmapTextura: repaso completo, actualización parcial, época
# ---------------------------------------------------------------------------------------------------------------
func _probar_textura() -> void:
	var rej := _rejilla(70, 37)
	var t := _teselas(rej, 70, 37, 0.05, 1)
	var c = CostmapTextura.new()
	check(not c.de_tesela(_arr("std_msgs/msg/UInt8MultiArray", t.teselas[0])) and c.descartadas == 1,
			"sin meta: la tesela se descarta")
	c.al_meta(_meta(0.1, t.w, t.h, -1.0, -2.0, 1))
	check(c.tiene_datos() and c.img.get_size() == Vector2i(35, 19) and c.img.get_pixel(0, 0).a8 == 0,
			"meta: imagen 35×19 transparente (aún sin teselas)")
	# Repaso completo: las 4 teselas (dos de borde parciales en x y en y).
	var us := 0
	for b in t.teselas:
		check(c.de_tesela(_arr("std_msgs/msg/UInt8MultiArray", b)), "repaso: tesela (%d, %d) pintada" % [b[2], b[3]])
		us = maxi(us, c.us_ultima)
	var ref := _referencia(c, t.d, t.w, t.h)
	check(c.img.get_data() == ref.get_data(), "repaso completo: imagen = referencia celda a celda")
	print("  tesela de costmap (host): máx %d µs" % us)
	# Actualización parcial: cambia una zona de la tesela (1, 0) y solo llega esa tesela.
	var cambio := rej.duplicate()
	for y in range(0, 10):
		for x in range(64, 70):
			cambio[y * 70 + x] = 100
	var t2 := _teselas(cambio, 70, 37, 0.05, 1)
	var antes: Image = c.img.duplicate()
	check(c.de_tesela(_arr("std_msgs/msg/UInt8MultiArray", t2.teselas[1])), "parcial: llega la tesela (1, 0)")
	var ref2 := _referencia(c, t2.d, t2.w, t2.h)
	check(c.img.get_data() == ref2.get_data(), "parcial: imagen = referencia del costmap nuevo")
	var fuera_igual := true
	for y in 19:
		for x in 35:
			var dentro := x >= 32 and y >= 19 - 16          # tesela (1, 0): celdas x ≥ 32, filas 0–15 (abajo)
			if not dentro and c.img.get_pixel(x, y) != antes.get_pixel(x, y):
				fuera_igual = false
	check(fuera_igual and c.img.get_pixel(34, 18).to_rgba32() == c.color_nivel(15).to_rgba32(),
			"parcial: fuera de la tesela no cambia nada; dentro, letal")
	# Época: una tesela de otra época se descarta; época nueva (misma geometría) = imagen vacía.
	var d0: int = c.descartadas
	var vieja := _teselas(rej, 70, 37, 0.05, 7)
	check(not c.de_tesela(_arr("std_msgs/msg/UInt8MultiArray", vieja.teselas[0])) and c.descartadas == d0 + 1,
			"época: tesela de otra época descartada")
	var v0: int = c.version
	c.al_meta(_meta(0.1, t.w, t.h, -1.0, -2.0, 2))
	check(c.epoca == 2 and c.version > v0 and c.img.get_pixel(5, 5).a8 == 0, "época nueva: imagen vacía")
	check(not c.de_tesela(_arr("std_msgs/msg/UInt8MultiArray", t.teselas[0])), "época nueva: las teselas de la 1 ya no valen")
	var t3 := _teselas(rej, 70, 37, 0.05, 2)
	for b in t3.teselas:
		c.de_tesela(_arr("std_msgs/msg/UInt8MultiArray", b))
	check(c.img.get_data() == ref.get_data(), "época nueva: repaso completo = referencia")
	# Geometría nueva (origen) = imagen nueva aunque la época coincidiera.
	c.al_meta(_meta(0.1, t.w, t.h, -0.5, -2.0, 2))
	check(c.img.get_pixel(5, 5).a8 == 0 and c.origen == Vector2(-0.5, -2.0), "geometría nueva: imagen vacía")
	# Tesela corta o fuera de límites: se descarta sin error.
	var corta := PackedByteArray([2, 0, 0, 0, 1, 2])
	var lejos: PackedByteArray = t3.teselas[0].duplicate()
	lejos[2] = 9
	d0 = c.descartadas
	c.de_tesela(_arr("std_msgs/msg/UInt8MultiArray", corta))
	c.de_tesela(_arr("std_msgs/msg/UInt8MultiArray", lejos))
	check(c.descartadas == d0 + 2, "tesela corta o fuera del costmap: descartada")


# ---------------------------------------------------------------------------------------------------------------
# Composición en CPU sobre el mapa
# ---------------------------------------------------------------------------------------------------------------
func _mapa_base(w: int, h: int, semilla: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color8((x * 3 + semilla) % 256, (y * 5) % 256, 128, 255))
	return img


func _probar_composicion() -> void:
	# Mapa 80×50 a 5 cm con origen (−1,5, −2,5); costmap 70×37 a 5 cm → 35×19 a 10 cm con origen (−1, −2):
	# 10 px a la derecha y 10 px arriba del borde inferior del mapa (sobra mapa por los cuatro lados).
	var res_m := 0.05
	var org_m := Vector2(-1.5, -2.5)
	var base := _mapa_base(80, 50, 0)
	var rej := _rejilla(70, 37)
	var t := _teselas(rej, 70, 37, 0.05, 1)
	var c = CostmapTextura.new()
	c.al_meta(_meta(0.1, t.w, t.h, -1.0, -2.0, 1))
	for b in t.teselas:
		c.de_tesela(_arr("std_msgs/msg/UInt8MultiArray", b))
	check(c.tic_compuesta(base, res_m, org_m, true) and c.compuesta.get_size() == Vector2i(80, 50),
			"composición: imagen con la geometría del mapa (80×50)")
	check(not c.tic_compuesta(base, res_m, org_m, true), "composición: sin nada sucio no se recompone")
	# Píxeles sueltos: fuera del costmap = el mapa; dentro = mapa mezclado con el color de la celda.
	var ok_fuera: bool = c.compuesta.get_pixel(2, 2) == base.get_pixel(2, 2) \
			and c.compuesta.get_pixel(79, 49) == base.get_pixel(79, 49)
	check(ok_fuera, "composición: fuera del costmap queda el mapa")
	var peor := 0.0
	for p in [Vector2i(10, 39), Vector2i(11, 38), Vector2i(40, 20), Vector2i(79, 2), Vector2i(45, 30)]:
		# Píxel (px, fila) → celda del costmap: x = (px − 10) / 2, fila del mundo = (50 − 1 − fila − 10) / 2.
		var cx: int = (p.x - 10) / 2
		var cy: int = (50 - 1 - p.y - 10) / 2
		var esperado: Color = base.get_pixel(p.x, p.y)
		if cx >= 0 and cx < t.w and cy >= 0 and cy < t.h:
			esperado = esperado.blend(c.color_nivel(VC1.celda_costmap_4bit(t.d[cy * t.w + cx])))
		var real: Color = c.compuesta.get_pixel(p.x, p.y)
		peor = maxf(peor, maxf(maxf(absf(real.r - esperado.r), absf(real.g - esperado.g)), absf(real.b - esperado.b)))
	check(peor <= 2.0 / 255.0, "composición: píxel = mapa ⊕ celda del costmap (error máx %.4f)" % peor)
	# Recomponer por regiones = componer todo de cero: cambia una tesela del mapa y una del costmap.
	var base2 := _mapa_base(80, 50, 77)
	var r_mapa: Rect2i = CostmapTextura.rect_tesela_mapa(1, 0, 80, 50)        # columnas 32–63, filas 18–49
	base.blit_rect(base2, r_mapa, r_mapa.position)
	c.marcar_base(r_mapa)
	var cambio := rej.duplicate()
	for k in cambio.size():
		if cambio[k] == 40:
			cambio[k] = 100
	var t2 := _teselas(cambio, 70, 37, 0.05, 1)
	c.de_tesela(_arr("std_msgs/msg/UInt8MultiArray", t2.teselas[2]))          # tesela (0, 1)
	var us0 := Time.get_ticks_usec()
	check(c.tic_compuesta(base, res_m, org_m, true), "parcial: hay regiones sucias")
	var us_parcial := Time.get_ticks_usec() - us0
	var limpio = CostmapTextura.new()
	limpio.al_meta(_meta(0.1, t.w, t.h, -1.0, -2.0, 1))
	for b in t.teselas:
		limpio.de_tesela(_arr("std_msgs/msg/UInt8MultiArray", b))
	limpio.de_tesela(_arr("std_msgs/msg/UInt8MultiArray", t2.teselas[2]))
	us0 = Time.get_ticks_usec()
	limpio.tic_compuesta(base, res_m, org_m, true)
	var us_todo := Time.get_ticks_usec() - us0
	check(c.compuesta.get_data() == limpio.compuesta.get_data(), "parcial: regiones sucias = composición completa (byte a byte)")
	print("  composición (host): parcial %d µs, completa %d µs" % [us_parcial, us_todo])
	# Muchas regiones → una recomposición completa (sin crecer sin límite).
	for i in CostmapTextura.MAX_REGIONES + 2:
		c.marcar_base(Rect2i(i, 0, 1, 1))
	check(c._todo and c._regiones_base.is_empty(), "demasiadas regiones: recomposición completa")
	check(c.tic_compuesta(base, res_m, org_m, true) and c.compuesta.get_data() == limpio.compuesta.get_data(),
			"recomposición completa = la misma imagen")
	# Mapa nuevo (otra geometría) → recomposición completa con el tamaño nuevo.
	var grande := _mapa_base(96, 64, 5)
	check(c.tic_compuesta(grande, res_m, org_m, true) and c.compuesta.get_size() == Vector2i(96, 64),
			"mapa con otra geometría: recompone entera")


# ---------------------------------------------------------------------------------------------------------------
# RegistroDisplays
# ---------------------------------------------------------------------------------------------------------------
func _probar_registro() -> void:
	var casos := [
		["/vita/costmap_tesela", "std_msgs/msg/UInt8MultiArray", true, "2d/costmap.gd"],
		["/global_costmap/costmap", "nav_msgs/msg/OccupancyGrid", false, "2d/costmap.gd"],
		["/local_costmap/costmap", "nav_msgs/msg/OccupancyGrid", true, "2d/costmap.gd"],
		["/map", "nav_msgs/msg/OccupancyGrid", false, "3d/mapa.gd"],
		["/vita/mapa_tesela", "std_msgs/msg/UInt8MultiArray", true, "2d/mapa.gd"],
	]
	for k in casos:
		var r := Registro.regla(k[0], k[1], k[2])
		check(String(r.get("script", "")).ends_with(k[3]), "registro: %s → %s" % [k[0], k[3]])


# ---------------------------------------------------------------------------------------------------------------
# Vita simulada (loopback): Mapa + Costmap compuestos; Costmap solo
# ---------------------------------------------------------------------------------------------------------------
func _probar_vita() -> void:
	var mapa := _display(D + "2d/mapa.gd", "Mapa", {"topic": "/map", "tipo": "nav_msgs/msg/OccupancyGrid"})
	var cm := _display(D + "2d/costmap.gd", "Costmap", {"topic": "/global_costmap/costmap", "tipo": "nav_msgs/msg/OccupancyGrid"})
	var v := _visor(true, [mapa, cm])
	await _esperar(v)
	check(cm.estado == "ok" and cm.canal.compacto and cm.canal.topic_abierto == "/vita/costmap_tesela",
			"Vita: costmap suscrito a /vita/costmap_tesela")
	check(not cm.latched and cm.cupo == 1 and mapa.costmap_encima == cm.costmap, "Vita: best effort, 1 quad, enganchado al Mapa")
	var nodo = v.contexto.nodo
	var be = v.contexto.qos(true, 1, false)
	var fiable = v.contexto.qos(false, 1, true)
	var p_mmeta = nodo.create_publisher("/vita/mapa_meta", "std_msgs/msg/Float32MultiArray", fiable)
	var p_mtes = nodo.create_publisher("/vita/mapa_tesela", "std_msgs/msg/UInt8MultiArray", be)
	var p_cmeta = nodo.create_publisher("/vita/costmap_meta", "std_msgs/msg/Float32MultiArray", fiable)
	var p_ctes = nodo.create_publisher("/vita/costmap_tesela", "std_msgs/msg/UInt8MultiArray", be)
	# Solo costmap (aún sin mapa): el Costmap dibuja su propia textura.
	var rej := _rejilla(70, 37)
	var t := _teselas(rej, 70, 37, 0.05, 1)
	p_cmeta.publish(_meta(0.1, t.w, t.h, -1.0, -2.0, 1))
	await _fotogramas(2)
	for b in t.teselas:
		p_ctes.publish(_arr("std_msgs/msg/UInt8MultiArray", b))
	await _fotogramas(4)
	check(cm.costmap.teselas == 4 and not cm.compuesto() and cm.costmap.textura != null, "Vita sin mapa: 4 teselas, textura propia")
	check(cm.visible, "Vita sin mapa: el costmap se ve")
	# Llega el mapa (80×50 a 5 cm): el Mapa pasa a dibujar la composición.
	var rm := PackedInt32Array()
	for y in 50:
		for x in 80:
			rm.append(0 if (x + y) % 9 else 100)
	p_mmeta.publish(_arr("std_msgs/msg/Float32MultiArray", PackedFloat32Array([0.05, 80, 50, -1.5, -2.5, 3, 2, 1])))
	await _fotogramas(2)
	for ty in 2:
		for tx in 3:
			p_mtes.publish(_arr("std_msgs/msg/UInt8MultiArray", VC1.empaquetar_tesela(rm, 80, 50, tx, ty, 1)))
	await _fotogramas(4)
	await _esperar_composicion(cm.costmap)
	check(mapa.mapa.teselas == 6 and cm.compuesto() and mapa._compone(), "Vita: mapa + costmap → composición")
	check(mapa.costmap_encima.textura_compuesta != null
			and mapa.costmap_encima.compuesta.get_size() == Vector2i(80, 50), "Vita: textura compuesta con la geometría del mapa")
	var img: Image = mapa.costmap_encima.compuesta
	var celda_mapa: Color = mapa.mapa.relay.mapa_img.get_pixel(2, 2)
	check(img.get_pixel(2, 2) == celda_mapa, "Vita: fuera del costmap, el píxel del mapa")
	var cx := (40 - 10) / 2
	var cy := (50 - 1 - 20 - 10) / 2
	var esp: Color = mapa.mapa.relay.mapa_img.get_pixel(40, 20).blend(cm.costmap.color_nivel(VC1.celda_costmap_4bit(t.d[cy * t.w + cx])))
	var real: Color = img.get_pixel(40, 20)
	check(absf(real.r - esp.r) <= 2.0 / 255.0 and absf(real.b - esp.b) <= 2.0 / 255.0, "Vita: dentro, mapa ⊕ costmap")
	# Actualización parcial por la red: una tesela del costmap cambia → la composición la recoge.
	var cambio := rej.duplicate()
	for k in cambio.size():
		cambio[k] = 100
	var t2 := _teselas(cambio, 70, 37, 0.05, 1)
	var antes: int = cm.costmap.version
	p_ctes.publish(_arr("std_msgs/msg/UInt8MultiArray", t2.teselas[0]))
	await _fotogramas(2)
	await _esperar_composicion(cm.costmap)
	var p_letal: Color = mapa.costmap_encima.compuesta.get_pixel(12, 38)      # celda (1, 0) del costmap
	var letal: Color = mapa.mapa.relay.mapa_img.get_pixel(12, 38).blend(cm.costmap.color_nivel(15))
	check(cm.costmap.version != antes and absf(p_letal.r - letal.r) <= 2.0 / 255.0 and absf(p_letal.g - letal.g) <= 2.0 / 255.0
			and absf(p_letal.b - letal.b) <= 2.0 / 255.0, "Vita: actualización parcial compuesta (letal en la tesela (0, 0))")
	# Época nueva del costmap: imagen vacía; la composición queda solo con el mapa en esa zona.
	p_cmeta.publish(_meta(0.1, t.w, t.h, -1.0, -2.0, 2))
	await _fotogramas(2)
	check(cm.costmap.epoca == 2 and cm.costmap.img.get_pixel(1, 18).a8 == 0, "Vita: época nueva del costmap → vacío")
	p_ctes.publish(_arr("std_msgs/msg/UInt8MultiArray", t.teselas[0]))   # época 1: se descarta
	await _fotogramas(3)
	check(cm.costmap.img.get_pixel(1, 18).a8 == 0 and cm.costmap.descartadas >= 1, "Vita: tesela de la época vieja descartada")
	await _cerrar(v)

	# Costmap sin display Mapa: dibuja su textura propia, no busca destino.
	var solo := _display(D + "2d/costmap.gd", "Costmap", {"topic": "/global_costmap/costmap", "tipo": "nav_msgs/msg/OccupancyGrid"})
	var v2 := _visor(true, [solo])
	await _esperar(v2)
	check(solo.estado == "ok" and solo._destino == null, "Vita: costmap solo, sin Mapa de destino")
	await _cerrar(v2)


# ---------------------------------------------------------------------------------------------------------------
# PC: OccupancyGrid con la paleta costmap (sin relay)
# ---------------------------------------------------------------------------------------------------------------
func _probar_pc() -> void:
	var cm := _display(D + "2d/costmap.gd", "Costmap", {"topic": "/global_costmap/costmap", "tipo": "nav_msgs/msg/OccupancyGrid"})
	var v := _visor(false, [cm])
	await _esperar(v)
	check(cm.estado == "ok" and not cm.canal.compacto and cm.latched, "PC: OccupancyGrid directo, latched")
	var g = RosMsg.from_type("nav_msgs/msg/OccupancyGrid")
	g.header.frame_id = "map"
	g.info.resolution = 0.05
	g.info.width = 4
	g.info.height = 2
	g.info.origin.orientation.w = 1.0
	g.data = PackedInt32Array([0, 50, 99, 100, -1, 0, 0, 0])
	var b: PackedByteArray = g.serialize()
	var r = RosMsg.from_type("nav_msgs/msg/OccupancyGrid")
	r.deserialize(b)
	cm._al_mensaje(r)
	var img: Image = cm.mapa.textura.get_image()
	check(img.get_pixel(0, 1).a8 == 0, "PC: 0 libre transparente")
	check(img.get_pixel(2, 1).to_rgba32() == Color8(0, 255, 255).to_rgba32() and img.get_pixel(3, 1).to_rgba32() == Color8(255, 0, 255).to_rgba32(),
			"PC: 99 inscrito cian, 100 letal magenta (paleta costmap de RViz)")
	check(img.get_pixel(0, 0).to_rgba32() == Color8(0x70, 0x89, 0x86).to_rgba32(), "PC: −1 desconocido 0x708986")
	await _cerrar(v)
