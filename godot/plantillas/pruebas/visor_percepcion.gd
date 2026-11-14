extends SceneTree
## Prueba de host de V10 (percepción; doc 36 §5.3 y §10; doc 36a §4.5.3, §4.5.5, §4.5.6, §4.8.4, §4.8.5; sentencia
## W13 D12 y D13). Transporte `loopback`:
##   - bytes Python = GDScript: `vc1.gd` (bloque «percepción») da los MISMOS float32 / int16 que
##     `vita_relay_formatos.py` (huellas de `docker/scripts/test_vita_relay.py`: det2d, det3d y nube); tamaños CDR
##     reales ≤ 488 B por datagrama (472, 464 y 480 B);
##   - registro: relay y tipos estándar → hud/imagen, hud/cajas_2d, 2d/cajas_3d, 2d/nube;
##   - imagen: JPEG 160×120 q40 (≤ 2 994 B) decodificado por el motor (tiempo de decodificar + subir: E-W8-5 en la
##     Vita, aquí solo se imprime), textura reutilizada, PNG, compressedDepth rechazado; cruda en el PC (rgb8, bgr8
##     con *shader*, mono8; 16UC1 y step con relleno rechazados);
##   - cajas 2D (Vita simulada): relay `detecciones` + `det_clases`, ≤ 150 *quads*, umbral, caducidad;
##   - cajas 3D (Vita simulada): relay `detecciones3d`, aristas proyectadas, etiquetas en TextoSuperpuesto, cupo;
##     directo (PC) con un Detection3DArray falso (vision_msgs no está en el esquema);
##   - nube (Vita simulada): 3 trozos → una nube, trozo perdido, `process` ≤ 2 ms por trozo (gate V10, medido en el
##     host); PointCloud2 directo (PC) con NaN y diezmado;
##   - escena `godot/visor-ros/main_percepcion.tscn` (hereda `main.tscn`): pestaña Cámara, nube y cajas 3D con cupo.
##
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_percepcion.gd

const VisorRos = preload("res://comun/visor/visor_ros.gd")
const Texto = preload("res://comun/visor/texto_superpuesto.gd")
const Registro = preload("res://comun/visor/registro_displays.gd")
const VC1 = preload("res://comun/ros/vc1.gd")
const D := "res://comun/visor/displays/"

## Huellas de `docker/scripts/test_vita_relay.py` (HUELLA_DET2D / _DET3D / _NUBE).
const HUELLA_DET2D := "ee2ba52555c851eb7215e34e3e29df65"
const HUELLA_DET3D := "85721035f7b1d215bcd3006fc4c5bcde"
const HUELLA_NUBE := "749401e964f564fdba18ef774a5e8333"


## Objeto ROS falso (tipos sin esquema: vision_msgs).
class Falso:
	extends RefCounted
	var _m := {}

	func _init(m: Dictionary) -> void:
		_m = m

	func _get(n: StringName):
		return _m.get(String(n))

	func get_member(n: String):
		return _m.get(n)


class Vigia:
	extends Logger
	var errores := 0
	var ultimo := ""

	func _log_error(_f: String, file: String, _l: int, code: String, rationale: String, _e: bool, tipo: int,
			_b: Array[ScriptBacktrace]) -> void:
		if tipo == ERROR_TYPE_SCRIPT or (tipo == ERROR_TYPE_ERROR and file.contains("/visor/")):
			errores += 1
			ultimo = "%s: %s %s" % [file, code, rationale]

	func _log_message(_m: String, _e: bool) -> void:
		pass


var fallos := 0
var pruebas := 0
var vigia := Vigia.new()


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
	_probar_bytes_percepcion()
	_probar_registro()
	await _probar_imagen()
	await _probar_imagen_cruda()
	await _probar_cajas_2d()
	await _probar_cajas_3d()
	await _probar_nube()
	await _probar_escena()
	check(vigia.errores == 0, "sin errores de script en visor/ (%s)" % vigia.ultimo)
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


func _f32(datos: Array):
	var m = RosMsg.from_type("std_msgs/msg/Float32MultiArray")
	m.data = PackedFloat32Array(datos)
	return m


func _i16(datos: Array):
	var m = RosMsg.from_type("std_msgs/msg/Int16MultiArray")
	m.data = PackedInt32Array(datos)
	return m


func _cadena(s: String):
	var m = RosMsg.from_type("std_msgs/msg/String")
	m.data = s
	return m


## VisorRos de prueba: `hud` = widgets HUD (bajo Hud) y `planos` = displays 2D (bajo Marcas2D).
func _visor(en_vita: bool, hud: Array, planos: Array) -> Node:
	var v: Node = VisorRos.new()
	v.name = "VisorPrueba"
	v.transporte = "loopback"
	v.config_json = ""
	v.reintento_s = 0.0
	v.en_vita = en_vita
	var capa := CanvasLayer.new()
	capa.name = "Marcas2D"
	v.add_child(capa)
	for d in planos:
		capa.add_child(d)
	var h := CanvasLayer.new()
	h.name = "Hud"
	v.add_child(h)
	var t: Control = Texto.new()
	t.name = "Texto"
	h.add_child(t)
	v.texto = t
	for w in hud:
		h.add_child(w)
	var raiz := Node3D.new()
	raiz.name = "Escena"
	var cam := Camera3D.new()
	cam.position = Vector3(0, 6, 6)
	raiz.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3.ZERO)
	raiz.add_child(v)
	root.add_child(raiz)
	cam.current = true
	v.camara = cam
	return v


func _cerrar(v: Node) -> void:
	v.get_parent().queue_free()
	await _fotogramas(2)


func _huella_f32(datos: Array) -> String:
	return PackedFloat32Array(datos).to_byte_array().hex_encode().md5_text()


func _huella_int(datos: Array) -> String:
	var s := PackedStringArray()
	for x in datos:
		s.append(str(int(x)))
	return ",".join(s).md5_text()


# ---------------------------------------------------------------------------------------------------------------
# Bytes: vc1.gd = vita_relay_formatos.py (mismos vectores que test_vita_relay.py)
# ---------------------------------------------------------------------------------------------------------------
func _vector_det2d() -> Array:
	var out := []
	for i in 22:
		out.append([i % 4, ((i * 7) % 20) / 20.0, 10.0 + i * 25.5, 20.0 + i * 12.25, 30.0 + (i % 5) * 8, 40.0 + (i % 3) * 10])
	out[5][2] = NAN
	return out


func _vector_det3d() -> Array:
	var out := []
	for i in 15:
		out.append([i % 3, ((i * 3) % 10) / 10.0, i * 0.5 - 3.0, 1.0 - i * 0.25, 0.125 * (i % 4), -1.5 + i * 0.2,
			0.5 + (i % 3) * 0.25, 0.4, 1.7])
	out[4][1] = NAN
	return out


@warning_ignore("integer_division")
func _vector_nube() -> Array:
	var out := []
	for i in 1200:
		var x := NAN if i % 97 == 0 else -4.0 + (i % 40) * 0.07
		out.append([x, -2.0 + (i / 40) * 0.13, 0.05 * (i % 7) - 0.1])
	return out


func _probar_bytes_percepcion() -> void:
	var d2: Array = VC1.empaquetar_det2d(_vector_det2d(), 640, 480, 70001)
	check(d2.size() == 114 and d2[3] == 18 and d2[0] == (70001 & 0x7FFF) and _f32(d2).serialize().size() + 4 == 472,
			"bytes: det2d = 18 cajas de 22 (una NaN), 472 B (CDR real)")
	check(_huella_f32(d2) == HUELLA_DET2D, "bytes: detecciones = vita_relay_formatos (float32 idénticos)")
	var r2: Dictionary = VC1.leer_det2d(PackedFloat32Array(d2))
	check(r2.ancho == 640.0 and r2.cajas.size() == 18 and r2.cajas[0][1] >= r2.cajas[17][1], "det2d: lectura ordenada por score")
	var d3: Array = VC1.empaquetar_det3d(_vector_det3d(), 9)
	check(d3.size() == 112 and d3[3] == 12 and _f32(d3).serialize().size() + 4 == 464, "bytes: det3d = 12 de 15, 464 B")
	check(_huella_f32(d3) == HUELLA_DET3D, "bytes: detecciones3d = vita_relay_formatos")
	check(VC1.leer_det3d(PackedFloat32Array(d3)).size() == 12, "det3d: lectura")
	var pts: Array = VC1.voxelizar_nube(_vector_nube())
	var tn: Array = VC1.empaquetar_nube(pts, 123)
	var plano := []
	var tam_ok := true
	for t in tn:
		plano.append_array(t)
		tam_ok = tam_ok and _i16(t).serialize().size() + 4 <= 480
	check(tn.size() == 3 and tn[0][3] == 76 and tam_ok and _i16(tn[0]).serialize().size() + 4 == 480,
			"bytes: nube = 3 trozos de ≤ 76 puntos, ≤ 480 B (%d puntos)" % pts.size())
	check(_huella_int(plano) == HUELLA_NUBE, "bytes: nube2d = vita_relay_formatos (int16 idénticos)")
	check(VC1.empaquetar_nube([], 4) == [[4, 0, 1, 0]] and VC1.voxelizar_nube([[INF, 0.0, 0.0]]).is_empty(),
			"nube vacía = un trozo con n = 0; Inf fuera")
	check(VC1.leer_det_clases("persona,coche,a;b") == PackedStringArray(["persona", "coche", "a;b"]), "det_clases: lectura")


func _probar_registro() -> void:
	var casos := [
		["/vita/detecciones", "std_msgs/msg/Float32MultiArray", true, "hud/cajas_2d.gd"],
		["/vita/detecciones3d", "std_msgs/msg/Float32MultiArray", true, "2d/cajas_3d.gd"],
		["/vita/nube2d", "std_msgs/msg/Int16MultiArray", true, "2d/nube.gd"],
		["/vita/camara/compressed", "sensor_msgs/msg/CompressedImage", true, "hud/imagen.gd"],
		["/camera/image_raw", "sensor_msgs/msg/Image", false, "hud/imagen.gd"],
		["/points", "sensor_msgs/msg/PointCloud2", false, "2d/nube.gd"],
		["/detections", "vision_msgs/msg/Detection2DArray", false, "hud/cajas_2d.gd"],
		["/detections_3d", "vision_msgs/msg/Detection3DArray", false, "2d/cajas_3d.gd"],
	]
	for c in casos:
		check(Registro.regla(c[0], c[1], c[2]).get("script", "") == D + c[3], "registro: %s → %s" % [c[0], c[3]])
	check(Registro.regla("/camera/image_raw", "sensor_msgs/msg/Image", true).get("script", "") != D + "hud/imagen.gd",
			"registro: Image cruda solo en el PC (D13)")


# ---------------------------------------------------------------------------------------------------------------
# Imagen
# ---------------------------------------------------------------------------------------------------------------
func _imagen_prueba(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for k in 8:
		img.fill_rect(Rect2i(k * w / 8, 0, w / 8, h), Color.from_hsv(k / 8.0, 0.7, 0.9))
	img.fill_rect(Rect2i(w / 4, h / 4, w / 3, h / 3), Color(0.1, 0.1, 0.1))
	return img


func _comprimida(datos: PackedByteArray, formato: String):
	var m = RosMsg.from_type("sensor_msgs/msg/CompressedImage")
	m.header.frame_id = "camara"
	m.format = formato
	m.data = datos
	return m


func _widget(script: String, nombre: String, tam := Vector2(320, 240)) -> Control:
	var w: Control = load(D + script).new()
	w.name = nombre
	w.size = tam
	return w


func _probar_imagen() -> void:
	var im := _widget("hud/imagen.gd", "Imagen")
	var v := _visor(true, [im], [])
	await _esperar(v)
	check(im.canal.compacto and im.canal.topic_abierto == "/vita/camara/compressed"
			and im.canal.tipo_abierto == "sensor_msgs/msg/CompressedImage", "Vita: imagen por el relay camara/compressed")
	var jpg := _imagen_prueba(160, 120).save_jpg_to_buffer(0.4)
	var m = _comprimida(jpg, "jpeg")
	var tam: int = m.serialize().size() + 4
	print("imagen: JPEG 160×120 q40 = %d B de datos, %d B de mensaje" % [jpg.size(), tam])
	check(tam <= 2994, "imagen: JPEG 160×120 q40 ≤ 2 994 B con rosbags (%d B)" % tam)
	im._al_mensaje(m)
	await _fotogramas(2)
	check(im.textura != null and im.tam_imagen == Vector2i(160, 120) and im.imagenes == 1 and im.dibujos > 0,
			"imagen: JPEG decodificado por el motor y dibujado")
	print("imagen: decodificar + subir = %.2f ms (host; E-W8-5 en la Vita ≤ 6 ms)" % im.ms_ultimo)
	var tex: ImageTexture = im.textura
	im._al_mensaje(_comprimida(_imagen_prueba(160, 120).save_jpg_to_buffer(0.6), "jpeg"))
	check(im.textura == tex and im.imagenes == 2, "imagen: mismo tamaño → misma textura (update, H19)")
	var r: Rect2 = im.rect_imagen()
	check(r.size.is_equal_approx(Vector2(320, 240)) and im.quads_dibujados <= im._coste().quads, "imagen: ajuste con aspecto y quads ≤ coste")
	im.size = Vector2(320, 120)
	check(im.rect_imagen().is_equal_approx(Rect2(Vector2(80, 0), Vector2(160, 120))), "imagen: aspecto 4:3 centrado")
	im._al_mensaje(_comprimida(_imagen_prueba(64, 48).save_png_to_buffer(), "png"))
	check(im.tam_imagen == Vector2i(64, 48) and im.textura != tex, "imagen: PNG y cambio de tamaño → textura nueva")
	var antes: int = im.imagenes
	im._al_mensaje(_comprimida(PackedByteArray([1, 2, 3]), "16UC1; compressedDepth"))
	im._al_mensaje(_comprimida(PackedByteArray([1, 2, 3]), "jpeg"))
	check(im.imagenes == antes and im.rechazadas == 2, "imagen: compressedDepth (T4) y datos rotos rechazados")
	# Revisión V3: PNG de 16 bit de image_transport «compressed» (no compressedDepth) también fuera (T4).
	im._al_mensaje(_comprimida(_imagen_prueba(64, 48).save_png_to_buffer(), "16UC1; png compressed "))
	check(im.imagenes == antes and im.rechazadas == 3 and im.es_formato_profundo("mono16; png compressed")
			and not im.es_formato_profundo("rgb8; jpeg compressed bgr8") and not im.es_formato_profundo("jpeg"),
			"imagen: PNG de 16 bit («16UC1; png compressed») rechazado; jpeg/rgb8 no")
	# 30 imágenes: el tiempo máximo (host) para el informe
	for i in 30:
		im._al_mensaje(_comprimida(_imagen_prueba(160, 120).save_jpg_to_buffer(0.4), "jpeg"))
	print("imagen: máx. decodificar + subir en 30 JPEG = %.2f ms (host)" % im.ms_max)
	check(im.ms_max < 50.0, "imagen: decodificar + subir acotado en el host")
	await _cerrar(v)


func _cruda(enc: String, w: int, h: int, step: int, datos: PackedByteArray):
	var m = RosMsg.from_type("sensor_msgs/msg/Image")
	m.encoding = enc
	m.width = w
	m.height = h
	m.step = step
	m.data = datos
	return m


func _probar_imagen_cruda() -> void:
	var im := _widget("hud/imagen.gd", "ImagenCruda")
	im.topic = "/camera/image_raw"
	im.tipo = "sensor_msgs/msg/Image"
	var v := _visor(false, [im], [])
	await _esperar(v)
	check(not im.canal.compacto and im.canal.tipo_abierto == "sensor_msgs/msg/Image", "PC: imagen cruda directa")
	var img := _imagen_prueba(32, 24)
	im._al_mensaje(_cruda("rgb8", 32, 24, 96, img.get_data()))
	check(im.tam_imagen == Vector2i(32, 24) and im.textura.get_format() == Image.FORMAT_RGB8 and im.material == null,
			"cruda: rgb8 sin conversión")
	im._al_mensaje(_cruda("bgr8", 32, 24, 96, img.get_data()))
	check(im.material is ShaderMaterial, "cruda: bgr8 con shader canvas_item (solo PC)")
	var gris := PackedByteArray()
	gris.resize(32 * 24)
	im._al_mensaje(_cruda("mono8", 32, 24, 32, gris))
	check(im.textura.get_format() == Image.FORMAT_L8 and im.material == null, "cruda: mono8 = L8")
	var antes: int = im.imagenes
	im._al_mensaje(_cruda("16UC1", 32, 24, 64, gris + gris))
	im._al_mensaje(_cruda("rgb8", 32, 24, 100, img.get_data()))
	check(im.imagenes == antes and im.rechazadas == 2, "cruda: 16UC1 y step con relleno rechazados")
	await _fotogramas(2)
	await _cerrar(v)


# ---------------------------------------------------------------------------------------------------------------
# Cajas 2D
# ---------------------------------------------------------------------------------------------------------------
func _probar_cajas_2d() -> void:
	var im := _widget("hud/imagen.gd", "Imagen")
	var cj := _widget("hud/cajas_2d.gd", "Cajas2D")
	cj.imagen = im
	cj.umbral_score = 0.0
	var v := _visor(true, [im, cj], [])
	await _esperar(v)
	check(cj.canal.topic_abierto == "/vita/detecciones" and cj.clases.canal.topic_abierto == "/vita/det_clases"
			and cj.fiabilidad == 0, "Vita: cajas 2D por el relay (best effort) + det_clases latched")
	im._al_mensaje(_comprimida(_imagen_prueba(160, 120).save_jpg_to_buffer(0.4), "jpeg"))
	var cajas := []
	for i in 20:
		cajas.append([i % 3, 1.0 - i * 0.04, 40.0 + i * 28.0, 60.0 + i * 18.0, 60.0, 80.0])
	cj._al_mensaje(_f32(VC1.empaquetar_det2d(cajas, 640, 480, 1)))
	await _fotogramas(2)
	check(cj.datos != null and cj.datos[1].size() == 18 and cj.cajas_dibujadas == 18, "cajas 2D: 18 del relay dibujadas")
	check(cj.quads_dibujados <= 150 and cj.etiquetas_dibujadas > 0, "cajas 2D: ≤ 150 quads (%d, %d etiquetas)"
			% [cj.quads_dibujados, cj.etiquetas_dibujadas])
	check(cj._etiqueta(cj.datos[1][0][1]) == "0", "cajas 2D: sin det_clases, el índice")
	cj.clases.al_texto(_cadena("persona,coche,perro"))
	await _fotogramas(2)
	check(cj._etiqueta(cj.datos[1][1][1]) == "coche" and cj._etiqueta(-1) == "?", "cajas 2D: nombres de det_clases")
	var z: Rect2 = cj.zona()
	check(z.is_equal_approx(Rect2(Vector2.ZERO, Vector2(320, 240))), "cajas 2D: sobre el rect de la imagen")
	cj.umbral_score = 0.5
	cj._al_mensaje(_f32(VC1.empaquetar_det2d(cajas, 640, 480, 2)))
	check(cj.datos[1].size() == 13, "cajas 2D: umbral de score (≥ 0,5 → 13)")
	# PC directo con un Detection2DArray falso
	var det := []
	for i in 3:
		det.append(Falso.new({"id": "d%d" % i, "results": [Falso.new({"hypothesis": Falso.new({"class_id": "gato", "score": 0.4 + i * 0.2})})],
			"bbox": Falso.new({"center": Falso.new({"position": Falso.new({"x": 100.0 + i, "y": 50.0}), "theta": 0.0}),
				"size_x": 20.0, "size_y": 10.0})}))
	var r = cj._procesar(Falso.new({"detections": det}))
	check(r[1].size() == 2 and r[1][0][1] == "gato" and is_equal_approx(r[1][0][2], 0.8) and r[1][0][0] == Rect2(92, 45, 20, 10),
			"cajas 2D directo: mejor hipótesis, umbral y rect en px")
	await _cerrar(v)


# ---------------------------------------------------------------------------------------------------------------
# Cajas 3D
# ---------------------------------------------------------------------------------------------------------------
@warning_ignore("integer_division")
func _probar_cajas_3d() -> void:
	var c3: Node2D = load(D + "2d/cajas_3d.gd").new()
	c3.name = "Cajas3D"
	c3.umbral_score = 0.0
	var v := _visor(true, [], [c3])
	await _esperar(v)
	check(c3.canal.topic_abierto == "/vita/detecciones3d" and c3.clases.canal.topic_abierto == "/vita/det_clases",
			"Vita: cajas 3D por el relay + det_clases")
	check(c3.cupo == 144, "Vita HMI: 12 cajas × 12 aristas = 144 quads de resto_2d")
	var cajas := []
	for i in 12:
		cajas.append([i % 2, 0.9, (i % 4) * 0.8 - 1.2, (i / 4) * 0.8 - 0.8, 0.5, 0.3 * i, 0.6, 0.4, 1.0])
	c3._al_mensaje(_f32(VC1.empaquetar_det3d(cajas, 1)))
	await _fotogramas(3)
	check(c3.cajas_dibujadas == 12 and c3.quads_dibujados == 144 and v.texto.cuantos() == 12,
			"cajas 3D: 12 cajas proyectadas (144 aristas) y 12 etiquetas")
	var e: PackedVector3Array = c3._cajas[0][0]
	var centro := Vector3.ZERO
	for p in e:
		centro += p
	centro /= 8.0
	check(centro.is_equal_approx(rclgd.ros_to_godot_vector(Vector3(-1.2, -0.8, 0.5))), "cajas 3D: centro ROS → Godot")
	check(is_equal_approx(e[0].distance_to(e[7]), Vector3(0.6, 0.4, 1.0).length()), "cajas 3D: diagonal = tamaño")
	c3._al_mensaje(_f32(VC1.empaquetar_det3d(cajas.slice(0, 3), 2)))
	await _fotogramas(2)
	check(c3.cajas_dibujadas == 3 and v.texto.cuantos() == 3, "cajas 3D: menos cajas → se quitan sus etiquetas")
	c3._caducar()
	check(v.texto.cuantos() == 0 and not c3.visible, "cajas 3D: caducado → oculto y sin etiquetas")
	# PC directo con un Detection3DArray falso
	var P := func(x, y, z): return Falso.new({"x": x, "y": y, "z": z})
	var det := [Falso.new({"id": "", "results": [Falso.new({"hypothesis": Falso.new({"class_id": "caja", "score": 0.7})})],
		"bbox": Falso.new({"center": Falso.new({"position": P.call(1.0, 2.0, 0.5),
			"orientation": Falso.new({"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0})}), "size": P.call(2.0, 1.0, 0.5)})})]
	var r = c3._procesar(Falso.new({"detections": det}))
	var esperada: Vector3 = rclgd.ros_to_godot_vector(Vector3(1, 2, 0.5)) + Vector3(0.5, 0.25, 1.0)
	check(r.size() == 1 and r[0][1] == "caja" and r[0][0][7].is_equal_approx(esperada), "cajas 3D directo: esquinas en ejes Godot")
	await _cerrar(v)


# ---------------------------------------------------------------------------------------------------------------
# Nube
# ---------------------------------------------------------------------------------------------------------------
func _probar_nube() -> void:
	var nb: Node2D = load(D + "2d/nube.gd").new()
	nb.name = "Nube"
	var v := _visor(true, [], [nb])
	await _esperar(v)
	check(nb.canal.compacto and nb.canal.topic_abierto == "/vita/nube2d" and not nb.canal.coalescer and nb.cupo == 228,
			"Vita: nube por el relay, todos los trozos, cupo 228")
	var pts: Array = VC1.voxelizar_nube(_vector_nube())
	var tn: Array = VC1.empaquetar_nube(pts, 7)
	nb._al_mensaje(_i16(tn[0]))
	check(nb.nubes_completas == 0, "nube: un trozo no completa la nube")
	nb._al_mensaje(_i16(tn[1]))
	nb._al_mensaje(_i16(tn[2]))
	await _fotogramas(2)
	check(nb.nubes_completas == 1 and nb.puntos_dibujados == pts.size(), "nube: 3 trozos → %d puntos dibujados" % pts.size())
	print("nube: process por trozo de 76 puntos = %d µs (máx. %d; gate V10 ≤ 2 000 µs en la Vita)"
			% [nb.us_ultimo_trozo, nb.us_max_trozo])
	check(nb.us_max_trozo <= 2000, "nube: process ≤ 2 ms por trozo (host)")
	# Trozo perdido: seq 8 llega sin el trozo 2; al empezar seq 9 se enseña lo que llegó de la 8
	var t8: Array = VC1.empaquetar_nube(pts, 8)
	nb._al_mensaje(_i16(t8[0]))
	nb._al_mensaje(_i16(t8[1]))
	await _fotogramas(2)
	check(nb.puntos_dibujados == pts.size(), "nube: incompleta → se sigue viendo la anterior")
	nb._al_mensaje(_i16(VC1.empaquetar_nube(pts, 9)[0]))
	await _fotogramas(2)
	check(nb.puntos_dibujados == 152, "nube: empieza otra → se ve la incompleta (2 trozos = 152 puntos)")
	# Color por altura: z baja = azul, alta = rojo
	check(nb._color_z(-1.0).b > 0.9 and nb._color_z(5.0).r > 0.9, "nube: color por banda de altura")
	await _cerrar(v)
	# PC directo: PointCloud2 xyz FLOAT32 con NaN y diezmado
	var nd: Node2D = load(D + "2d/nube.gd").new()
	nd.name = "NubePC"
	nd.topic = "/points"
	nd.max_puntos_pc = 100
	var v2 := _visor(false, [], [nd])
	await _esperar(v2)
	check(not nd.canal.compacto and nd.canal.tipo_abierto == "sensor_msgs/msg/PointCloud2", "PC: PointCloud2 directo")
	var m = RosMsg.from_type("sensor_msgs/msg/PointCloud2")
	var campos := []
	for k in 3:
		var f = RosMsg.from_type("sensor_msgs/msg/PointField")
		f.name = ["x", "y", "z"][k]
		f.offset = 4 * k
		f.datatype = 7
		f.count = 1
		campos.append(f)
	m.fields = campos
	var datos := PackedFloat32Array()
	for i in 1000:
		datos.append_array([NAN if i % 7 == 3 else i * 0.01, 1.0, 0.5, 0.0])   # point_step 16 (x, y, z, relleno)
	m.width = 1000
	m.height = 1
	m.point_step = 16
	m.row_step = 16000
	m.data = datos.to_byte_array()
	var r = nd._procesar(m)
	check(r != null and r[3].size() == 3 * 85, "PointCloud2: diezmado a 100 y NaN fuera → 85 puntos")
	m.is_bigendian = true
	check(nd._procesar(m) == null and nd.rechazadas == 1, "PointCloud2: big endian rechazado (T28)")
	await _cerrar(v2)


# ---------------------------------------------------------------------------------------------------------------
# Escena de ejemplo: godot/visor-ros/main_percepcion.tscn
# ---------------------------------------------------------------------------------------------------------------
func _probar_escena() -> void:
	if not ResourceLoader.exists("res://main_percepcion.tscn"):
		print("(sin main_percepcion.tscn en este proyecto: se salta)")
		return
	var raiz: Node = load("res://main_percepcion.tscn").instantiate()
	var v: Node = raiz.get_node("VisorRos")
	v.transporte = "loopback"
	v.config_json = ""
	v.reintento_s = 0.0
	v.en_vita = true
	root.add_child(raiz)
	await _esperar(v)
	await _fotogramas(2)
	var nb: Node = v.get_node("Planta/Vista/Nube")
	var c3: Node = v.get_node("Marcas2D/Cajas3D")
	var im: Node = v.get_node("Hud/GestorHud/Pestanas/Camara/Imagen")
	var cj: Node = v.get_node("Hud/GestorHud/Pestanas/Camara/Cajas2D")
	check(nb.canal.topic_abierto == "/vita/nube2d" and c3.canal.topic_abierto == "/vita/detecciones3d"
			and im.canal.topic_abierto == "/vita/camara/compressed" and cj.canal.topic_abierto == "/vita/detecciones",
			"escena: los 4 displays de percepción por el relay")
	# Juez V3 (D2): con Mapa 1 + Costmap 1 + Plan 112 + Nube 228 + Scan 360 quedan 98 para Odom; la escena lo dice
	# (`max_rastro = 98`, propiedad editable, doc 35) y la zona sensores_2d suma 800 justos, sin recorte ni aviso.
	var od: Node = v.get_node("Planta/Vista/Odom")
	check(od.max_rastro == 98 and od._coste().quads == 98 and od.cupo == 98 and v.usado("sensores_2d") == 800,
			"escena: Odom pide 98 quads y recibe %d; sensores_2d = %d (800 justos)" % [od.cupo, v.usado("sensores_2d")])
	var od_main: Node = load("res://main.tscn").instantiate()
	check(od_main.get_node("VisorRos/Planta/Vista/Odom")._coste().quads == 100,
			"escena: en main.tscn Odom sigue pidiendo 100 quads (doc 36 §7.2)")
	od_main.free()
	check(nb.cupo == 228 and c3.cupo == 144 and cj.imagen == im, "escena: cupos (nube 228, cajas 3D 144 de resto_2d) y cajas sobre la imagen")
	var g: Node = v.get_node("Hud/GestorHud")
	var k := -1
	for i in g.num_pestanas():
		if g.pestana(i).name == "Camara":
			k = i
	g.mostrar(k)
	await _fotogramas(2)
	check(k >= 0 and g.quads_declarados(g.pestana(k)) <= 240, "escena: pestaña Cámara ≤ 240 quads declarados (%d)"
			% g.quads_declarados(g.pestana(k)))
	raiz.queue_free()
	await _fotogramas(2)
