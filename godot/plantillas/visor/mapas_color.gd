extends RefCounted
## MapasColor (V14, solo PC): rampas de color 256×1 para los *shaders* de la nube (`3d/nube_puntos.gd`) y de la
## imagen de profundidad (`hud/imagen_pc.gd`). Estático: `const MapasColor = preload("res://comun/visor/mapas_color.gd")`.
## Índice 0 = valor mínimo del rango, 255 = máximo.
##   ARCOIRIS: port de `getRainbowColor` de RViz (`rviz_default_plugins/.../point_cloud_transformers.cpp`), con el
##             orden de RViz: `value = 1 − normalizado` (mínimo rojo, máximo magenta); `invertir` le da la vuelta.
##   TURBO   : aproximación polinómica de Turbo (Google AI, 2019; Apache 2.0) — la del «Colormap» de rqt/Foxglove [I].
##   GRIS    : negro → blanco.
## Las rampas viven en la paleta solo PC: la Vita no tiene *shaders* y no las carga (displays `solo_pc`).

enum { ARCOIRIS, TURBO, GRIS }

static var _cache := {}                    # Vector2i(mapa, invertir) → ImageTexture


## Color de RViz para `value` en [0, 1] (getRainbowColor, literal).
static func arcoiris_rviz(value: float) -> Color:
	value = clampf(value, 0.0, 1.0)
	var h := value * 5.0 + 1.0
	var i := floori(h)
	var f := h - i
	if i % 2 == 0:
		f = 1.0 - f
	var n := 1.0 - f
	if i <= 1:
		return Color(n, 0, 1)
	if i == 2:
		return Color(0, n, 1)
	if i == 3:
		return Color(0, 1, n)
	if i == 4:
		return Color(n, 1, 0)
	return Color(1, n, 0)


static func turbo(x: float) -> Color:
	x = clampf(x, 0.0, 1.0)
	var r := 0.13572138 + x * (4.61539260 + x * (-42.66032258 + x * (132.13108234 + x * (-152.94239396 + x * 59.28637943))))
	var g := 0.09140261 + x * (2.19418839 + x * (4.84296658 + x * (-14.18503333 + x * (4.27729857 + x * 2.82956604))))
	var b := 0.10667330 + x * (12.64194608 + x * (-60.58204836 + x * (110.36276771 + x * (-89.90310912 + x * 27.34824973))))
	return Color(clampf(r, 0, 1), clampf(g, 0, 1), clampf(b, 0, 1))


## Color del índice k (0..255) del mapa.
static func color(mapa: int, k: int, invertir := false) -> Color:
	var t := clampi(k, 0, 255) / 255.0
	if invertir:
		t = 1.0 - t
	match mapa:
		TURBO:
			return turbo(t)
		GRIS:
			return Color(t, t, t)
	return arcoiris_rviz(1.0 - t)              # RViz: value = 1 − (v − min)/(max − min)


## Rampa 256×1 RGBA8 (el bucle de 256 se hace una vez por (mapa, invertir) y se cachea).
static func imagen(mapa: int, invertir := false) -> Image:
	var b := PackedByteArray()
	b.resize(1024)
	for k in 256:
		var c := color(mapa, k, invertir)
		b[4 * k] = c.r8
		b[4 * k + 1] = c.g8
		b[4 * k + 2] = c.b8
		b[4 * k + 3] = 255
	return Image.create_from_data(256, 1, false, Image.FORMAT_RGBA8, b)


static func textura(mapa: int, invertir := false) -> ImageTexture:
	var k := Vector2i(mapa, int(invertir))
	if not _cache.has(k):
		_cache[k] = ImageTexture.create_from_image(imagen(mapa, invertir))
	return _cache[k]
