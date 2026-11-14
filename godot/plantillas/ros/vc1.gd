extends RefCounted
## Contrato VC/1 de formatos compactos para la Vita (docs/ia/revision-kimi/R4-integracion.md §1.6).
## Referencia de formato: las funciones puras de `docker/scripts/vita_relay.py`; estas son su copia en GDScript
## y `pruebas/runner.gd` comprueba que dan los MISMOS bytes con vectores generados por el script de Python.
##
##   scan_compacto  Int16MultiArray  [seq & 0x7FFF, ang_min_cdeg, inc_cdeg, n, r0..] en cm; 0 = sin dato
##                  (sin impacto, NaN/Inf o fuera de [range_min, range_max]); como mucho MAX_RAYOS rayos
##   mapa_tesela    UInt8MultiArray  [ver_lo, ver_hi, tx, ty, 256 B: 32×32 celdas a 2 bit, LSB primero]
##                  celda: 0 desconocido, 1 libre (0 ≤ p ≤ 25), 2 ocupado (p ≥ 65); 26–64 = desconocido
##   mapa_meta      Float32MultiArray [res, ancho, alto, ox, oy, teselas_x, teselas_y, version]; version = época
##   joints_orden   String «nombre1,nombre2,…» fiable + TRANSIENT_LOCAL
##   (época, V6: `version` solo sube si cambian resolución, tamaño u origen del mapa; antes con cada OccupancyGrid.
##    El cliente `vita_relay.gd` no cambia: una época nueva con el mismo tamaño solo sobrescribe teselas.)
##
## VC/1 rev. 2 (V6; doc 36 §5.2, sentencia W13 D5). Aditiva: los formatos de arriba no cambian ni un byte.
## Referencia: `docker/scripts/vita_relay_formatos.py` (antes en vita_relay.py, que ahora es solo el nodo).
##   cabecera común de todo formato NUEVO troceado (Float32/Int16MultiArray):
##                  [seq & 0x7FFF, trozo, n_trozos, n, …campos propios…, elementos del trozo], n = elementos de
##                  ESTE trozo; se lee con `cabecera(d)` y se genera con `trocear` (misma salida que Python)
##   relay_info     String fiable + TRANSIENT_LOCAL «VC/1.2;mód1,mód2,…» → `leer_relay_info(s)`
##   rosout         rcl_interfaces/msg/Log (≥ WARN, msg ≤ 200 car.) y diagnostics (DiagnosticArray de UN estado):
##                  tipos estándar, sin formato propio (los leen `visor/displays/hud/{consola,diagnostico}.gd`)

const TESELA := 32
const MAX_RAYOS := 180
const MASCARA_SEQ := 0x7FFF
## Tamaño de diseño de todo /vita/* (D4): ≤ 488 B medidos con rosbags (CDR con encapsulación). = MAX_BE de Python.
const MAX_BE := 488
const MAX_F32 := (MAX_BE - 16) / 4             # 118 floats por Float32MultiArray (16 + 4N)
const MAX_I16 := (MAX_BE - 16) / 2             # 236 int16 por Int16MultiArray (16 + 2N)
const VERSION_CONTRATO := "VC/1.2"


static func _i16(v: float) -> int:
	return clampi(int(v), -32768, 32767)


## Igual que `round()` de Python 3 (redondeo al par en los empates .5) para que los bytes coincidan.
static func _redondear_py(v: float) -> float:
	var r := roundf(v)
	if absf(v - floorf(v) - 0.5) < 1e-9 and fmod(r, 2.0) != 0.0:
		r -= signf(v)
	return r


## LaserScan → [seq, ang_min_cdeg, inc_cdeg, n, r…]; diezma por paso fijo hasta ≤ max_rayos (= vita_relay.py).
static func empaquetar_scan(rangos: PackedFloat32Array, angulo_min: float, incremento: float,
		rango_min: float, rango_max: float, seq: int, max_rayos: int = MAX_RAYOS) -> PackedInt32Array:
	var n_in := rangos.size()
	var paso := maxi(1, ceili(float(n_in) / float(max_rayos)))
	var sel := PackedFloat32Array()
	var i := 0
	while i < n_in and sel.size() < max_rayos:
		sel.append(rangos[i])
		i += paso
	var out := PackedInt32Array([seq & MASCARA_SEQ, _i16(_redondear_py(rad_to_deg(angulo_min) * 100.0)),
		_i16(_redondear_py(rad_to_deg(incremento * paso) * 100.0)), sel.size()])
	for r in sel:
		if is_nan(r) or is_inf(r) or r < rango_min or r > rango_max:
			out.append(0)   # VC/1: 0 = sin dato, también «sin impacto» (antes se enviaba range_max: anillo falso)
		else:
			out.append(_i16(_redondear_py(r * 100.0)))
	return out


## OccupancyGrid (-1 desconocido, 0..100) → 0 desconocido, 1 libre, 2 ocupado (umbrales de map_server, como
## `celda_2bit` de vita_relay.py). Antes las plantillas daban «libre» a todo lo < 65 (R4 §1.2).
static func celda_2bit(v: int) -> int:
	if v < 0:
		return 0
	if v >= 65:
		return 2
	return 1 if v <= 25 else 0


## Una tesela de 32×32 celdas a 2 bit = 4 B de cabecera + 256 B. Celdas fuera del mapa = desconocido.
static func empaquetar_tesela(data: PackedInt32Array, ancho: int, alto: int, tx: int, ty: int,
		version: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4 + TESELA * TESELA / 4)
	b.fill(0)   # VC/1: cuerpo a cero explícito (no depender de lo que deje resize)
	b[0] = version & 0xFF
	b[1] = (version >> 8) & 0xFF
	b[2] = tx
	b[3] = ty
	for j in TESELA:
		var y := ty * TESELA + j
		for i in TESELA:
			var x := tx * TESELA + i
			var c := celda_2bit(data[y * ancho + x]) if (x < ancho and y < alto) else 0
			var k := j * TESELA + i
			b[4 + (k >> 2)] |= c << ((k & 3) * 2)
	return b


static func orden_joints(nombres: PackedStringArray) -> String:
	return ",".join(nombres)


# ---------------------------------------------------------------------------------------------------------------
# VC/1 rev. 2 (V6)
# ---------------------------------------------------------------------------------------------------------------

## Cabecera común de lo troceado [seq & 0x7FFF, trozo, n_trozos, n, …]. {} si no es válida (corta, trozo fuera de
## rango o n negativo). `d` sin anotar: PackedFloat32Array o PackedInt32Array (Int16MultiArray, trampa T6).
static func cabecera(d) -> Dictionary:
	if d == null or d.size() < 4:
		return {}
	var c := {"seq": int(d[0]), "trozo": int(d[1]), "n_trozos": int(d[2]), "n": int(d[3])}
	if c.n_trozos < 1 or c.trozo < 0 or c.trozo >= c.n_trozos or c.n < 0:
		return {}
	return c


## Referencia de bytes: misma salida que `vita_relay_formatos.trocear` (huella cruzada en pruebas/runner.gd).
## `elementos` = Array de Arrays de `por_elemento` números; `extra` = campos propios tras la cabecera. Corta a
## `max_trozos` trozos (estado completo); sin elementos sale un trozo con n = 0.
@warning_ignore("integer_division")
static func trocear(elementos: Array, por_elemento: int, extra: Array = [], seq: int = 0,
		max_valores: int = MAX_F32, max_trozos: int = 3) -> Array:
	var cab := 4 + extra.size()
	var cabe := (max_valores - cab) / por_elemento
	if cabe < 1:
		push_error("VC1.trocear: %d valores por elemento no caben en %d - %d" % [por_elemento, max_valores, cab])
		return []
	var lista := elementos.slice(0, cabe * max_trozos)
	var n_trozos := maxi(1, ceili(float(lista.size()) / cabe))
	var out := []
	for t in n_trozos:
		var parte := lista.slice(t * cabe, (t + 1) * cabe)
		var trozo: Array = [seq & MASCARA_SEQ, t, n_trozos, parte.size()]
		trozo.append_array(extra)
		for e in parte:
			trozo.append_array(e)
		out.append(trozo)
	return out


## «VC/1.2;scan,pose,…» → {"version": "VC/1.2", "modulos": PackedStringArray}; {} si no es un saludo VC/1.
## Con él el HUD distingue «sin datos» (módulo activo, nada llega) de «módulo apagado» (no está en la lista).
static func leer_relay_info(s: String) -> Dictionary:
	if not s.begins_with("VC/1") or not s.contains(";"):
		return {}
	var k := s.find(";")
	var mods := PackedStringArray()
	for m in s.substr(k + 1).split(",", false):
		mods.append(m)
	return {"version": s.left(k), "modulos": mods}


# ---------------------------------------------------------------------------------------------------------------
# Marcadores (V8; doc 36 §5.3, 36a §4.7.4, sentencia W13 D14). Referencia: `vita_relay_formatos.py` (bloque
# «marcadores»); huellas cruzadas en `docker/scripts/test_vita_relay.py` y `pruebas/visor_marcadores.gd`.
##   marcadores       Float32MultiArray BE 5 Hz, ESTADO COMPLETO: cab. común + [clave, tipo, x, y, z, yaw, sx, sy,
##                    sz, color]·n, n ≤ 11 por trozo, ≤ 33 marcadores (3 trozos de ≤ 472 B); pose en el marco fijo
##                    (ejes ROS). Al completar un seq, la Vita recicla lo que no llegó (sin fantasmas).
##   marcador_puntos  Float32MultiArray BE ≤ 4/s: cab. común + [clave, tipo, color, ancho] + xyz·n, n ≤ 36 por trozo
##   marcador_texto   String fiable ≤ 2/s: «clave|x|y|z|texto» (≤ 80 car.)
##   clave = (id ⊕ fnv1a32(ns)) & 0xFFFFFF; color = índice de PaletaViz + 256 · alfa (0–15)
# ---------------------------------------------------------------------------------------------------------------
const POR_MARCADOR := 10
const MAX_MARCADORES := 33
const EXTRA_PUNTOS := 4
const MAX_CAR_TEXTO_MARCADOR := 80


## FNV-1a de 32 bit del ns en UTF-8 (= `hash_ns` de Python).
static func hash_ns(ns: String) -> int:
	var h := 0x811C9DC5
	for b in ns.to_utf8_buffer():
		h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
	return h


static func clave_marcador(ns: String, id: int) -> int:
	return (id ^ hash_ns(ns)) & 0xFFFFFF


static func color_marcador(indice: int, alfa: float) -> int:
	return clampi(indice, 0, 255) + 256 * clampi(int(alfa * 15.0 + 0.5), 0, 15)


## color compacto → [índice de paleta, alfa 0–1].
static func leer_color_marcador(c: int) -> Array:
	return [c & 0xFF, float((c >> 8) & 0xF) / 15.0]


## Estado completo → ≤ 3 trozos (≤ 33 marcadores); vacío = un trozo con n = 0.
static func empaquetar_marcadores(elementos: Array, seq: int) -> Array:
	return trocear(elementos.slice(0, MAX_MARCADORES), POR_MARCADOR, [], seq, MAX_F32, 3)


## Un marcador de líneas/puntos: puntos = Array de [x, y, z] (marco fijo, ejes ROS) → ≤ 3 trozos de ≤ 36 puntos.
static func empaquetar_puntos(clave: int, tipo: int, color: int, ancho: float, puntos: Array, seq: int) -> Array:
	return trocear(puntos, 3, [clave, tipo, color, ancho], seq, MAX_F32, 3)


static func texto_marcador(clave: int, x: float, y: float, z: float, texto: String) -> String:
	return "%d|%.3f|%.3f|%.3f|%s" % [clave, x, y, z, texto.left(MAX_CAR_TEXTO_MARCADOR)]


## «clave|x|y|z|texto» → {clave, pos (Vector3 ROS), texto}; {} si no vale.
static func leer_texto_marcador(s: String) -> Dictionary:
	var p := s.split("|", true, 4)
	if p.size() != 5 or not p[0].is_valid_int():
		return {}
	return {"clave": p[0].to_int(), "pos": Vector3(p[1].to_float(), p[2].to_float(), p[3].to_float()), "texto": p[4]}
