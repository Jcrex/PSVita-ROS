extends RefCounted
## (Antes en godot/comun/, fusionado en godot/plantillas/ el 2026-11-12, revisión R4.)
## Cliente Godot de los formatos compactos de `docker/scripts/vita_relay.py` (doc 27). Sirve igual en el PC
## (rclgd o ros2_vita) y en la Vita: solo usa arrays de RosMsg, Image/ImageTexture y matemáticas.
##
## Uso (ver godot/g1-unitree/minimapa.gd):
##   var relay := preload("res://comun/vita_relay.gd").new()
##   node.create_subscription("/vita/mapa_meta", "std_msgs/msg/Float32MultiArray", relay.on_mapa_meta, qos_latched)
##   node.create_subscription("/vita/mapa_tesela", "std_msgs/msg/UInt8MultiArray", relay.on_mapa_tesela, qos_be)
##   cada fotograma: relay.actualizar_textura()  → relay.mapa_tex (ImageTexture, norte arriba)
##
## Arreglos de docs/31 §4.4 (tarea V3 del visor, doc 36 §10; 2026-11-13). Los formatos VC/1 no cambian ni un byte:
##   - tesela: LUT byte → 4 celdas RGBA8 (16 B) + `Image.set_data` + `blit_rect`, en vez de 1 024 `set_pixel`
##     (misma imagen al byte: la LUT trunca a 8 bit igual que `set_pixel`; lo comprueba pruebas/visor_displays.gd);
##   - scan: tabla de direcciones cos/sin cacheada por (ang_min, inc, n), en vez de cos/sin por rayo;
##   - `actualizar_textura()` devuelve true si subió la textura (para redibujar solo cuando cambia).
## Pendiente de docs/31 §4.4 (no entra en V3): sub-texturas de 128² subiendo solo la sucia (H19) — hoy se sube la
## textura entera, como mucho HZ_TEXTURA veces por segundo.

signal mapa_cambiado

const TESELA := 32
const COLORES := [Color(0.16, 0.17, 0.2), Color(0.86, 0.86, 0.84), Color(0.05, 0.05, 0.08)]  # desconocido, libre, ocupado
const HZ_TEXTURA := 4.0       # subir la textura completa como mucho 4 veces por segundo (CPU de la Vita)

var resolucion := 0.05
var ancho := 0
var alto := 0
var origen := Vector2.ZERO    # esquina inferior izquierda del mapa en el marco de ROS (m)
var version := -1
var mapa_img: Image
var mapa_tex: ImageTexture
var teselas_recibidas := 0
var _sucio := false
var _t_ultima := 0.0
var _tesela_img: Image                 # imagen 32×32 reutilizada para cada tesela (set_data + blit_rect)
var _tesela_bytes := PackedByteArray()

# LUT de teselas: byte (4 celdas a 2 bit, LSB primero) → 16 B RGBA8. Se calcula una vez (256 entradas).
static var _lut_tesela: Array = []
# Tablas de direcciones del scan: Vector3i(ang_min_cdeg, inc_cdeg, n) → PackedVector2Array de cos/sin.
static var _dirs_scan := {}
const MAX_TABLAS_SCAN := 8


## /vita/mapa_meta = [res, ancho, alto, ox, oy, teselas_x, teselas_y, version] (fiable + TRANSIENT_LOCAL).
func on_mapa_meta(m) -> void:
	var d: PackedFloat32Array = m.data
	if d.size() < 8:
		return
	var nuevo := int(d[1]) != ancho or int(d[2]) != alto
	resolucion = d[0]
	ancho = int(d[1])
	alto = int(d[2])
	origen = Vector2(d[3], d[4])
	version = int(d[7])
	if nuevo or mapa_img == null:
		mapa_img = Image.create(ancho, alto, false, Image.FORMAT_RGBA8)
		mapa_img.fill(COLORES[0])
		mapa_tex = ImageTexture.create_from_image(mapa_img)
		teselas_recibidas = 0
	mapa_cambiado.emit()


## /vita/mapa_tesela = [ver_lo, ver_hi, tx, ty, 256 B: 32×32 celdas a 2 bit] (best effort).
## LUT + `blit_rect` (docs/31 §4.4): 256 `append_array` de 16 B en vez de 1 024 `set_pixel` con desempaquetado.
func on_mapa_tesela(m) -> void:
	var b: PackedByteArray = m.data
	if mapa_img == null or b.size() < 4 + TESELA * TESELA / 4:
		return
	var tx: int = b[2]
	var ty: int = b[3]
	var x0 := tx * TESELA
	var y0 := ty * TESELA
	if x0 >= ancho or y0 >= alto:
		return
	var w := mini(TESELA, ancho - x0)           # teselas del borde: solo la parte dentro del mapa
	var h := mini(TESELA, alto - y0)
	var lut := lut_tesela()
	# Filas al revés: OccupancyGrid tiene la fila 0 abajo y la imagen arriba (norte arriba). La fila j de la
	# tesela (8 B) queda en la fila 31 − j de la imagen 32×32.
	_tesela_bytes.resize(0)
	for j in range(TESELA - 1, -1, -1):
		var base := 4 + j * (TESELA / 4)
		for k in TESELA / 4:
			_tesela_bytes.append_array(lut[b[base + k]])
	if _tesela_img == null:
		_tesela_img = Image.create_from_data(TESELA, TESELA, false, Image.FORMAT_RGBA8, _tesela_bytes)
	else:
		_tesela_img.set_data(TESELA, TESELA, false, Image.FORMAT_RGBA8, _tesela_bytes)
	# Fila j (0 ≤ j < h) → fila de imagen alto − 1 − (y0 + j); en la tesela invertida, filas 32 − h … 31.
	mapa_img.blit_rect(_tesela_img, Rect2i(0, TESELA - h, w, h), Vector2i(x0, alto - y0 - h))
	teselas_recibidas += 1
	_sucio = true


## LUT de teselas (estática, se calcula una vez): índice = byte → 16 B RGBA8 de sus 4 celdas. Cada celda se
## convierte a 8 bit TRUNCANDO, igual que `Image.set_pixel` (core/io/image.cpp `_set_color_at_ofs`), para que la
## imagen sea idéntica a la del código anterior.
static func lut_tesela() -> Array:
	if _lut_tesela.is_empty():
		var col := []
		for c: Color in COLORES:
			col.append(PackedByteArray([int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0), int(c.a * 255.0)]))
		for v in 256:
			var p := PackedByteArray()
			for k in 4:
				p.append_array(col[mini((v >> (2 * k)) & 3, 2)])
			_lut_tesela.append(p)
	return _lut_tesela


## Sube la imagen a la textura si hubo teselas nuevas (limitado a HZ_TEXTURA). Llamar en _process.
## Devuelve true si la subió (quien dibuja puede redibujar solo entonces; docs/31 §4.4).
func actualizar_textura() -> bool:
	var ahora := Time.get_ticks_msec() / 1000.0
	if _sucio and mapa_tex != null and ahora - _t_ultima >= 1.0 / HZ_TEXTURA:
		mapa_tex.update(mapa_img)
		_sucio = false
		_t_ultima = ahora
		return true
	return false


## Punto del mundo (ROS, m) → píxel de la imagen del mapa (norte arriba).
func mundo_a_pixel(p: Vector2) -> Vector2:
	return Vector2((p.x - origen.x) / resolucion, alto - (p.y - origen.y) / resolucion)


## /vita/pose2d = [x, y, yaw, vx, vy, wz] → {pos: Vector2, yaw: float, vel: Vector3}
static func pose2d(m) -> Dictionary:
	var d: PackedFloat32Array = m.data
	if d.size() < 6:
		return {}
	return {"pos": Vector2(d[0], d[1]), "yaw": d[2], "vel": Vector3(d[3], d[4], d[5])}


## /vita/scan_compacto = [seq, ang_min_cdeg, inc_cdeg, n, r0..] (cm, 0 = sin dato) → puntos en el marco del sensor (m).
## Tabla de direcciones (docs/31 §4.4): cos/sin solo cuando cambian ang_min, inc o n; por rayo, una multiplicación.
static func scan_puntos(m) -> PackedVector2Array:
	var d = m.data                     # Int16MultiArray → PackedInt32Array (trampa T6): sin anotar
	var r := PackedVector2Array()
	if d.size() < 4:
		return r
	var n: int = mini(d[3], d.size() - 4)
	if n <= 0:
		return r
	var dirs := direcciones_scan(int(d[1]), int(d[2]), n)
	r.resize(n)
	var k := 0
	for i in n:
		var cm: int = d[4 + i]
		if cm > 0:
			r[k] = dirs[i] * (cm / 100.0)
			k += 1
	r.resize(k)
	return r


## Direcciones unitarias de los n rayos (ángulos en centésimas de grado, como el formato). Cacheadas.
static func direcciones_scan(ang_min_cdeg: int, inc_cdeg: int, n: int) -> PackedVector2Array:
	var clave := Vector3i(ang_min_cdeg, inc_cdeg, n)
	if _dirs_scan.has(clave):
		return _dirs_scan[clave]
	if _dirs_scan.size() >= MAX_TABLAS_SCAN:
		_dirs_scan.clear()
	var a0 := deg_to_rad(ang_min_cdeg / 100.0)
	var inc := deg_to_rad(inc_cdeg / 100.0)
	var dirs := PackedVector2Array()
	dirs.resize(n)
	for i in n:
		var a := a0 + i * inc
		dirs[i] = Vector2(cos(a), sin(a))
	_dirs_scan[clave] = dirs
	return dirs


## /vita/path_compacto = [n, x0, y0, ...] → puntos del mundo (m).
static func path_puntos(m) -> PackedVector2Array:
	var d: PackedFloat32Array = m.data
	var r := PackedVector2Array()
	if d.size() < 1:
		return r
	var n := mini(int(d[0]), (d.size() - 1) / 2)
	for i in n:
		r.append(Vector2(d[1 + 2 * i], d[2 + 2 * i]))
	return r
