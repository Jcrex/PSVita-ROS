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
func on_mapa_tesela(m) -> void:
	var b: PackedByteArray = m.data
	if mapa_img == null or b.size() < 4 + TESELA * TESELA / 4:
		return
	var tx := b[2]
	var ty := b[3]
	for j in TESELA:
		var y := ty * TESELA + j
		if y >= alto:
			break
		var fila := alto - 1 - y          # OccupancyGrid: fila 0 abajo; imagen: fila 0 arriba (norte arriba)
		for i in TESELA:
			var x := tx * TESELA + i
			if x >= ancho:
				break
			var k := j * TESELA + i
			var c := (b[4 + (k >> 2)] >> ((k & 3) * 2)) & 3
			mapa_img.set_pixel(x, fila, COLORES[mini(c, 2)])
	teselas_recibidas += 1
	_sucio = true


## Sube la imagen a la textura si hubo teselas nuevas (limitado a HZ_TEXTURA). Llamar en _process.
func actualizar_textura() -> void:
	var ahora := Time.get_ticks_msec() / 1000.0
	if _sucio and mapa_tex != null and ahora - _t_ultima >= 1.0 / HZ_TEXTURA:
		mapa_tex.update(mapa_img)
		_sucio = false
		_t_ultima = ahora


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
static func scan_puntos(m) -> PackedVector2Array:
	var d = m.data
	var r := PackedVector2Array()
	if d.size() < 4:
		return r
	var a0 := deg_to_rad(d[1] / 100.0)
	var inc := deg_to_rad(d[2] / 100.0)
	var n: int = mini(d[3], d.size() - 4)
	for i in n:
		var dist: float = d[4 + i] / 100.0
		if dist > 0.0:
			var a := a0 + i * inc
			r.append(Vector2(cos(a), sin(a)) * dist)
	return r


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
