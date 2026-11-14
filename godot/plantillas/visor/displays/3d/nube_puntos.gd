extends "res://comun/visor/display_ros_3d.gd"
## Nube de puntos en GPU (V14, `solo_pc`; doc 36a §4.5.3 sens#3 y el «hueco V14»: textura + *vertex shader* con
## `VERTEX_ID`). `sensor_msgs/PointCloud2` directo; en la Vita no existe (la nube llega como `<p>/nube2d` a
## `2d/nube.gd`, sentencia W13 D5).
##
## Cómo (cero bucles por punto en GDScript en la ruta normal):
##   1. `_procesar`: lee `fields[]` (nombre, offset, datatype) y sube los bytes CRUDOS de `data` a una textura RGBA8
##      de 4 096 texeles de ancho (1 texel = 1 palabra de 4 B). Sin copia por punto: solo el relleno hasta la fila.
##   2. *Vertex shader*: una malla `PRIMITIVE_POINTS` de `max_puntos` vértices (creada una vez); el vértice
##      `VERTEX_ID` lee el punto `VERTEX_ID · paso` (diezmado uniforme), reconstruye x/y/z con `uintBitsToFloat`,
##      descarta NaN/Inf, pasa de ROS a Godot y colorea: plano, por campo (intensity, z, x… con mapa de color 256×1 y
##      rango) o `rgb`/`rgba` empaquetado (PCL: 0x00RRGGBB en un float32 o uint32).
##   3. Filas con relleno (`row_step ≠ width·point_step`, nubes organizadas): el *shader* usa `row_step`.
## Ruta CPU (solo si hace falta): campos x/y/z que no son FLOAT32 alineados a 4 B, color FLOAT64 o desalineado →
## se reempaqueta en GDScript a 16 B por punto (≤ `max_puntos`, ≈ 0,5 µs/punto [I]) y sigue por la misma GPU.
## *Big endian*: `bswap32` nativo si todos los campos son de 4 B (como propone la ficha; RViz no lo trata); si no, se
## rechaza. Rango automático: mínimo y máximo de una muestra de ≤ 1 024 puntos (como «Autocompute intensity bounds»).
## Coste en la capa «mundo»: 1 instancia, 0 triángulos (puntos).

const MapasColor = preload("res://comun/visor/mapas_color.gd")

const ANCHO := 4096                       # texeles (palabras de 4 B) por fila de la textura de datos
const T_INT8 := 1
const T_UINT8 := 2
const T_INT16 := 3
const T_UINT16 := 4
const T_INT32 := 5
const T_UINT32 := 6
const T_FLOAT32 := 7
const T_FLOAT64 := 8
const TAM_TIPO := {1: 1, 2: 1, 3: 2, 4: 2, 5: 4, 6: 4, 7: 4, 8: 8}

@export var campo_color := "intensity"    # "" = plano; "rgb"/"rgba" = empaquetado; otro = campo con mapa de color
@export_enum("arcoiris", "turbo", "gris") var mapa_color := 0
@export var invertir := false             # «Invert Rainbow» de RViz
@export var rango_auto := true
@export var rango_color := Vector2(0.0, 255.0)
@export var color_plano := Color.WHITE
@export var max_puntos := 60000           # vértices de la malla: el diezmado es uniforme hasta este tope
@export var tam_px := 3.0

var puntos := 0                           # puntos de la última nube (antes de diezmar)
var dibujados := 0                        # puntos que dibuja el *shader* (≤ max_puntos)
var paso := 1
var ruta := ""                            # "gpu" | "cpu" (reempaquetado) | ""
var rechazadas := 0
var motivo := ""
var us_ultimo := 0                        # µs de `_procesar` + subida de la última nube
var rango_usado := Vector2.ZERO
var textura: ImageTexture
var material_nube: ShaderMaterial
var _vis: MeshInstance3D
var _malla_n := -1

static var _shader: Shader


static func nombre_display() -> String:
	return "NubePuntos"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["sensor_msgs/msg/PointCloud2"])


func _init() -> void:
	tipo = "sensor_msgs/msg/PointCloud2"
	capa = "mundo"
	solo_pc = true
	hz = 10.0
	caducidad_s = 2.0


func conectar(v) -> void:
	super.conectar(v)
	if estado != "ok" and estado != "sin topic":
		return
	if _vis == null:
		material_nube = ShaderMaterial.new()
		material_nube.shader = shader()
		_vis = MeshInstance3D.new()
		_vis.name = "Puntos"
		_vis.material_override = material_nube
		_vis.visible = false
		add_child(_vis)                   # sin owner (doc 35)
	_malla(max_puntos)


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	return _shader


## Malla de n vértices de puntos (las posiciones las pone el *shader*; AABB grande: no se recorta).
func _malla(n: int) -> void:
	if n == _malla_n:
		return
	_malla_n = n
	var v := PackedVector3Array()
	v.resize(maxi(n, 1))
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, a)
	m.custom_aabb = AABB(Vector3.ONE * -1.0e4, Vector3.ONE * 2.0e4)
	_vis.mesh = m


## Campo por nombre → [offset, datatype] o [] si no está.
static func campo(campos: Array, nombre: String) -> Array:
	for f in campos:
		if String(f.name) == nombre:
			return [int(f.offset), int(f.datatype)]
	return []


func _rechazar(m: String):
	rechazadas += 1
	motivo = m
	return null


## PointCloud2 → dato intermedio para el *shader* (o null). Ver la cabecera.
func _procesar(msg):
	var t0 := Time.get_ticks_usec()
	var campos: Array = msg.fields
	var w := int(msg.width)
	var h := int(msg.height)
	var step := int(msg.point_step)
	var row := int(msg.row_step)
	var data: PackedByteArray = msg.data
	var n := w * h
	if n <= 0 or step <= 0:
		return _rechazar("nube vacía")
	if row < w * step:
		row = w * step
	if data.size() < (h - 1) * row + w * step:
		return _rechazar("data más corto que width·height·point_step")
	var fx := campo(campos, "x")
	var fy := campo(campos, "y")
	var fz := campo(campos, "z")
	if fx.is_empty() or fy.is_empty() or fz.is_empty():
		return _rechazar("sin campos x/y/z")
	var modo := 0
	var fc := []
	if campo_color in ["rgb", "rgba"]:
		fc = campo(campos, campo_color)
		if fc.is_empty():
			fc = campo(campos, "rgba" if campo_color == "rgb" else "rgb")
		modo = 2 if not fc.is_empty() else 0
	elif campo_color != "":
		fc = campo(campos, campo_color)
		modo = 1 if not fc.is_empty() else 0
	if bool(msg.is_bigendian):
		for f in campos:
			if TAM_TIPO.get(int(f.datatype), 0) != 4:
				return _rechazar("big endian con campos que no son de 4 B")
		if step % 4 != 0 or row % 4 != 0:
			return _rechazar("big endian con point_step no múltiplo de 4")
		data = data.duplicate()
		data.bswap32()                    # nativo (Godot ≥ 4.7): todos los campos de 4 B ya alineados
	var d := {"n": n, "ancho_nube": w, "step": step, "row": row, "x": fx[0], "y": fy[0], "z": fz[0],
			"modo": modo, "off_c": fc[0] if modo != 0 else 0, "tipo_c": fc[1] if modo != 0 else T_FLOAT32}
	if _alineada(fx, fy, fz, fc, modo, step, row):
		ruta = "gpu"
		d["bytes"] = data
	else:
		ruta = "cpu"
		d = _reempaquetar(data, d, fx, fy, fz, fc)
	paso = maxi(1, ceili(float(d["n"]) / maxi(max_puntos, 1)))
	d["paso"] = paso
	if modo == 1:
		d["rango"] = _rango_auto(d) if rango_auto else rango_color
	else:
		d["rango"] = rango_color
	puntos = n
	us_ultimo = Time.get_ticks_usec() - t0
	return d


## ¿Puede el *shader* leer los campos tal cual? x/y/z FLOAT32 en palabras enteras, color en su alineación natural.
static func _alineada(fx: Array, fy: Array, fz: Array, fc: Array, modo: int, step: int, row: int) -> bool:
	if step % 4 != 0 or row % 4 != 0:
		return false
	for f in [fx, fy, fz]:
		if f[1] != T_FLOAT32 or f[0] % 4 != 0:
			return false
	if modo == 2:
		return fc[1] in [T_FLOAT32, T_UINT32, T_INT32] and fc[0] % 4 == 0
	if modo == 1:
		var tam: int = TAM_TIPO.get(fc[1], 0)
		return tam in [1, 2, 4] and fc[0] % tam == 0
	return true


## Lectura de un campo en CPU (ruta CPU y rango automático).
static func leer(b: PackedByteArray, o: int, t: int) -> float:
	match t:
		T_INT8: return b.decode_s8(o)
		T_UINT8: return b.decode_u8(o)
		T_INT16: return b.decode_s16(o)
		T_UINT16: return b.decode_u16(o)
		T_INT32: return b.decode_s32(o)
		T_UINT32: return b.decode_u32(o)
		T_FLOAT32: return b.decode_float(o)
		T_FLOAT64: return b.decode_double(o)
	return NAN


## Ruta CPU: ≤ max_puntos puntos (diezmado uniforme) a 16 B: x, y, z float32 + color (float32 o rgb u32).
func _reempaquetar(b: PackedByteArray, d: Dictionary, fx: Array, fy: Array, fz: Array, fc: Array) -> Dictionary:
	var n: int = d["n"]
	var p := maxi(1, ceili(float(n) / maxi(max_puntos, 1)))
	var m := ceili(float(n) / p)
	var out := PackedByteArray()
	out.resize(m * 16)
	var w: int = d["ancho_nube"]
	var k := 0
	for i in range(0, n, p):
		var base: int = (i / w) * int(d["row"]) + (i % w) * int(d["step"])
		out.encode_float(16 * k, leer(b, base + fx[0], fx[1]))
		out.encode_float(16 * k + 4, leer(b, base + fy[0], fy[1]))
		out.encode_float(16 * k + 8, leer(b, base + fz[0], fz[1]))
		if d["modo"] == 2:
			out.encode_u32(16 * k + 12, b.decode_u32(base + fc[0]))
		elif d["modo"] == 1:
			out.encode_float(16 * k + 12, leer(b, base + fc[0], fc[1]))
		k += 1
	return {"n": m, "ancho_nube": m, "step": 16, "row": m * 16, "x": 0, "y": 4, "z": 8, "modo": d["modo"],
			"off_c": 12, "tipo_c": T_FLOAT32, "bytes": out}


## Mínimo y máximo del campo de color en una muestra de ≤ 1 024 puntos (sin NaN).
static func _rango_auto(d: Dictionary) -> Vector2:
	var b: PackedByteArray = d["bytes"]
	var n: int = d["n"]
	var w: int = d["ancho_nube"]
	var s := maxi(1, n / 1024)
	var mn := INF
	var mx := -INF
	for i in range(0, n, s):
		var v := leer(b, (i / w) * int(d["row"]) + (i % w) * int(d["step"]) + int(d["off_c"]), int(d["tipo_c"]))
		if is_finite(v):
			mn = minf(mn, v)
			mx = maxf(mx, v)
	if mn > mx:
		return Vector2(0, 1)
	if mx - mn < 1e-6:
		mx = mn + 1.0
	return Vector2(mn, mx)


func _pintar(d) -> void:
	if _vis == null:
		return
	var t0 := Time.get_ticks_usec()
	var bytes: PackedByteArray = d["bytes"]
	var filas := maxi(1, ceili(bytes.size() / (4.0 * ANCHO)))
	if bytes.size() != filas * ANCHO * 4:
		bytes = bytes.duplicate() if bytes.size() < filas * ANCHO * 4 else bytes.slice(0, filas * ANCHO * 4)
		bytes.resize(filas * ANCHO * 4)   # relleno hasta la fila (los bytes de más no se leen)
	var img := Image.create_from_data(ANCHO, filas, false, Image.FORMAT_RGBA8, bytes)
	if textura != null and textura.get_height() == filas:
		textura.update(img)               # mismo tamaño: sin realojar (T26)
	else:
		textura = ImageTexture.create_from_image(img)
	_malla(max_puntos)
	dibujados = mini(max_puntos, ceili(float(d["n"]) / d["paso"]))
	rango_usado = d["rango"]
	var m := material_nube
	m.set_shader_parameter("datos", textura)
	m.set_shader_parameter("mapa", MapasColor.textura(mapa_color, invertir))
	m.set_shader_parameter("n_puntos", int(d["n"]))
	m.set_shader_parameter("paso", int(d["paso"]))
	m.set_shader_parameter("ancho_nube", int(d["ancho_nube"]))
	m.set_shader_parameter("point_step", int(d["step"]))
	m.set_shader_parameter("row_step", int(d["row"]))
	m.set_shader_parameter("off_xyz", Vector3i(d["x"], d["y"], d["z"]))
	m.set_shader_parameter("off_c", int(d["off_c"]))
	m.set_shader_parameter("tipo_c", int(d["tipo_c"]))
	m.set_shader_parameter("modo", int(d["modo"]))
	m.set_shader_parameter("rango", d["rango"])
	m.set_shader_parameter("color_plano", color_plano)
	m.set_shader_parameter("tam_px", tam_px)
	_vis.visible = true
	us_ultimo += Time.get_ticks_usec() - t0


func _coste() -> Dictionary:
	return {"instancias": 1, "triangulos": 0, "quads": 0}


## Los bytes de la nube como palabras de 32 bit (little endian) en una textura RGBA8 de ANCHO de ancho.
## Funciona igual en Compatibility (rclgd/GL) y en Forward+ (Vulkan).
const SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D datos : filter_nearest;
uniform sampler2D mapa : source_color, filter_nearest;
uniform int n_puntos = 0;
uniform int paso = 1;
uniform int ancho_nube = 1;
uniform int point_step = 16;
uniform int row_step = 16;
uniform ivec3 off_xyz = ivec3(0, 4, 8);
uniform int off_c = 12;
uniform int tipo_c = 7;
uniform int modo = 0;
uniform vec2 rango = vec2(0.0, 1.0);
uniform vec4 color_plano : source_color = vec4(1.0);
uniform float tam_px = 3.0;
varying vec3 v_color;

uint palabra(int b) {
	int w = b >> 2;
	uvec4 c = uvec4(texelFetch(datos, ivec2(w & 4095, w >> 12), 0) * 255.0 + 0.5);
	return c.r | (c.g << 8u) | (c.b << 16u) | (c.a << 24u);
}

float leer(int b, int t) {
	uint w = palabra(b);
	uint sh = uint((b & 3) * 8);
	if (t == 7) return uintBitsToFloat(w);
	if (t == 2) return float((w >> sh) & 255u);
	if (t == 1) { int v = int((w >> sh) & 255u); return float(v > 127 ? v - 256 : v); }
	if (t == 4) return float((w >> sh) & 65535u);
	if (t == 3) { int v = int((w >> sh) & 65535u); return float(v > 32767 ? v - 65536 : v); }
	if (t == 6) return float(w);
	if (t == 5) return float(int(w));
	return 0.0;
}

vec3 lineal(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	int k = VERTEX_ID * paso;
	POINT_SIZE = tam_px;
	v_color = vec3(0.0);
	if (k >= n_puntos) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	} else {
		int b = (k / ancho_nube) * row_step + (k % ancho_nube) * point_step;
		vec3 p = vec3(uintBitsToFloat(palabra(b + off_xyz.x)), uintBitsToFloat(palabra(b + off_xyz.y)),
				uintBitsToFloat(palabra(b + off_xyz.z)));
		if (any(isnan(p)) || any(isinf(p))) {
			POSITION = vec4(2.0, 2.0, 2.0, 1.0);
		} else {
			POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(-p.y, p.z, -p.x, 1.0);
		}
		if (modo == 2) {
			uint w = palabra(b + off_c);
			v_color = lineal(vec3(float((w >> 16u) & 255u), float((w >> 8u) & 255u), float(w & 255u)) / 255.0);
		} else if (modo == 1) {
			float t = clamp((leer(b + off_c, tipo_c) - rango.x) / max(rango.y - rango.x, 1e-6), 0.0, 1.0);
			v_color = texelFetch(mapa, ivec2(int(t * 255.0 + 0.5), 0), 0).rgb;
		} else {
			v_color = color_plano.rgb;
		}
	}
}

void fragment() {
	ALBEDO = v_color;
}
"""
