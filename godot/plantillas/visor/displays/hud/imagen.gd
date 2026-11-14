extends "res://comun/visor/display_ros_hud.gd"
## Imagen (V10; doc 36a §4.5.5 y §4.5.6; sentencia W13 D13): widget HUD de la pestaña Cámara.
##   PC y Vita: `sensor_msgs/CompressedImage` jpeg/png (en la Vita, `<p>/camara/compressed` del relay: JPEG ≤ 160×120
##          q40, ≤ 2 994 B, FIABLE, 3 Hz). Decodifica el MOTOR (`Image.load_jpg_from_buffer`/`load_png_from_buffer`,
##          H22): nada de bucles por píxel en GDScript (trampa T5). `compressedDepth` (PNG de 16 bit) se rechaza: el
##          cargador de Godot lo baja a 8 bit (trampa T4).
##   Solo PC: `sensor_msgs/Image` de 8 bit (rgb8, rgba8, bgr8, bgra8, mono8, 8UC1, 8UC3) con `Image.set_data` sin
##          conversión; BGR se corrige con un *shader* `canvas_item` (la Vita no tiene *shaders*, pero nunca recibe
##          imagen cruda: D13). Profundidad (16UC1, 32FC1) y filas con relleno (`step ≠ ancho·bpp`) se rechazan.
## Dibujo: UN `draw_texture_rect` ajustado al widget conservando el aspecto (1 *quad*); misma textura reutilizada con
## `ImageTexture.update` si no cambian tamaño ni formato (H19, trampa T26). `rect_imagen()` da dónde quedó la imagen
## (lo usa `hud/cajas_2d.gd` para poner las cajas encima). Gate E-W8-5: `ms_ultimo` = decodificar + subir (≤ 6 ms en
## la Vita, sin medir [I]).

## encoding → [formato de Image, bytes por píxel, ¿BGR?]
const CRUDOS := {
	"rgb8": [Image.FORMAT_RGB8, 3, false], "rgba8": [Image.FORMAT_RGBA8, 4, false],
	"bgr8": [Image.FORMAT_RGB8, 3, true], "bgra8": [Image.FORMAT_RGBA8, 4, true], "8UC3": [Image.FORMAT_RGB8, 3, true],
	"mono8": [Image.FORMAT_L8, 1, false], "8UC1": [Image.FORMAT_L8, 1, false],
}
const SHADER_BGR := "shader_type canvas_item;\nvoid fragment() { COLOR.rgb = COLOR.bgr; }\n"
const MAX_CAR := 30

var textura: ImageTexture
var tam_imagen := Vector2i.ZERO               # tamaño de la imagen decodificada
var imagenes := 0                             # imágenes mostradas
var rechazadas := 0                           # formato o codificación no soportados, o datos corruptos
var motivo := ""                              # última causa de rechazo (se pinta si no hay imagen)
var ms_ultimo := 0.0                          # decodificar + subir la última (gate E-W8-5)
var ms_max := 0.0
var _img := Image.new()
var _bgr := false


static func nombre_display() -> String:
	return "Imagen"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["sensor_msgs/msg/CompressedImage", "sensor_msgs/msg/Image"])


func _init() -> void:
	tipo = "sensor_msgs/msg/CompressedImage"
	topic_vita = "camara/compressed"
	tipo_vita = "sensor_msgs/msg/CompressedImage"
	fiabilidad = 2                            # FIABLE: ≈ 3 KB no cabe en 488 B (doc 36 §6)
	profundidad = 1
	hz = 15.0
	hz_vita = 3.0
	caducidad_s = 2.0


func _procesar(msg):
	var t0 := Time.get_ticks_usec()
	var err := ERR_INVALID_DATA
	_bgr = false
	if canal.tipo_abierto == "sensor_msgs/msg/Image":
		err = _cruda(msg)
	else:
		var f := String(msg.format)
		if "compresseddepth" in f.to_lower():
			return _rechazar("compressedDepth (16 bit, T4)")
		var data: PackedByteArray = msg.data
		err = _img.load_png_from_buffer(data) if "png" in f.to_lower() else _img.load_jpg_from_buffer(data)
		if err != OK:
			return _rechazar("no se pudo decodificar «%s»" % f.left(16))
	if err != OK:
		return null
	ms_ultimo = (Time.get_ticks_usec() - t0) / 1000.0     # se completa con la subida en _pintar
	return _img


## sensor_msgs/Image de 8 bit → `_img` sin conversión. Devuelve OK o un error (con `motivo`).
func _cruda(msg) -> int:
	var enc := String(msg.encoding)
	if not CRUDOS.has(enc):
		_rechazar("codificación «%s» no soportada" % enc)
		return ERR_UNAVAILABLE
	var w := int(msg.width)
	var h := int(msg.height)
	var bpp: int = CRUDOS[enc][1]
	var data: PackedByteArray = msg.data
	if w <= 0 or h <= 0 or int(msg.step) != w * bpp or data.size() < w * h * bpp:
		_rechazar("step o tamaño no válidos")
		return ERR_INVALID_DATA
	_img.set_data(w, h, false, CRUDOS[enc][0], data.slice(0, w * h * bpp) if data.size() > w * h * bpp else data)
	_bgr = CRUDOS[enc][2]
	return OK


func _rechazar(m: String):
	rechazadas += 1
	motivo = m
	return null


func _pintar(img) -> void:
	var t0 := Time.get_ticks_usec()
	if textura == null or Vector2i(textura.get_size()) != img.get_size() or textura.get_format() != img.get_format():
		textura = ImageTexture.create_from_image(img)
	else:
		textura.update(img)                   # mismo tamaño y formato: sin realojar (H19)
	tam_imagen = img.get_size()
	ms_ultimo += (Time.get_ticks_usec() - t0) / 1000.0
	ms_max = maxf(ms_max, ms_ultimo)
	imagenes += 1
	_poner_material_bgr(_bgr)
	queue_redraw()


func _poner_material_bgr(bgr: bool) -> void:
	if not bgr or (visor != null and visor.en_vita):
		material = null
		return
	if material == null:
		var sh := Shader.new()
		sh.code = SHADER_BGR
		var m := ShaderMaterial.new()
		m.shader = sh
		material = m


## Dónde queda la imagen dentro del widget (coordenadas locales), ajustada conservando el aspecto.
func rect_imagen() -> Rect2:
	if tam_imagen.x <= 0 or tam_imagen.y <= 0 or size.x <= 0 or size.y <= 0:
		return Rect2(Vector2.ZERO, size)
	var k := minf(size.x / tam_imagen.x, size.y / tam_imagen.y)
	var s := Vector2(tam_imagen) * k
	return Rect2((size - s) * 0.5, s)


func _dibujar() -> bool:
	rect(Rect2(Vector2.ZERO, size), COLOR_FONDO)
	if textura == null:
		texto(Vector2(6, 16), "Cámara: " + (motivo if motivo != "" else estado), color_estado(COLOR_TEXTO), MAX_CAR)
		return true
	draw_texture_rect(textura, rect_imagen(), false, Color(1, 1, 1, 0.4) if gris else Color.WHITE)
	_q += 1
	return true


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 2 + MAX_CAR}
