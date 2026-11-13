extends RefCounted
## PaletaViz (ADR 0013 §2; doc 36 §3.3; W13 D2): color de TODO el 3D del visor con una textura-paleta 16×16
## (256 colores) y UN material compartido. Cada vértice lleva la UV del centro del texel de su color; con el filtro
## POINT (forzado en el 3D de la Vita, H15 de docs/31) sale el color exacto, y varios colores caben en una sola
## malla (ejes RGB, listas horneadas) sin color por vértice (H3) ni un material por color.
##
## El texel 255 tiene alfa 0: con un solo píxel con alfa, el port de la Vita marca la textura «con alfa» y excluye
## la malla de la pasada de luz por vértice (H8: ni *draw* doble ni el riesgo H7). Sin medir en hardware: gate
## E-W8-1 (`[gxm3d] lit=` = 0 con 80 instancias). En el PC el material es opaco (el alfa del texel se ignora).
##
## Reparto de índices [I, doc 36 §3.3]: 0–15 con nombre (abajo), 16–231 cubo RGB 6×6×6, 232–254 grises,
## 255 transparente. Uso: `const Paleta = preload("res://comun/visor/paleta_viz.gd")` (sin `class_name`, D15).
##
## También están aquí las paletas de raster (D2 funde `paletas.gd` de mapas#1–#2): `rampa_mapa()` = ports
## literales de makeMapPalette/makeCostmapPalette/makeRawPalette (rviz `palette_builder.cpp:87-152`, Jazzy) y
## `lut16_costmap()` para la tesela de 4 bit de la Vita (doc 36 §4.6.2, V11).

## Colores de estado de rqt_robot_monitor (`util_robot_monitor.py:48-54`). STALE sustituirá al gris provisional
## `COLOR_CADUCADO` del HUD de V1 (lo hace quien toque `display_ros_hud.gd`).
const OK := Color8(85, 178, 76)
const WARN := Color8(222, 213, 17)
const ERROR := Color8(178, 23, 46)
const STALE := Color8(40, 23, 176)

## Índices con nombre (los que usan las primitivas y los displays; mejor el nombre que el número).
const BLANCO := 0
const NEGRO := 1
const ROJO := 2                                # eje X de ROS (REP-103)
const VERDE := 3                               # eje Y
const AZUL := 4                                # eje Z
const AMARILLO := 5
const CIAN := 6
const MAGENTA := 7
const NARANJA := 8
const GRIS := 9
const I_OK := 10
const I_WARN := 11
const I_ERROR := 12
const I_STALE := 13
const FLECHA_RVIZ := 14                        # color por defecto de Pose/Odometry en RViz
const PATH_RVIZ := 15                          # color por defecto de Path en RViz
const TRANSPARENTE := 255

const NOMBRADOS := [Color.WHITE, Color.BLACK, Color(0.9, 0.1, 0.1), Color(0.1, 0.8, 0.2), Color(0.15, 0.35, 1.0),
	Color.YELLOW, Color.CYAN, Color.MAGENTA, Color.ORANGE, Color.GRAY, OK, WARN, ERROR, STALE,
	Color(1.0, 0.1, 0.0), Color(0.1, 1.0, 0.0)]

## Tope de la caché color → índice: un display con colores arbitrarios (Marker) no debe hacerla crecer sin fin.
const MAX_CACHE := 1024

static var _img: Image
static var _mat: StandardMaterial3D
static var _cache := {}                        # Color.to_rgba32() -> índice


## Imagen 16×16 de la paleta (se calcula una vez: 256 píxeles).
static func imagen() -> Image:
	if _img == null:
		# Bytes con redondeo (`r8`, como `to_rgba32`): `set_pixel` trunca (0,1 → 25, no 26) y el texel no
		# casaría con `color(i)` en 8 bit.
		var p := PackedByteArray()
		p.resize(1024)
		for i in 256:
			var c := _calcular(i)
			p[4 * i] = c.r8
			p[4 * i + 1] = c.g8
			p[4 * i + 2] = c.b8
			p[4 * i + 3] = c.a8
		_img = Image.create_from_data(16, 16, false, Image.FORMAT_RGBA8, p)
	return _img


static func _calcular(i: int) -> Color:
	if i < 16:
		return NOMBRADOS[i]
	if i < 232:
		var k := i - 16
		return Color(float(k / 36) / 5.0, float((k / 6) % 6) / 5.0, float(k % 6) / 5.0)
	if i < 255:
		return Color.from_hsv(0.0, 0.0, float(i - 232) / 22.0)
	return Color(0, 0, 0, 0)                   # texel de alfa 0: fuera de la pasada de luz (H8)


## Color del índice (con el alfa pedido; la textura conserva el suyo).
static func color(i: int, alfa := 1.0) -> Color:
	var c := _calcular(clampi(i, 0, 255))
	c.a = alfa
	return c


## UV del centro del texel `i` (lo que lleva cada vértice de ese color).
static func uv(i: int) -> Vector2:
	var k := clampi(i, 0, 255)
	return Vector2((k % 16) + 0.5, (k / 16) + 0.5) / 16.0


## Índice del color más cercano en RGB (sin el 255 transparente; el alfa se ignora). Cacheado: la búsqueda
## lineal de 255 colores solo se paga la primera vez que aparece un color.
static func indice(c: Color) -> int:
	var k := c.to_rgba32()
	if _cache.has(k):
		return _cache[k]
	var mejor := 0
	var dmin := INF
	for i in 255:
		var p := _calcular(i)
		var d := Vector3(p.r - c.r, p.g - c.g, p.b - c.b).length_squared()
		if d < dmin:
			dmin = d
			mejor = i
	if _cache.size() >= MAX_CACHE:
		_cache.clear()
	_cache[k] = mejor
	return mejor


## std_msgs/ColorRGBA (RosMsg) → Color (nucleo#14).
static func de_ros(c) -> Color:
	return Color(c.r, c.g, c.b, c.a)


## EL material de todas las primitivas del visor. Unshaded en el PC (en la Vita no consta efecto [?]; manda H8),
## filtro NEAREST (colores exactos) y sin *culling* (H15: cintas y tubos sin tapa se ven por las dos caras).
## La opción «sombreado» (material por color, `albedo.a = 0,99` o con luz; D2 «reversión») iría aquí y en
## `PrimitivasViz.instancia()`; no se usa en V2.
static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_texture = ImageTexture.create_from_image(imagen())
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat


# --- Paletas de raster (mapas#1–#2; rviz palette_builder.cpp:87-152) ----------------------------------------------

enum { ESQUEMA_MAP, ESQUEMA_COSTMAP, ESQUEMA_RAW }


## Paleta 256×1 RGBA8 del esquema de RViz (índice = byte crudo del int8; −1 → 255). `binaria` y `umbral` son
## «Binary representation» y «Binary threshold» del Map display (umbral 100 por defecto, como RViz).
static func rampa_mapa(esquema: int, binaria := false, umbral := 100) -> Image:
	match esquema:
		ESQUEMA_COSTMAP:
			return _costmap(binaria, umbral)
		ESQUEMA_RAW:
			return _raw(binaria, umbral)
	return _mapa(binaria, umbral)


## Ilegales y desconocido, comunes a map y costmap (makeMapPalette / makeCostmapPalette).
static func _base_ilegales() -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(1024)
	for i in range(101, 128):                  # ilegales positivos: verde
		p[4 * i + 1] = 255
		p[4 * i + 3] = 255
	for i in range(128, 255):                  # ilegales negativos: rojo → amarillo
		p[4 * i] = 255
		p[4 * i + 1] = 255 * (i - 128) / (254 - 128)
		p[4 * i + 3] = 255
	p[1020] = 0x70                             # 255 = −1 desconocido: 0x708986
	p[1021] = 0x89
	p[1022] = 0x86
	p[1023] = 255
	return p


static func _mapa(binaria: bool, umbral: int) -> Image:
	var p := _base_ilegales()
	for i in 101:
		var v := 255 - 255 * i / 100           # libre blanco → ocupado negro
		if binaria:
			v = 255 if i < umbral else 0
		p[4 * i] = v
		p[4 * i + 1] = v
		p[4 * i + 2] = v
		p[4 * i + 3] = 255
	return Image.create_from_data(256, 1, false, Image.FORMAT_RGBA8, p)


static func _costmap(binaria: bool, umbral: int) -> Image:
	var p := _base_ilegales()
	for i in 101:
		var c := Color8(0, 0, 0, 255)
		if binaria:
			c = Color8(0, 0, 255) if i < umbral else Color8(255, 0, 0)
		elif i == 0:
			c = Color8(0, 0, 0, 0)                  # libre: transparente
		elif i <= 98:
			var v := 255 * i / 100
			c = Color8(v, 0, 255 - v)               # azul → rojo
		elif i == 99:
			c = Color8(0, 255, 255)                 # inscrito: cian
		else:
			c = Color8(255, 0, 255)                 # letal: magenta
		p[4 * i] = c.r8
		p[4 * i + 1] = c.g8
		p[4 * i + 2] = c.b8
		p[4 * i + 3] = c.a8
	return Image.create_from_data(256, 1, false, Image.FORMAT_RGBA8, p)


static func _raw(binaria: bool, umbral: int) -> Image:
	var p := PackedByteArray()
	p.resize(1024)
	for i in 256:
		var v := i
		if binaria:
			v = 0 if i < umbral else 255
		p[4 * i] = v
		p[4 * i + 1] = v
		p[4 * i + 2] = v
		p[4 * i + 3] = 255
	return Image.create_from_data(256, 1, false, Image.FORMAT_RGBA8, p)


## LUT de 16 niveles de `<p>/costmap_tesela` (4 bit; doc 36 §4.6.2): 0 desconocido, 1 libre (transparente),
## 2–13 degradado, 14 inscrito, 15 letal. Sacada de la misma paleta costmap (índices de mapas#1).
static func lut16_costmap() -> PackedColorArray:
	var img := _costmap(false, 100)
	var out := PackedColorArray()
	for i in [255, 0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 98, 99, 100]:
		out.append(img.get_pixel(i, 0))
	return out
