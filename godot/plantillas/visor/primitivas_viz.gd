extends RefCounted
## PrimitivasViz (ADR 0013 §2; doc 36 §3; W13 D2): mallas unidad del 3D del visor, poses y conversiones de ejes.
## LA biblioteca de formas (D2 funde `primitivas.gd`, `fabrica.gd` y `paletas.gd` de los borradores);
## `fabrica_marcadores.gd` (V8) solo traducirá Marker/shape_msgs a llamadas de aquí.
##
## Reglas (doc 36 §3.1; hechos de docs/31 §1):
## - Solo `PRIMITIVE_TRIANGLES` (H1), sin MultiMesh (H2), sin color por vértice ni normales (H3: el port solo
##   guarda xyz + uv); color por UV a PaletaViz y UN material para todas (ADR 0011 §3).
## - Mallas unidad **compartidas** por (forma, color) y cacheadas, con tope de MAX_VARIANTES = 64: cada malla
##   nueva cuesta ≈ 60 B por triángulo en el arena de 24 MiB, que no libera (H3, H9). Un visual = un
##   `MeshInstance3D` que solo cambia `transform`; nunca se reconstruye geometría por mensaje (salvo `cinta`, con
##   tope de Hz en quien la use).
## - Sin *culling* (H15): los tubos sin tapa y las cintas se ven por las dos caras.
## - Todo en **ejes de Godot**. El eje de las formas con dirección (FLECHA, CONO, eje X de EJES) es **−Z de
##   Godot = +X de ROS**, que es lo que da `Basis.looking_at`.
##
## Triángulos por forma (tabla D2; doc 36 §3.2), iguales en PC y Vita (un solo camino de código):
## CUBO 12, ESFERA 8 (octaedro), CILINDRO 32, CONO 16, FLECHA 24, EJES 36, DISCO 12, ANILLO 56.
##
## Uso: `const Prim = preload("res://comun/visor/primitivas_viz.gd")`; `var mi := Prim.instancia(Prim.FLECHA,
## Color.RED)`; luego solo `mi.transform = …`. Sin `class_name` (D15).

const Paleta = preload("res://comun/visor/paleta_viz.gd")

## 1–3 coinciden con `visualization_msgs/Marker` (CUBE = 1, SPHERE = 2, CYLINDER = 3).
enum { CUBO = 1, ESFERA = 2, CILINDRO = 3, CONO = 4, FLECHA = 5, EJES = 6, DISCO = 7, ANILLO = 8 }

const FORMAS := [CUBO, ESFERA, CILINDRO, CONO, FLECHA, EJES, DISCO, ANILLO]
const TRIANGULOS := {CUBO: 12, ESFERA: 8, CILINDRO: 32, CONO: 16, FLECHA: 24, EJES: 36, DISCO: 12, ANILLO: 56}
const MAX_VARIANTES := 64

## Medidas de la FLECHA unidad (largo 1 sobre −Z): cuerpo 0,77 y cabeza 0,23 como la ARROW de RViz
## (`arrow_marker.cpp:160-180`, doc 36 §3.2); radios del esqueleto de doc 36 §3.4.
const FLECHA_CUERPO := 0.77
const FLECHA_R_ASTA := 0.04
const FLECHA_R_PUNTA := 0.1
const EJES_GROSOR := 0.04
## ANILLO: el arco de `wrench_visual.cpp` (i = 4..32 de 36 pasos: de 40° a 320°, 28 segmentos de 10°).
const ANILLO_SEGMENTOS := 28
const ANILLO_R_INT := 0.45
const ANILLO_R_EXT := 0.5

## Columnas = ejes X, Y, Z de ROS en Godot (= `BASE_ROS_A_GODOT` de `godot/plantillas/ros/util_ros.gd:6`).
const C := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))

static var _mallas := {}                       # Vector2i(forma, índice de color) -> ArrayMesh
static var _n_color := 0                       # variantes con color distinto del blanco
static var _avisado := false


## Malla unidad compartida de `forma` en el color `indice_color` de PaletaViz.
## EJES ignora el color (lleva sus tres). Con el cupo de color lleno (64 − 8 huecos reservados para el blanco de
## cada forma) devuelve la variante blanca: así el total nunca pasa de MAX_VARIANTES.
static func malla(forma: int, indice_color: int = Paleta.BLANCO) -> ArrayMesh:
	if not TRIANGULOS.has(forma):
		push_error("PrimitivasViz: forma desconocida %d" % forma)
		return null
	var ic := 0 if forma == EJES else clampi(indice_color, 0, Paleta.TRANSPARENTE - 1)
	var k := Vector2i(forma, ic)
	if _mallas.has(k):
		return _mallas[k]
	if ic != Paleta.BLANCO and _n_color >= MAX_VARIANTES - FORMAS.size():
		if not _avisado:
			_avisado = true
			push_warning("PrimitivasViz: más de %d variantes (forma, color); se reutiliza el blanco" % MAX_VARIANTES)
		return malla(forma, Paleta.BLANCO)
	var m := _construir(forma, ic)
	_mallas[k] = m
	if ic != Paleta.BLANCO:
		_n_color += 1
	return m


## Nuevo `MeshInstance3D` con la malla compartida (color cuantizado a la paleta). Solo se le cambia `transform`.
static func instancia(forma: int, color: Color = Color.WHITE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = malla(forma, Paleta.indice(color))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Nº de variantes cacheadas (prueba y diagnóstico).
static func variantes() -> int:
	return _mallas.size()


## Vacía la caché (pruebas, o al cambiar de escena entera). Las instancias vivas conservan su malla.
static func vaciar() -> void:
	_mallas.clear()
	_n_color = 0
	_avisado = false


static func _construir(forma: int, ic: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var t := PackedVector2Array()
	match forma:
		CUBO:
			_caja(v, t, Vector3.ZERO, Vector3.ONE, ic)
		ESFERA:
			_octaedro(v, t, 0.5, ic)
		CILINDRO:                              # eje +Y de Godot = +Z de ROS (Marker CYLINDER), con tapas
			_tubo(v, t, 8, -0.5, 0.5, 0.5, 0.5, ic, true)
			_tapa(v, t, 8, -0.5, 0.5, ic, true)
			_tapa(v, t, 8, 0.5, 0.5, ic, true)
		CONO:                                  # vértice en el origen, base en z = −1 (Godot), radio 0,5
			_tubo(v, t, 8, 0.0, 1.0, 0.0, 0.5, ic, false, true)
			_tapa(v, t, 8, 1.0, 0.5, ic)
		FLECHA:                                # asta (tubo de 6) + punta (cono de 6 con base)
			_tubo(v, t, 6, 0.0, FLECHA_CUERPO, FLECHA_R_ASTA, FLECHA_R_ASTA, ic)
			_tubo(v, t, 6, FLECHA_CUERPO, 1.0, FLECHA_R_PUNTA, 0.0, ic, false, true)
			_tapa(v, t, 6, FLECHA_CUERPO, FLECHA_R_PUNTA, ic)
		EJES:                                  # X ROS = −Z (rojo), Y ROS = −X (verde), Z ROS = +Y (azul)
			var g := EJES_GROSOR
			_caja(v, t, Vector3(0, 0, -0.5), Vector3(g, g, 1.0), Paleta.ROJO)
			_caja(v, t, Vector3(-0.5, 0, 0), Vector3(1.0, g, g), Paleta.VERDE)
			_caja(v, t, Vector3(0, 0.5, 0), Vector3(g, 1.0, g), Paleta.AZUL)
		DISCO:                                 # plano XY de ROS = XZ de Godot, radio 0,5
			_tapa(v, t, 12, 0.0, 0.5, ic, true)
		ANILLO:                                # cinta plana en el plano XY de ROS, eje = +Z ROS (+Y Godot)
			_arco(v, t, ANILLO_SEGMENTOS, deg_to_rad(40.0), deg_to_rad(320.0), ANILLO_R_INT, ANILLO_R_EXT, ic)
	return _malla_de(v, t)


## Una superficie, PRIMITIVE_TRIANGLES, solo vértices + UV, con el material de la paleta.
static func _malla_de(v: PackedVector3Array, t: PackedVector2Array) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = t
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, Paleta.material())
	return m


static func _tri(v: PackedVector3Array, t: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, ic: int) -> void:
	var u := Paleta.uv(ic)
	v.append(a)
	v.append(b)
	v.append(c)
	t.append(u)
	t.append(u)
	t.append(u)


## Punto del perfil (radio r, ángulo a, posición z sobre −Z) en ejes Godot; con `eje_y`, el eje es +Y.
static func _p(r: float, a: float, z: float, eje_y: bool) -> Vector3:
	var x := cos(a) * r
	var y := sin(a) * r
	return Vector3(x, z, y) if eje_y else Vector3(x, y, -z)


## Tubo/cono sobre −Z (o +Y) entre z0 y z1 con radios r0, r1 y n lados, sin tapas (2n triángulos).
## `punta` = r1 es 0: un triángulo por lado en lugar de un quad degenerado (n triángulos).
static func _tubo(v: PackedVector3Array, t: PackedVector2Array, n: int, z0: float, z1: float, r0: float,
		r1: float, ic: int, eje_y := false, punta := false) -> void:
	for i in n:
		var a := TAU * i / n
		var b := TAU * (i + 1) / n
		if punta or r0 == 0.0:
			# cono: base del lado de radio no nulo, vértice en el otro extremo
			var zb := z0 if r0 > 0.0 else z1
			var rb := r0 if r0 > 0.0 else r1
			var za := z1 if r0 > 0.0 else z0
			_tri(v, t, _p(rb, a, zb, eje_y), _p(rb, b, zb, eje_y), _p(0.0, 0.0, za, eje_y), ic)
		else:
			var a0 := _p(r0, a, z0, eje_y)
			var a1 := _p(r1, a, z1, eje_y)
			var b0 := _p(r0, b, z0, eje_y)
			var b1 := _p(r1, b, z1, eje_y)
			_tri(v, t, a0, a1, b0, ic)
			_tri(v, t, b0, a1, b1, ic)


## Tapa: abanico de n triángulos de radio r en la posición z del eje (n triángulos).
static func _tapa(v: PackedVector3Array, t: PackedVector2Array, n: int, z: float, r: float, ic: int,
		eje_y := false) -> void:
	var centro := _p(0.0, 0.0, z, eje_y)
	for i in n:
		_tri(v, t, centro, _p(r, TAU * i / n, z, eje_y), _p(r, TAU * (i + 1) / n, z, eje_y), ic)


## Caja de `lados` centrada en `centro` (12 triángulos).
static func _caja(v: PackedVector3Array, t: PackedVector2Array, centro: Vector3, lados: Vector3, ic: int) -> void:
	var h := lados * 0.5
	var p := []
	for k in 8:                                # esquina k: bits (x, y, z) → signo −/+
		p.append(centro + Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
	# 6 caras como quads (índices de esquina); 2 triángulos cada una
	for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_tri(v, t, p[q[0]], p[q[1]], p[q[2]], ic)
		_tri(v, t, p[q[0]], p[q[2]], p[q[3]], ic)


## Octaedro de radio r (8 triángulos): la «esfera» barata de la Vita.
static func _octaedro(v: PackedVector3Array, t: PackedVector2Array, r: float, ic: int) -> void:
	var ejes := [Vector3(r, 0, 0), Vector3(0, 0, r), Vector3(-r, 0, 0), Vector3(0, 0, -r)]
	for i in 4:
		var a: Vector3 = ejes[i]
		var b: Vector3 = ejes[(i + 1) % 4]
		_tri(v, t, Vector3(0, r, 0), a, b, ic)
		_tri(v, t, Vector3(0, -r, 0), b, a, ic)


## Arco plano (cinta) en el plano XZ de Godot entre los ángulos a0 y a1 (ángulo ROS desde +X hacia +Y).
static func _arco(v: PackedVector3Array, t: PackedVector2Array, n: int, a0: float, a1: float, ri: float,
		re: float, ic: int) -> void:
	for i in n:
		var a := lerpf(a0, a1, float(i) / n)
		var b := lerpf(a0, a1, float(i + 1) / n)
		var ia := C * Vector3(cos(a) * ri, sin(a) * ri, 0.0)
		var ea := C * Vector3(cos(a) * re, sin(a) * re, 0.0)
		var ib := C * Vector3(cos(b) * ri, sin(b) * ri, 0.0)
		var eb := C * Vector3(cos(b) * re, sin(b) * re, 0.0)
		_tri(v, t, ia, ea, ib, ic)
		_tri(v, t, ib, ea, eb, ic)


# --- Poses y conversiones ------------------------------------------------------------------------------------------

## geometry_msgs/Pose (RosMsg) → Transform3D Godot. Cuaternión nulo → identidad (RViz lo rechaza; trampa T14).
static func pose_godot(p) -> Transform3D:
	var o = p.orientation
	var x = p.position
	var q := Quaternion(o.x, o.y, o.z, o.w)
	q = q.normalized() if q.length_squared() > 1e-6 else Quaternion.IDENTITY
	return Transform3D(Basis(rclgd.ros_to_godot_quat(q)), rclgd.ros_to_godot_vector(Vector3(x.x, x.y, x.z)))


## Escala de Marker/shape (ROS x, y, z) → ejes locales de Godot (mapas#13): ROS X = −Z, Y = −X, Z = +Y.
static func escala_ros(s) -> Vector3:
	return Vector3(absf(s.y), absf(s.z), absf(s.x))


## Transform3D que lleva la FLECHA unidad (−Z, largo 1) a apuntar a `v` (ejes Godot) con largo |v|.
## v ≈ 0 → null (oculto): `Basis.looking_at` con vector nulo da error (T13).
static func flecha_hacia(v: Vector3):
	var largo := v.length()
	if largo < 1e-6:
		return null
	var arriba := Vector3.UP if absf(v.y / largo) < 0.99 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(v, arriba).scaled_local(Vector3(1, 1, largo)), Vector3.ZERO)


## Matriz simétrica 3×3 en ejes ROS (covarianza, inercia) → ejes Godot: C·B·Cᵀ.
static func a_godot(b_ros: Basis) -> Basis:
	return C * b_ros * C.transposed()


## Grosor mínimo (m) de una caja fina para que no parpadee sin MSAA: 1,5 px a `distancia` m (docs/31 §2.2;
## focal ≈ 522 px con fov 55° a 544 px de alto). Se aplica escalando la instancia, nunca la malla.
static func grosor_minimo(distancia: float, focal_px := 522.0) -> float:
	return 1.5 * distancia / focal_px


## Cinta plana horizontal (2 triángulos por segmento, ancho perpendicular a UP), puntos en ejes Godot.
## NO se cachea ni cuenta como variante: quien la use la reconstruye solo si cambian los puntos y con tope de
## Hz (Path ≤ 2 Hz, ADR 0011 §4), porque cada malla nueva gasta arena (H9).
static func cinta(puntos: PackedVector3Array, ancho: float, ic: int = Paleta.BLANCO, cerrada := false) -> ArrayMesh:
	var v := PackedVector3Array()
	var t := PackedVector2Array()
	var n := puntos.size()
	if n >= 2:
		for i in (n if cerrada else n - 1):
			var a := puntos[i]
			var b := puntos[(i + 1) % n]
			var d := b - a
			var lado := d.cross(Vector3.UP)
			if lado.length_squared() < 1e-12:      # segmento vertical o nulo: ancho a lo largo de X
				lado = Vector3.RIGHT
			lado = lado.normalized() * ancho * 0.5
			_tri(v, t, a - lado, a + lado, b - lado, ic)
			_tri(v, t, b - lado, a + lado, b + lado, ic)
	if v.is_empty():
		return ArrayMesh.new()                 # sin superficies: nada que dibujar
	return _malla_de(v, t)
