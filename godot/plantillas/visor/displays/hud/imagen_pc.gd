extends "res://comun/visor/displays/hud/imagen.gd"
## Imagen cruda con *shader* (V14, `solo_pc`; doc 36a §4.5.5 sens#6–8): amplía `hud/imagen.gd` con lo que en V10 se
## rechazaba. Los bytes de `sensor_msgs/Image` suben SIN conversión (un `Image.set_data` por mensaje) y el color lo
## pone un *shader* `canvas_item` (cero bucles por píxel en GDScript, trampa T5):
##
## | `encoding` | Textura | Modo del *shader* |
## |---|---|---|
## | `rgb8`, `rgba8`, `mono8`, `8UC1` | RGB8 / RGBA8 / L8 | 0 directo |
## | `bgr8`, `bgra8`, `8UC3` | RGB8 / RGBA8 | 1 `.bgr` |
## | `16UC1`, `mono16` | RG8 (byte bajo en R, alto en G: exacto, sin depender de `FORMAT_R16`) | 2 escalar 16 bit |
## | `32FC1` | RF | 3 escalar float |
## | `bayer_rggb8`, `bayer_bggr8`, `bayer_gbrg8`, `bayer_grbg8` | L8 | 4 demosaico 2×2 (superpíxel) |
## | `yuv422` (= `uyvy`), `uyvy`, `yuyv`, `yuv422_yuy2` | RGBA8 de ancho/2 | 5 / 6 YUV → RGB (BT.601 completo [I]) |
##
## Escalares (profundidad): `16UC1` en mm (REP-118) × `escala_16` (0,001 → m) y `32FC1` en m; 0, NaN e Inf quedan
## transparentes (`cero_transparente`); color con `mapa_color` (MapasColor: turbo por defecto, arcoíris de RViz o
## gris) entre `rango` o, con `rango_auto` («Normalize Range» de RViz), el mín./máx. de una muestra de ≤ 4 096
## píxeles. `mono16` es intensidad: gris y sin transparencia.
## Filas con relleno (`step ≠ ancho·bpp`): la textura toma el ancho de `step` y se dibuja solo la región útil
## (`draw_texture_rect_region`): sin copia por fila.
## Sigue sin cubrir (doc 36a §9.3): `16SC1`, `64FC1`, `nv21`/`nv24`, color de 16 bit, `bayer_*16`.
## Dibujo: el fondo y el texto en el widget y la imagen en un hijo `Lienzo` con el material (así el *shader* no toca
## el fondo). La Vita no carga este script (`solo_pc`, sin *shaders*; D13: nunca recibe imagen cruda).

const MapasColor = preload("res://comun/visor/mapas_color.gd")

enum { DIRECTO, BGR, ESCALAR16, ESCALAR32, BAYER, UYVY, YUYV }

## encoding → [formato de Image, bytes por píxel de la TEXTURA, píxeles de imagen por texel, modo, patrón bayer]
const PC := {
	"rgb8": [Image.FORMAT_RGB8, 3, 1, DIRECTO, 0], "rgba8": [Image.FORMAT_RGBA8, 4, 1, DIRECTO, 0],
	"bgr8": [Image.FORMAT_RGB8, 3, 1, BGR, 0], "bgra8": [Image.FORMAT_RGBA8, 4, 1, BGR, 0],
	"8UC3": [Image.FORMAT_RGB8, 3, 1, BGR, 0],
	"mono8": [Image.FORMAT_L8, 1, 1, DIRECTO, 0], "8UC1": [Image.FORMAT_L8, 1, 1, DIRECTO, 0],
	"16UC1": [Image.FORMAT_RG8, 2, 1, ESCALAR16, 0], "mono16": [Image.FORMAT_RG8, 2, 1, ESCALAR16, 0],
	"32FC1": [Image.FORMAT_RF, 4, 1, ESCALAR32, 0],
	"bayer_rggb8": [Image.FORMAT_L8, 1, 1, BAYER, 0], "bayer_bggr8": [Image.FORMAT_L8, 1, 1, BAYER, 1],
	"bayer_gbrg8": [Image.FORMAT_L8, 1, 1, BAYER, 2], "bayer_grbg8": [Image.FORMAT_L8, 1, 1, BAYER, 3],
	"yuv422": [Image.FORMAT_RGBA8, 4, 2, UYVY, 0], "uyvy": [Image.FORMAT_RGBA8, 4, 2, UYVY, 0],
	"yuyv": [Image.FORMAT_RGBA8, 4, 2, YUYV, 0], "yuv422_yuy2": [Image.FORMAT_RGBA8, 4, 2, YUYV, 0],
}

@export_enum("arcoiris", "turbo", "gris") var mapa_color := 1
@export var rango_auto := true
@export var rango := Vector2(0.2, 5.0)        # m (16UC1 ya escalado, 32FC1) o crudo (mono16) si no hay auto
@export var escala_16 := 0.001                # 16UC1: mm → m (REP-118)
@export var cero_transparente := true         # profundidad: 0/NaN/Inf transparentes

var modo := DIRECTO
var patron := 0
var rango_usado := Vector2.ZERO
var lienzo: Control                           # hijo que dibuja la imagen con el material
var material_imagen: ShaderMaterial
var _util := Vector2i.ZERO                    # píxeles de imagen útiles (sin relleno de fila)
var _tex_util := Vector2i.ZERO                # región útil en texeles
var _ultima_codificacion := ""

static var _shader: Shader


static func nombre_display() -> String:
	return "ImagenPC"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["sensor_msgs/msg/Image", "sensor_msgs/msg/CompressedImage"])


func _init() -> void:                         # el _init de imagen.gd ya corrió (implícito)
	tipo = "sensor_msgs/msg/Image"
	solo_pc = true
	topic_vita = ""                           # en la Vita no existe (D13)


func conectar(v) -> void:
	super.conectar(v)
	if lienzo == null:
		material_imagen = ShaderMaterial.new()
		if _shader == null:
			_shader = Shader.new()
			_shader.code = SHADER
		material_imagen.shader = _shader
		lienzo = Control.new()
		lienzo.name = "Lienzo"
		lienzo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lienzo.set_anchors_preset(Control.PRESET_FULL_RECT)
		lienzo.material = material_imagen
		lienzo.draw.connect(_dibujar_imagen)
		add_child(lienzo)                     # sin owner (doc 35)


## sensor_msgs/Image → `_img` sin conversión (ver la tabla). Devuelve OK o un error (con `motivo`).
func _cruda(msg) -> int:
	var enc := String(msg.encoding)
	if not PC.has(enc):
		_rechazar("codificación «%s» no soportada" % enc)
		return ERR_UNAVAILABLE
	var e: Array = PC[enc]
	var w := int(msg.width)
	var h := int(msg.height)
	var step := int(msg.step)
	var bpp_tex: int = e[1]
	var por_texel: int = e[2]
	var data: PackedByteArray = msg.data
	if w <= 0 or h <= 0 or w % por_texel != 0:
		_rechazar("tamaño no válido")
		return ERR_INVALID_DATA
	var util_bytes := w / por_texel * bpp_tex
	if step < util_bytes or step % bpp_tex != 0 or data.size() < step * (h - 1) + util_bytes:
		_rechazar("step o tamaño no válidos")
		return ERR_INVALID_DATA
	var ancho_tex := step / bpp_tex           # con relleno: la textura toma el ancho de step
	var n := ancho_tex * h * bpp_tex
	if data.size() < n:                       # la última fila puede venir sin relleno
		data = data.duplicate()
		data.resize(n)
	_img.set_data(ancho_tex, h, false, e[0], data if data.size() == n else data.slice(0, n))
	modo = e[3]
	patron = e[4]
	_util = Vector2i(w, h)
	_tex_util = Vector2i(w / por_texel, h)
	_bgr = false                              # el BGR lo hace el material del lienzo, no el del widget
	if modo == ESCALAR16 or modo == ESCALAR32:
		var es_prof := enc != "mono16"
		var esc := escala_16 if enc == "16UC1" else 1.0
		rango_usado = _rango_auto(data, ancho_tex, w, h, bpp_tex, esc, es_prof) if rango_auto else rango
	return OK


## Mín./máx. de una muestra de ≤ 4 096 píxeles (sin 0/NaN/Inf en profundidad).
static func _rango_auto(b: PackedByteArray, ancho_tex: int, w: int, h: int, bpp: int, esc: float, prof: bool) -> Vector2:
	var n := w * h
	var s := maxi(1, n / 4096)
	var mn := INF
	var mx := -INF
	for i in range(0, n, s):
		var o := ((i / w) * ancho_tex + i % w) * bpp
		var val: float = b.decode_float(o) if bpp == 4 else b.decode_u16(o) * esc
		if not is_finite(val) or (prof and val <= 0.0):
			continue
		mn = minf(mn, val)
		mx = maxf(mx, val)
	if mn > mx:
		return Vector2(0, 1)
	if mx - mn < 1e-6:
		mx = mn + 1.0
	return Vector2(mn, mx)


func _pintar(img) -> void:
	super._pintar(img)
	tam_imagen = _util if canal.tipo_abierto == "sensor_msgs/msg/Image" else img.get_size()
	if canal.tipo_abierto != "sensor_msgs/msg/Image":
		modo = DIRECTO
		_tex_util = img.get_size()
	var m := material_imagen
	if m != null:
		m.set_shader_parameter("modo", modo)
		m.set_shader_parameter("patron", patron)
		m.set_shader_parameter("rango", rango_usado)
		m.set_shader_parameter("escala", escala_16 if _ultima_codificacion == "16UC1" else 1.0)
		m.set_shader_parameter("cero_transparente", cero_transparente and _es_profundidad())
		m.set_shader_parameter("mapa", MapasColor.textura(MapasColor.GRIS if not _es_profundidad() else mapa_color))


func _es_profundidad() -> bool:
	return modo == ESCALAR32 or (modo == ESCALAR16 and _ultima_codificacion != "mono16")


func _procesar(msg):
	if canal.tipo_abierto == "sensor_msgs/msg/Image":
		_ultima_codificacion = String(msg.encoding)
	return super._procesar(msg)


## El widget no lleva material (el fondo no pasa por el *shader*).
func _poner_material_bgr(_bgr_: bool) -> void:
	material = null


func _dibujar() -> bool:
	rect(Rect2(Vector2.ZERO, size), COLOR_FONDO)
	if textura == null:
		texto(Vector2(6, 16), "Cámara: " + (motivo if motivo != "" else estado), color_estado(COLOR_TEXTO), MAX_CAR)
		return true
	_q += 1
	if lienzo != null:
		lienzo.queue_redraw()
	return true


func _dibujar_imagen() -> void:
	if textura == null:
		return
	lienzo.draw_texture_rect_region(textura, rect_imagen(), Rect2(Vector2.ZERO, _tex_util),
			Color(1, 1, 1, 0.4) if gris else Color.WHITE)


## Color de un píxel como lo pinta el *shader* en los modos escalares (para pruebas): valor ya en unidades.
func color_escalar(v: float) -> Color:
	if not is_finite(v) or (cero_transparente and _es_profundidad() and v <= 0.0):
		return Color(0, 0, 0, 0)
	var t := clampf((v - rango_usado.x) / maxf(rango_usado.y - rango_usado.x, 1e-6), 0.0, 1.0)
	return MapasColor.color(MapasColor.GRIS if not _es_profundidad() else mapa_color, int(t * 255.0 + 0.5))


const SHADER := """shader_type canvas_item;
uniform int modo = 0;
uniform int patron = 0;
uniform vec2 rango = vec2(0.0, 1.0);
uniform float escala = 0.001;
uniform bool cero_transparente = true;
uniform sampler2D mapa : filter_nearest;
varying vec4 modulado;

void vertex() { modulado = COLOR; }

vec4 escalar(float v) {
	if (isnan(v) || isinf(v) || (cero_transparente && v <= 0.0)) return vec4(0.0);
	float t = clamp((v - rango.x) / max(rango.y - rango.x, 1e-6), 0.0, 1.0);
	return texelFetch(mapa, ivec2(int(t * 255.0 + 0.5), 0), 0);
}

vec3 yuv(float y, float u, float v) {
	u -= 0.5; v -= 0.5;
	return clamp(vec3(y + 1.402 * v, y - 0.344136 * u - 0.714136 * v, y + 1.772 * u), 0.0, 1.0);
}

void fragment() {
	ivec2 ts = textureSize(TEXTURE, 0);
	vec4 c;
	if (modo == 0) {
		c = texelFetch(TEXTURE, clamp(ivec2(UV * vec2(ts)), ivec2(0), ts - 1), 0);
	} else if (modo == 1) {
		c = texelFetch(TEXTURE, clamp(ivec2(UV * vec2(ts)), ivec2(0), ts - 1), 0).bgra;
	} else if (modo == 2) {
		vec4 t = texelFetch(TEXTURE, clamp(ivec2(UV * vec2(ts)), ivec2(0), ts - 1), 0);
		float crudo = floor(t.r * 255.0 + 0.5) + 256.0 * floor(t.g * 255.0 + 0.5);
		c = escalar(crudo * escala);
	} else if (modo == 3) {
		c = escalar(texelFetch(TEXTURE, clamp(ivec2(UV * vec2(ts)), ivec2(0), ts - 1), 0).r);
	} else if (modo == 4) {
		ivec2 p = clamp(ivec2(UV * vec2(ts)), ivec2(0), ts - 1);
		ivec2 b = min(p - (p % 2), ts - 2);
		float a = texelFetch(TEXTURE, b, 0).r;
		float bb = texelFetch(TEXTURE, b + ivec2(1, 0), 0).r;
		float cc = texelFetch(TEXTURE, b + ivec2(0, 1), 0).r;
		float d = texelFetch(TEXTURE, b + ivec2(1, 1), 0).r;
		vec3 rgb;
		if (patron == 0) rgb = vec3(a, 0.5 * (bb + cc), d);
		else if (patron == 1) rgb = vec3(d, 0.5 * (bb + cc), a);
		else if (patron == 2) rgb = vec3(cc, 0.5 * (a + d), bb);
		else rgb = vec3(bb, 0.5 * (a + d), cc);
		c = vec4(rgb, 1.0);
	} else {
		int x = int(UV.x * float(ts.x) * 2.0);
		ivec2 p = clamp(ivec2(x / 2, int(UV.y * float(ts.y))), ivec2(0), ts - 1);
		vec4 t = texelFetch(TEXTURE, p, 0);
		if (modo == 5) c = vec4(yuv((x % 2 == 0) ? t.g : t.a, t.r, t.b), 1.0);
		else c = vec4(yuv((x % 2 == 0) ? t.r : t.b, t.g, t.a), 1.0);
	}
	COLOR = c * modulado;
}
"""
