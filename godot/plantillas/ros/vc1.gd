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

const TESELA := 32
const MAX_RAYOS := 180
const MASCARA_SEQ := 0x7FFF


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
