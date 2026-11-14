extends RefCounted
## MapaTextura (V3; doc 36a §4.6.1): estado común de `displays/2d/mapa.gd` y `displays/3d/mapa.gd`.
## No es un display: guarda la textura del mapa y su geometría, la llenen un `OccupancyGrid` entero (camino
## estándar, PC) o las teselas VC/1 del relay (camino compacto, Vita: `<p>/mapa_meta` + `<p>/mapa_tesela`).
##
## Dato intermedio que entregan `de_grid()` y `de_tesela()` (el MISMO en los dos caminos, doc 36 §2.5):
##   {"img": Image RGBA8 norte arriba (null en el compacto: la imagen la lleva VitaRelay), "res": m/celda,
##    "ancho", "alto": celdas, "origen": Vector2 (m, esquina de la celda (0,0) en el marco del mapa), "yaw": rad}
##
## V14 (solo PC, `gpu = true`; lo pone el display fuera de la Vita): el `OccupancyGrid` sube TAL CUAL como textura
## `R8` de índices (byte crudo del int8, −1 → 255; `flip_y` nativo para el norte arriba) y el color lo busca un
## *shader* en la paleta 256×1 de RViz (`PaletaViz.rampa_mapa`, `texelFetch`), como `map_display.cpp`: **sin bucle
## por celda** en GDScript (resuelve el DESAFÍO de V1). Materiales: `material_canvas()` (planta 2D) y
## `material_espacial()` (quad 3D). Dato intermedio: `img` = R8 de índices y `indices = true`.
## Sin `gpu` (la Vita no tiene *shaders*, D2): la rampa se aplica en CPU con un bucle por celda (384² ≈ 147 k); en la
## Vita este camino no se usa (un mapa no cabe, docs/27:65: llega por teselas). En el compacto la paleta se reduce a
## los 3 colores de VC/1 (2 bit).

const VitaRelay = preload("res://comun/vita_relay.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")

var relay = VitaRelay.new()          # camino compacto: teselas → relay.mapa_img / relay.mapa_tex
var textura: ImageTexture            # la que se dibuja (la propia o la del relay)
var res := 0.05
var ancho := 0
var alto := 0
var origen := Vector2.ZERO
var yaw := 0.0
var esquema := Paleta.ESQUEMA_MAP
var version := 0                     # sube cada vez que cambia la textura o su geometría (los displays redibujan)
var gpu := false                     # V14: índices R8 + paleta en *shader* (solo PC; la Vita deja false)
var indices := false                 # V14: la `textura` actual es de índices (necesita el material con paleta)
var binaria := false                 # «Binary representation» de RViz (solo con `gpu`: cambia la paleta)
var umbral := 100

static var _sh_canvas: Shader        # V14: *shaders* compartidos (se compilan una vez)
static var _sh_espacial: Shader
var _paleta: ImageTexture            # V14: paleta 256×1 del esquema
var _mat_canvas: ShaderMaterial
var _mat_espacial: ShaderMaterial

# Medida de la decodificación de teselas (criterio de V3 en hardware: ≤ 1,5 ms por tesela).
var teselas := 0
var us_ultima := 0
var us_max := 0
var _us_suma := 0
var _n_ventana := 0
var _t_informe := 0

var _sub_meta                        # suscripción a <p>/mapa_meta (sin anotar: RosSubscriber, T7)
var _lut32 := PackedInt32Array()     # rampa de la paleta como RGBA8 en un int32 (little endian), 256 entradas
var _bytes := PackedByteArray()


## Camino compacto: suscribe la meta *latched* aparte (la tesela es el topic del display).
func conectar_compacto(v) -> void:
	_sub_meta = v.contexto.nodo.create_subscription(v.prefijo_compacto.trim_suffix("/") + "/mapa_meta",
			"std_msgs/msg/Float32MultiArray", _al_meta, v.contexto.qos(false, 1, true))


func cerrar() -> void:
	_sub_meta = null


func _al_meta(m) -> void:
	relay.on_mapa_meta(m)
	version += 1


## OccupancyGrid (RosMsg) → dato intermedio con la imagen ya en colores. null si el mensaje no es válido.
func de_grid(msg):
	var info = msg.info
	var w: int = info.width
	var h: int = info.height
	var data = msg.data                  # ros2_vita: int8[] → PackedInt32Array (T6); rclgd: puede ser bytes [?]
	if w <= 0 or h <= 0 or data.size() < w * h:
		return null
	var celdas: PackedByteArray
	if data is PackedByteArray:
		celdas = data
	elif data is Array:                  # rclgd puede dar un Array genérico [?]: un paso a PackedInt32Array
		var tmp0 := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, PackedInt32Array(data).slice(0, w * h).to_byte_array())
		tmp0.convert(Image.FORMAT_R8)
		celdas = tmp0.get_data()
	else:
		# Byte bajo de cada int32 (−1 → 255) sin bucle: RGBA8 con el int32 little endian y conversión a R8.
		var tmp := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, PackedInt32Array(data).slice(0, w * h).to_byte_array())
		tmp.convert(Image.FORMAT_R8)
		celdas = tmp.get_data()
	var img: Image
	if gpu:
		# V14: índices crudos en R8 (sin bucle); la fila 0 del OccupancyGrid va abajo → flip_y nativo.
		img = Image.create_from_data(w, h, false, Image.FORMAT_R8, celdas if celdas.size() == w * h else celdas.slice(0, w * h))
		img.flip_y()
	else:
		if _lut32.is_empty():
			_lut32 = Paleta.rampa_mapa(esquema).get_data().to_int32_array()
		# Fila 0 del OccupancyGrid abajo; imagen con la fila 0 arriba (norte arriba).
		_bytes.resize(w * h * 4)
		for y in h:
			var o := (h - 1 - y) * w * 4
			var c := y * w
			for x in w:
				_bytes.encode_u32(o + 4 * x, _lut32[celdas[c + x]])
		img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, _bytes)
	var org = info.origin
	var q := Quaternion(org.orientation.x, org.orientation.y, org.orientation.z, org.orientation.w)
	var giro := 0.0
	if q.length_squared() > 1e-6:
		q = q.normalized()
		giro = atan2(2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z))
	return {"img": img, "res": float(info.resolution), "ancho": w, "alto": h,
			"origen": Vector2(org.position.x, org.position.y), "yaw": giro, "indices": gpu}


## Tesela VC/1 (UInt8MultiArray) → la decodifica en la imagen del relay (LUT + blit_rect) y devuelve la
## geometría (img = null: la textura es la del relay). null si aún no llegó la meta.
func de_tesela(msg):
	var t := Time.get_ticks_usec()
	relay.on_mapa_tesela(msg)
	us_ultima = Time.get_ticks_usec() - t
	us_max = maxi(us_max, us_ultima)
	_us_suma += us_ultima
	_n_ventana += 1
	teselas += 1
	if relay.mapa_img == null:
		return null
	return {"img": null, "res": relay.resolucion, "ancho": relay.ancho, "alto": relay.alto,
			"origen": relay.origen, "yaw": 0.0}


## Aplica el dato intermedio: geometría y, en el estándar, la textura propia. Devuelve true si algo cambió.
func aplicar(d: Dictionary) -> bool:
	var cambio: bool = d["res"] != res or d["ancho"] != ancho or d["alto"] != alto or d["origen"] != origen \
			or d["yaw"] != yaw
	res = d["res"]
	ancho = d["ancho"]
	alto = d["alto"]
	origen = d["origen"]
	yaw = d["yaw"]
	var img = d["img"]
	if img != null:
		if textura != null and textura != relay.mapa_tex and textura.get_width() == img.get_width() \
				and textura.get_height() == img.get_height() and textura.get_format() == img.get_format():
			textura.update(img)              # mismo tamaño y formato: sin reasignar (T26)
		else:
			textura = ImageTexture.create_from_image(img)
		indices = d.get("indices", false)
		if indices:
			_poner_datos(textura)
		cambio = true
	elif relay.mapa_tex != null and textura != relay.mapa_tex:
		textura = relay.mapa_tex
		indices = false
		cambio = true
	if cambio:
		version += 1
	return cambio


## Una vez por fotograma en el camino compacto: sube la imagen del relay (≤ HZ_TEXTURA) y, en la Vita o con
## `-- perfil`, escribe cada 5 s el coste de las teselas. Devuelve true si la textura cambió.
func tic(informar: bool) -> bool:
	var cambio: bool = relay.actualizar_textura()
	if relay.mapa_tex != null and textura != relay.mapa_tex:
		textura = relay.mapa_tex
		cambio = true
	if cambio:
		version += 1
	if informar:
		var ahora := Time.get_ticks_msec()
		if ahora - _t_informe >= 5000:
			_t_informe = ahora
			if _n_ventana > 0:
				printerr("[visor-mapa] teselas=%d media_us=%d max_us=%d ultima_us=%d" % [
						teselas, _us_suma / _n_ventana, us_max, us_ultima])
				_us_suma = 0
				_n_ventana = 0
	return cambio


# --- V14: paleta en *shader* (solo PC) ------------------------------------------------------------------------------
## Planta 2D (`canvas_item`): `TEXTURE` = índices R8 (la de `draw_texture_rect`); el color de `draw_texture_rect`
## (alfa del display) se multiplica al final. La alfa de la paleta (0 libre transparente en el costmap) se conserva.
const SHADER_CANVAS := """shader_type canvas_item;
uniform sampler2D paleta : filter_nearest;
varying vec4 modulado;
void vertex() { modulado = COLOR; }
void fragment() {
	ivec2 t = textureSize(TEXTURE, 0);
	ivec2 p = clamp(ivec2(UV * vec2(t)), ivec2(0), t - ivec2(1));
	int i = int(texelFetch(TEXTURE, p, 0).r * 255.0 + 0.5);
	COLOR = texelFetch(paleta, ivec2(i, 0), 0) * modulado;
}
"""

## Quad 3D (`spatial`, unshaded, sin *culling*, como el StandardMaterial3D de V3): `datos` = índices R8.
const SHADER_ESPACIAL := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D datos : filter_nearest;
uniform sampler2D paleta : source_color, filter_nearest;
uniform float alfa = 1.0;
void fragment() {
	ivec2 t = textureSize(datos, 0);
	ivec2 p = clamp(ivec2(UV * vec2(t)), ivec2(0), t - ivec2(1));
	int i = int(texelFetch(datos, p, 0).r * 255.0 + 0.5);
	vec4 c = texelFetch(paleta, ivec2(i, 0), 0);
	ALBEDO = c.rgb;
	ALPHA = c.a * alfa;
}
"""


## Paleta 256×1 del esquema (y `binaria`/`umbral`), como textura. Se rehace si cambian.
func textura_paleta() -> ImageTexture:
	if _paleta == null:
		_paleta = ImageTexture.create_from_image(Paleta.rampa_mapa(esquema, binaria, umbral))
	return _paleta


## Cambia esquema/binaria/umbral en caliente: solo se sube otra paleta (los índices no cambian).
func poner_esquema(e: int, bin := false, um := 100) -> void:
	esquema = e
	binaria = bin
	umbral = um
	_lut32 = PackedInt32Array()
	_paleta = null
	if _mat_canvas != null:
		_mat_canvas.set_shader_parameter("paleta", textura_paleta())
	if _mat_espacial != null:
		_mat_espacial.set_shader_parameter("paleta", textura_paleta())
	version += 1


## Material de la planta 2D (índices → paleta). Uno por MapaTextura (cada uno con su paleta).
func material_canvas() -> ShaderMaterial:
	if _mat_canvas == null:
		if _sh_canvas == null:
			_sh_canvas = Shader.new()
			_sh_canvas.code = SHADER_CANVAS
		_mat_canvas = ShaderMaterial.new()
		_mat_canvas.shader = _sh_canvas
		_mat_canvas.set_shader_parameter("paleta", textura_paleta())
	return _mat_canvas


## Material del quad 3D con los índices actuales y la alfa del display.
func material_espacial(alfa := 1.0) -> ShaderMaterial:
	if _mat_espacial == null:
		if _sh_espacial == null:
			_sh_espacial = Shader.new()
			_sh_espacial.code = SHADER_ESPACIAL
		_mat_espacial = ShaderMaterial.new()
		_mat_espacial.shader = _sh_espacial
		_mat_espacial.set_shader_parameter("paleta", textura_paleta())
	_mat_espacial.set_shader_parameter("alfa", alfa)
	if textura != null and indices:
		_mat_espacial.set_shader_parameter("datos", textura)
	return _mat_espacial


func _poner_datos(t: Texture2D) -> void:
	if _mat_espacial != null:
		_mat_espacial.set_shader_parameter("datos", t)


## Lo que el *shader* pinta, calculado en CPU (bucle por celda): SOLO para pruebas y depuración. Con la textura en
## colores (sin `gpu` o en el compacto) devuelve su imagen tal cual.
func imagen_colores() -> Image:
	if textura == null:
		return null
	var img := textura.get_image()
	if not indices:
		return img
	var lut := Paleta.rampa_mapa(esquema, binaria, umbral).get_data().to_int32_array()
	var src := img.get_data()
	var out := PackedByteArray()
	out.resize(src.size() * 4)
	for k in src.size():
		out.encode_u32(4 * k, lut[src[k]])
	return Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, out)
