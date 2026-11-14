extends RefCounted
## CostmapTextura (V11; doc 36a §4.6.2, doc 36 §5.3): costmap del relay (`<p>/costmap_meta` + `<p>/costmap_tesela`,
## teselas de 32×16 celdas a 4 bit) y su COMPOSICIÓN EN CPU sobre la imagen del mapa (una sola textura: sin
## *shaders* ni orden de transparencias en la Vita, docs/31 §2.4). No es un display: lo usan `displays/2d/costmap.gd`
## (decodifica) y `displays/2d/mapa.gd` (dibuja la textura compuesta cuando hay mapa y costmap).
##
##   imagen propia : `img` RGBA8 de ancho × alto celdas del costmap, norte arriba; cada tesela se decodifica con una
##                   LUT de 256 entradas (byte = 2 celdas → 8 B RGBA8, nibble bajo primero) + `blit_rect`, como el
##                   mapa de V3. Colores = `PaletaViz.lut16_costmap()` (paleta costmap de RViz) con `alfa`.
##   compuesta     : `compuesta` RGBA8 con la geometría del MAPA: región sucia = píxeles del mapa (`blit_rect`) +
##                   celdas del costmap escaladas al píxel del mapa (`resize` NEAREST) y mezcladas (`blend_rect`).
##                   Solo se recomponen las regiones sucias (teselas del mapa o del costmap que llegaron); todo si
##                   cambia la geometría de alguno. Subida a la textura ≤ HZ_TEXTURA.
##   época         : la de `costmap_meta`; una tesela de otra época se descarta (`descartadas`). Época o geometría
##                   nuevas = imagen nueva vacía (transparente) y recomposición completa.

const Paleta = preload("res://comun/visor/paleta_viz.gd")

const TX := 32                       # celdas por tesela (ancho)
const TY := 16                       # celdas por tesela (alto)
const HZ_TEXTURA := 4.0              # como `vita_relay.gd`: subir como mucho 4 veces por segundo
const MAX_REGIONES := 24             # más regiones sucias que esto → una recomposición completa

var alfa := 0.7                      # opacidad del costmap (RViz: 0,7 por defecto en el display de costmap)
var res := 0.1
var ancho := 0
var alto := 0
var origen := Vector2.ZERO           # esquina de la celda (0,0) en el marco del mapa (m)
var epoca := -1
var img: Image                       # costmap a su resolución (norte arriba)
var textura: ImageTexture            # la del costmap solo (sin mapa debajo)
var compuesta: Image                 # mapa + costmap (geometría del mapa)
var textura_compuesta: ImageTexture
var version := 0                     # sube cuando cambia `textura` o `textura_compuesta` (para redibujar)
var teselas := 0
var descartadas := 0                 # teselas de otra época, fuera de límites o cortas
var us_ultima := 0                   # µs de la última tesela decodificada
var us_max := 0
var us_composicion := 0              # µs de la última recomposición (gate G-W13-M5)

var _sub_meta
var _lut: Array = []                 # byte → PackedByteArray de 8 B (2 celdas RGBA8)
var _tesela_bytes := PackedByteArray()
var _tesela_img: Image
var _sucio_propia := false
var _t_propia := -1000.0
var _t_compuesta := -1000.0
var _regiones: Array[Rect2i] = []    # en celdas del costmap (x, fila de imagen) pendientes de componer
var _regiones_base: Array[Rect2i] = []   # en píxeles del mapa
var _todo := true                    # recomponer entera la próxima vez
var _clave_base := []                # geometría del mapa con la que se compuso


## Suscribe la meta *latched* (F+TL). `topic_meta` es el sufijo bajo el prefijo compacto.
func conectar(v, topic_meta: String = "costmap_meta") -> void:
	_sub_meta = v.contexto.nodo.create_subscription(v.prefijo_compacto.trim_suffix("/") + "/" + topic_meta,
			"std_msgs/msg/Float32MultiArray", al_meta, v.contexto.qos(false, 1, true))


func cerrar() -> void:
	_sub_meta = null


func tiene_datos() -> bool:
	return img != null


## `<p>/costmap_meta` = [res, ancho, alto, ox, oy, teselas_x, teselas_y, época].
func al_meta(m) -> void:
	var d: PackedFloat32Array = m.data
	if d.size() < 8 or int(d[1]) <= 0 or int(d[2]) <= 0:
		return
	var e := int(d[7])
	var geo_nueva := int(d[1]) != ancho or int(d[2]) != alto or not is_equal_approx(d[0], res) \
			or Vector2(d[3], d[4]) != origen
	res = d[0]
	ancho = int(d[1])
	alto = int(d[2])
	origen = Vector2(d[3], d[4])
	if geo_nueva or e != epoca or img == null:
		# Época nueva: lo recibido con la anterior ya no vale (el relay manda todas las teselas otra vez).
		img = Image.create(ancho, alto, false, Image.FORMAT_RGBA8)          # transparente: aún sin datos
		textura = ImageTexture.create_from_image(img)
		_regiones.clear()
		_todo = true
		version += 1
	epoca = e


## `<p>/costmap_tesela` = [ver_lo, ver_hi, tx, ty, 256 B]. Devuelve true si la pintó en la imagen.
func de_tesela(m) -> bool:
	var t0 := Time.get_ticks_usec()
	var b: PackedByteArray = m.data
	if img == null or b.size() < 4 + TX * TY / 2 or (b[0] | (b[1] << 8)) != epoca:
		descartadas += 1
		return false
	var x0: int = b[2] * TX
	var y0: int = b[3] * TY
	if x0 >= ancho or y0 >= alto:
		descartadas += 1
		return false
	var w := mini(TX, ancho - x0)
	var h := mini(TY, alto - y0)
	var lut := _lut_costmap()
	# Fila 0 del costmap abajo; imagen norte arriba: la fila j de la tesela (16 B) va a la fila TY − 1 − j.
	_tesela_bytes.resize(0)
	for j in range(TY - 1, -1, -1):
		var base := 4 + j * (TX / 2)
		for k in TX / 2:
			_tesela_bytes.append_array(lut[b[base + k]])
	if _tesela_img == null:
		_tesela_img = Image.create_from_data(TX, TY, false, Image.FORMAT_RGBA8, _tesela_bytes)
	else:
		_tesela_img.set_data(TX, TY, false, Image.FORMAT_RGBA8, _tesela_bytes)
	var dst := Vector2i(x0, alto - y0 - h)
	img.blit_rect(_tesela_img, Rect2i(0, TY - h, w, h), dst)
	_marcar(Rect2i(dst, Vector2i(w, h)))
	_sucio_propia = true
	teselas += 1
	us_ultima = Time.get_ticks_usec() - t0
	us_max = maxi(us_max, us_ultima)
	return true


## El mapa de debajo cambió en el rectángulo `r` (píxeles de la imagen del mapa).
func marcar_base(r: Rect2i) -> void:
	if _regiones_base.size() >= MAX_REGIONES:
		_todo = true
		_regiones_base.clear()
	elif not _todo:
		_regiones_base.append(r)


## Tesela (tx, ty) de 32×32 del mapa VC/1 → su rectángulo en la imagen del mapa (norte arriba).
static func rect_tesela_mapa(tx: int, ty: int, ancho_m: int, alto_m: int) -> Rect2i:
	var x0 := tx * 32
	var y0 := ty * 32
	if x0 >= ancho_m or y0 >= alto_m:
		return Rect2i()
	var w := mini(32, ancho_m - x0)
	var h := mini(32, alto_m - y0)
	return Rect2i(x0, alto_m - y0 - h, w, h)


func _marcar(r: Rect2i) -> void:
	if _regiones.size() >= MAX_REGIONES:
		_todo = true
		_regiones.clear()
	elif not _todo:
		_regiones.append(r)


## Sin mapa debajo: sube la imagen propia (≤ HZ_TEXTURA). true si cambió la textura.
func tic_propia() -> bool:
	var ahora := Time.get_ticks_msec() / 1000.0
	if not _sucio_propia or textura == null or ahora - _t_propia < 1.0 / HZ_TEXTURA:
		return false
	textura.update(img)
	_sucio_propia = false
	_t_propia = ahora
	version += 1
	return true


## Con mapa debajo (`base` = Image del mapa, geometría res_m/origen_m/alto_m): recompone lo sucio y sube la textura
## compuesta (≤ HZ_TEXTURA). `forzar` ignora el límite de Hz (pruebas). true si cambió la textura compuesta.
func tic_compuesta(base: Image, res_m: float, origen_m: Vector2, forzar := false) -> bool:
	if img == null or base == null:
		return false
	var ahora := Time.get_ticks_msec() / 1000.0
	if not forzar and ahora - _t_compuesta < 1.0 / HZ_TEXTURA:
		return false
	var clave := [base.get_width(), base.get_height(), res_m, origen_m, ancho, alto, res, origen, epoca]
	if clave != _clave_base or compuesta == null:
		_clave_base = clave
		_todo = true
	if not _todo and _regiones.is_empty() and _regiones_base.is_empty():
		return false
	var t0 := Time.get_ticks_usec()
	var tam := base.get_size()
	if compuesta == null or compuesta.get_size() != tam:
		compuesta = Image.create(tam.x, tam.y, false, Image.FORMAT_RGBA8)
		textura_compuesta = null
	var marco := Rect2i(Vector2i.ZERO, tam)
	if _todo:
		_componer(base, marco, res_m, origen_m)
	else:
		for r in _regiones_base:
			_componer(base, r.intersection(marco), res_m, origen_m)
		for r in _regiones:
			_componer(base, _pixeles_de_celdas(r, res_m, origen_m, tam.y).intersection(marco), res_m, origen_m)
	_todo = false
	_regiones.clear()
	_regiones_base.clear()
	if textura_compuesta == null:
		textura_compuesta = ImageTexture.create_from_image(compuesta)
	else:
		textura_compuesta.update(compuesta)
	_t_compuesta = ahora
	us_composicion = Time.get_ticks_usec() - t0
	version += 1
	return true


## Región R (píxeles del mapa): píxeles del mapa y, encima, las celdas del costmap que la cubren (NEAREST + mezcla).
func _componer(base: Image, r: Rect2i, res_m: float, origen_m: Vector2) -> void:
	if not r.has_area():
		return
	compuesta.blit_rect(base, r, r.position)
	var alto_m := base.get_height()
	# Celdas del costmap que cubren R (x: columnas; y: filas del costmap con la 0 abajo).
	var cx0 := clampi(floori((origen_m.x + r.position.x * res_m - origen.x) / res), 0, ancho)
	var cx1 := clampi(ceili((origen_m.x + r.end.x * res_m - origen.x) / res), 0, ancho)
	var cy0 := clampi(floori((origen_m.y + (alto_m - r.end.y) * res_m - origen.y) / res), 0, alto)
	var cy1 := clampi(ceili((origen_m.y + (alto_m - r.position.y) * res_m - origen.y) / res), 0, alto)
	if cx1 <= cx0 or cy1 <= cy0:
		return
	var celdas := Rect2i(cx0, alto - cy1, cx1 - cx0, cy1 - cy0)        # en filas de la imagen del costmap
	var dst := _pixeles_de_celdas(celdas, res_m, origen_m, alto_m)
	if not dst.has_area():
		return
	var sub := img.get_region(celdas)
	if sub.get_size() != dst.size:
		sub.resize(dst.size.x, dst.size.y, Image.INTERPOLATE_NEAREST)
	var i := dst.intersection(r)
	if i.has_area():
		compuesta.blend_rect(sub, Rect2i(i.position - dst.position, i.size), i.position)


## Rectángulo de celdas del costmap (x, fila de su imagen) → píxeles de la imagen del mapa (norte arriba).
func _pixeles_de_celdas(c: Rect2i, res_m: float, origen_m: Vector2, alto_m: int) -> Rect2i:
	var cy0 := alto - c.end.y                   # filas del costmap con la 0 abajo
	var cy1 := alto - c.position.y
	var x0 := roundi((origen.x + c.position.x * res - origen_m.x) / res_m)
	var x1 := roundi((origen.x + c.end.x * res - origen_m.x) / res_m)
	var f0 := roundi(alto_m - (origen.y + cy1 * res - origen_m.y) / res_m)
	var f1 := roundi(alto_m - (origen.y + cy0 * res - origen_m.y) / res_m)
	return Rect2i(x0, f0, x1 - x0, f1 - f0)


## LUT byte → 2 celdas RGBA8 (nibble bajo = celda par = la de la izquierda), con la opacidad `alfa`.
func _lut_costmap() -> Array:
	if _lut.is_empty():
		var col := []
		for c: Color in Paleta.lut16_costmap():
			col.append(PackedByteArray([c.r8, c.g8, c.b8, roundi(c.a8 * alfa)]))
		for v in 256:
			var p := PackedByteArray()
			p.append_array(col[v & 15])
			p.append_array(col[v >> 4])
			_lut.append(p)
	return _lut


## Color RGBA8 del nivel n (0–15) tal como lo pinta la LUT (para las pruebas).
func color_nivel(n: int) -> Color:
	var p: PackedByteArray = _lut_costmap()[n]
	return Color8(p[0], p[1], p[2], p[3])
