extends SceneTree
## Banco de V13b (2026-11-14; docs/ia/workshops/posts/V13b-juez-fable.md): tiempo en el HOST de los bucles
## GDScript de decodificación densa del visor, para decidir si hace falta `modules/viz-decode/` (ADR 0011 §5).
## Los bucles son COPIAS de los reales (se citan); solo cambian los datos, que son sintéticos. No usa ROS.
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script (pwd)/docs/ia/medidas/v13b-banco-decodificacion.gd
## Salida: «nombre mediana_us max_us» (2 000 repeticiones, tras una pasada de calentamiento).

var lut2 := []                        # byte → 16 B (4 celdas RGBA8): vita_relay.gd `lut_tesela`
var lut4 := []                        # byte → 8 B (2 celdas RGBA8): costmap_textura.gd `_lut_costmap`
var tb := PackedByteArray()
var timg: Image
var big: Image
var b260 := PackedByteArray()         # tesela de mapa: 4 + 256 B
var b516 := PackedByteArray()         # tesela de costmap: 4 + 512 B
var nube := PackedInt32Array()        # trozo nube2d: 4 + 3 × 76
var scan := PackedInt32Array()        # scan_compacto: 4 + 180
var dirs := PackedVector2Array()
var lutc := PackedColorArray()
var r360 := PackedFloat32Array()
var pc := PackedByteArray()           # PointCloud2 de 468 puntos × 16 B (lo que cabe en ≈ 7,5 KiB fiables)
var lut32 := PackedInt32Array()
var celdas := PackedByteArray()
var _v := PackedVector2Array()
var _c := PackedColorArray()


func medir(nombre: String, f: Callable, n := 2000) -> void:
	f.call()
	var ts := PackedInt64Array()
	for i in n:
		var t := Time.get_ticks_usec()
		f.call()
		ts.append(Time.get_ticks_usec() - t)
	ts.sort()
	print("%-44s %5d %5d" % [nombre, ts[n / 2], ts[n - 1]])


func _tri(v: PackedVector2Array, c: PackedColorArray, k: int, p: Vector2, col: Color) -> void:
	v[3 * k] = p + Vector2(0, -2.0)
	v[3 * k + 1] = p + Vector2(2.0, 2.0)
	v[3 * k + 2] = p + Vector2(-2.0, 2.0)
	c[3 * k] = col
	c[3 * k + 1] = col
	c[3 * k + 2] = col


func _color_z(z: float) -> Color:
	var esc := 15.0 / 2.2
	return lutc[clampi(int((z + 0.2) * esc), 0, 15)]


## vita_relay.gd `on_mapa_tesela` (bucle GDScript).
func tesela_mapa() -> void:
	tb.resize(0)
	for j in range(31, -1, -1):
		var base := 4 + j * 8
		for k in 8:
			tb.append_array(lut2[b260[base + k]])


## vita_relay.gd `on_mapa_tesela` (parte del motor: set_data + blit_rect).
func tesela_motor() -> void:
	timg.set_data(32, 32, false, Image.FORMAT_RGBA8, tb)
	big.blit_rect(timg, Rect2i(0, 0, 32, 32), Vector2i(64, 64))


## costmap_textura.gd `de_tesela` (bucle GDScript).
func tesela_costmap() -> void:
	tb.resize(0)
	for j in range(31, -1, -1):
		var base := 4 + j * 16
		for k in 16:
			tb.append_array(lut4[b516[base + k]])


## displays/2d/nube.gd `_procesar_compacto` (76 puntos).
func nube_trozo() -> void:
	var d := nube
	var n := 76
	var v := PackedVector2Array()
	var c := PackedColorArray()
	v.resize(3 * n)
	c.resize(3 * n)
	var k := 0.4
	for i in n:
		var b := 4 + 3 * i
		_tri(v, c, i, Vector2(d[b], -d[b + 1]) * k, _color_z(d[b + 2] / 100.0))


## vita_relay.gd `scan_puntos` + displays/2d/scan.gd `_pintar` (180 rayos).
func scan_compacto() -> void:
	var n := 180
	var r := PackedVector2Array()
	r.resize(n)
	var k := 0
	for i in n:
		var cm: int = scan[4 + i]
		if cm > 0:
			r[k] = dirs[i] * (cm / 100.0)
			k += 1
	r.resize(k)
	_pintar(r)


func _pintar(puntos: PackedVector2Array) -> void:
	var n := puntos.size()
	_v.resize(n * 3)
	_c.resize(n * 3)
	_c.fill(Color.RED)
	for i in n:
		var p := Vector2(puntos[i].x, -puntos[i].y) * 40.0
		_v[3 * i] = p + Vector2(0, -3.0)
		_v[3 * i + 1] = p + Vector2(3.0, 3.0)
		_v[3 * i + 2] = p + Vector2(-3.0, 3.0)


## displays/2d/scan.gd `_procesar` + `_pintar` (LaserScan directo de 360 rayos).
func scan_directo() -> void:
	var n := 360
	var out := PackedVector2Array()
	out.resize(n)
	var k := 0
	for i in n:
		var d: float = r360[i]
		if not (d >= 0.1 and d <= 30.0):
			continue
		out[k] = dirs[i] * d
		k += 1
	out.resize(k)
	_pintar(out)


## displays/2d/nube.gd `_procesar` (PointCloud2 directo alineado, 468 puntos).
func nube_directa() -> void:
	var total := 468
	var v := PackedVector2Array()
	var c := PackedColorArray()
	v.resize(3 * total)
	c.resize(3 * total)
	var f32 := pc.to_float32_array()
	var n := 0
	for i in total:
		var x := f32[i * 4]
		var y := f32[i * 4 + 1]
		var z := f32[i * 4 + 2]
		if is_finite(x) and is_finite(y) and is_finite(z):
			_tri(v, c, n, Vector2(x, -y) * 40.0, _color_z(z))
			n += 1


## mapa_textura.gd `de_grid` (OccupancyGrid directo de 86 × 86 celdas: lo que cabe en ≈ 7,5 KiB).
func grid_directo() -> void:
	var w := 86
	var h := 86
	tb.resize(w * h * 4)
	for y in h:
		var o := (h - 1 - y) * w * 4
		var cc := y * w
		for x in w:
			tb.encode_u32(o + 4 * x, lut32[celdas[cc + x]])


func _init() -> void:
	for v in 256:
		var p := PackedByteArray()
		p.resize(16)
		lut2.append(p)
		var q := PackedByteArray()
		q.resize(8)
		lut4.append(q)
	b260.resize(260)
	b516.resize(516)
	for i in 260:
		b260[i] = (i * 37) & 255
	for i in 516:
		b516[i] = (i * 37) & 255
	nube.resize(4 + 228)
	for i in 232:
		nube[i] = (i * 13) % 300
	scan.resize(184)
	for i in 184:
		scan[i] = 100 + i
	dirs.resize(360)
	r360.resize(360)
	for i in 360:
		dirs[i] = Vector2.from_angle(i * 0.0175)
		r360[i] = 1.0 + i * 0.01
	for k in 16:
		lutc.append(Color.from_hsv(0.66 * (1.0 - k / 15.0), 1.0, 1.0))
	var f := PackedFloat32Array()
	f.resize(468 * 4)
	for i in 468 * 4:
		f[i] = i * 0.001
	pc = f.to_byte_array()
	lut32.resize(256)
	celdas.resize(86 * 86)
	tesela_mapa()
	timg = Image.create_from_data(32, 32, false, Image.FORMAT_RGBA8, tb)
	big = Image.create(384, 384, false, Image.FORMAT_RGBA8)
	print("%-44s %5s %5s" % ["ruta", "med", "max"])
	medir("tesela mapa, bucle (256 append_array)", tesela_mapa)
	medir("tesela mapa, motor (set_data + blit_rect)", tesela_motor)
	medir("tesela costmap, bucle (512 append_array)", tesela_costmap)
	medir("nube2d, trozo de 76 puntos", nube_trozo)
	medir("scan_compacto 180 rayos (+ pintar)", scan_compacto)
	medir("LaserScan directo 360 rayos (+ pintar)", scan_directo)
	medir("PointCloud2 directo 468 puntos", nube_directa)
	medir("OccupancyGrid directo 86x86", grid_directo)
	quit()
