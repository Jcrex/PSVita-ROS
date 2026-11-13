extends Node3D
## Mundo común de las plantillas (bosque, ciudad, parque y casa). Desde el 2026-11-13 el mundo ES la escena
## `mundo.tscn` (regla de escenas, doc 35): cada caja y cada modelo es un nodo que se coloca en el editor. Este
## script solo ADAPTA esa escena al arrancar:
##  - cajas (`caja_mundo.gd`): les pone la colisión si son sólidas;
##  - modelos (`asset_mundo.gd`): crea su malla (de PC o de la Vita) y registra los que se mueven.
##
## Perfil «Vita ligero» (2026-11-13, objetivo 60 FPS; ADR 0011 §6: HMI = 15 000 triángulos y 80 instancias).
## En la Vita, o con `-- lod=vita` en el PC (Perfil.es_ligero()). Cambia solo lo que se DIBUJA; las colisiones son
## las mismas, así que rayos, LiDAR y mapa no cambian:
##  1. Cajas fundidas en una malla por color (28 draws → 11) y, en las láminas del suelo, solo la cara de arriba.
##  2. `modelo_vita` de cada modelo: variante de pocos triángulos (tools/generar-lod-vita.py).
##  3. `dibujar_en_vita = false`: adorno pequeño que no se dibuja (comida, libros…).
##  4. Visibilidad por distancia al robot (`enfocar()`): fuera de `radio_visible` no se dibuja nada pequeño. El
##     rasterizador GXM ya descarta a más de 40 m (gxm_camera_lod.h), pero desde la casa se veía media ciudad.

const Util = preload("res://comun/ros/util_ros.gd")
const Perfil = preload("res://comun/ros/perfil.gd")
const CajaMundo = preload("res://comun/mundo/caja_mundo.gd")
const AssetMundo = preload("res://comun/mundo/asset_mundo.gd")

## Si nadie lo fija antes de entrar en el árbol (las pruebas lo hacen), _ready() lo decide con Perfil.es_ligero().
var perfil_ligero := false:
	set(v):
		perfil_ligero = v
		_perfil_fijado = true
## Radio (m) alrededor del foco en el que se dibujan los assets, más el radio del propio asset. ≤ 0 = sin límite.
var radio_visible := 14.0

var _perfil_fijado := false
var _agentes: Array[Dictionary] = []
var _tiempo := 0.0
var _assets_visibles: Array[Dictionary] = []   # {nodo: Node3D, radio: float}; solo con perfil_ligero
var _cajas_por_color := {}                     # Color -> SurfaceTool; solo con perfil_ligero
var _triangulos_malla := {}                    # Mesh -> triángulos (caché de contar_dibujado)


func _ready() -> void:
	if not _perfil_fijado:
		perfil_ligero = Perfil.es_ligero()
	var cajas: Array[Node] = []
	var assets: Array[Node] = []
	_buscar(self, cajas, assets)
	for c in cajas:
		_preparar_caja(c)
	_fundir_cajas()
	for a in assets:
		_preparar_asset(a)


func _buscar(n: Node, cajas: Array[Node], assets: Array[Node]) -> void:
	for h in n.get_children():
		if h.get_script() == CajaMundo:
			cajas.append(h)
		elif h.get_script() == AssetMundo:
			assets.append(h)
		else:
			_buscar(h, cajas, assets)


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


func _color(caja) -> Color:
	var m = caja.mesh.material
	return m.albedo_color if m is BaseMaterial3D else Color.WHITE


func _preparar_caja(caja) -> void:   # caja_mundo.gd (MeshInstance3D)
	var box := caja.mesh as BoxMesh
	if box == null:
		push_warning("Caja sin BoxMesh: " + caja.name)
		return
	if not perfil_ligero:
		if caja.solido:
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var forma := BoxShape3D.new()
			forma.size = box.size
			shape.shape = forma
			body.add_child(shape)
			caja.add_child(body)
		return
	# Perfil ligero: la caja no es un nodo con su malla, sino 2 o 12 triángulos más en la malla de su color. El
	# nodo que queda (solo si es sólida) lleva únicamente la colisión, igual que antes.
	var xf: Transform3D = global_transform.affine_inverse() * caja.global_transform
	_fundir_caja(xf, box.size, _color(caja), caja.solido)
	var padre: Node = caja.get_parent()
	var nombre: StringName = caja.name
	var local: Transform3D = caja.transform
	var solido: bool = caja.solido
	padre.remove_child(caja)
	caja.free()
	if solido:
		var cuerpo := StaticBody3D.new()
		cuerpo.name = nombre
		var shape := CollisionShape3D.new()
		var forma := BoxShape3D.new()
		forma.size = box.size
		shape.shape = forma
		cuerpo.add_child(shape)
		cuerpo.transform = local
		padre.add_child(cuerpo)


func _fundir_caja(xf: Transform3D, tam: Vector3, color: Color, solido: bool) -> void:
	var st: SurfaceTool = _cajas_por_color.get(color)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_cajas_por_color[color] = st
	var h := tam * 0.5
	# Caras: [normal, eje u, eje v] con u × v = normal. Godot dibuja la cara cuyos vértices van en sentido horario
	# vista de frente, así que los triángulos se emiten (p0, p2, p1) y (p0, p3, p2). Lo comprueba
	# pruebas/perfil_ligero.gd comparando con BoxMesh.
	var caras := [
		[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
		[Vector3.RIGHT, Vector3.BACK, Vector3.DOWN], [Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN],
		[Vector3.BACK, Vector3.LEFT, Vector3.DOWN], [Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN],
	]
	# Lámina pegada al suelo y sin colisión (zonas, carreteras, pasos de peatones): solo se ve la cara de arriba.
	var n_caras := 1 if (not solido and tam.y <= 0.05) else 6
	for i in n_caras:
		var nrm: Vector3 = caras[i][0]
		var u: Vector3 = caras[i][1] * h
		var v: Vector3 = caras[i][2] * h
		var c: Vector3 = nrm * h
		var p0 := c - u - v
		var p1 := c + u - v
		var p2 := c + u + v
		var p3 := c - u + v
		var nrm_g := (xf.basis * nrm).normalized()
		for p in [p0, p2, p1, p0, p3, p2]:
			st.set_normal(nrm_g)
			st.add_vertex(xf * p)


func _fundir_cajas() -> void:
	var i := 0
	for color in _cajas_por_color:
		var st: SurfaceTool = _cajas_por_color[color]
		var mesh := st.commit()
		mesh.surface_set_material(0, _material(color))
		var n := MeshInstance3D.new()
		n.name = "Cajas%d" % i
		n.mesh = mesh
		add_child(n)
		i += 1
	_cajas_por_color.clear()


func _preparar_asset(a) -> void:   # asset_mundo.gd (Node3D)
	var visual: Node3D = a.montar(perfil_ligero)
	if visual == null and not a.tiene_colision() and not a.se_mueve():
		a.get_parent().remove_child(a)   # adorno sin colisión: en el perfil ligero no existe
		a.free()
		return
	if perfil_ligero and visual != null:
		var radio := 1.0
		if visual is MeshInstance3D and visual.mesh != null:
			radio = visual.mesh.get_aabb().size.length() * 0.5 * maxf(a.scale.x, maxf(a.scale.y, a.scale.z))
		_assets_visibles.append({"nodo": a, "radio": radio})
	if a.se_mueve():
		_agentes.append({"nodo": a, "centro": a.position, "radio": a.radio_movimiento,
			"velocidad": a.velocidad_movimiento, "fase": a.fase_movimiento})


func _process(dt: float) -> void:
	if Perfil.activo:
		var t := Perfil.t0()
		_mover_agentes(dt)
		Perfil.sumar("mundo", t)
	else:
		_mover_agentes(dt)


func _mover_agentes(dt: float) -> void:
	_tiempo += dt
	for a in _agentes:
		# Perfil ligero: un agente que no se dibuja (lejos del robot, fuera también del alcance del LiDAR) no se
		# mueve; al volver a verse salta a su sitio en la órbita.
		if perfil_ligero and not a.nodo.visible:
			continue
		var fase: float = _tiempo * a.velocidad + a.fase
		var delta: Vector3 = Vector3(cos(fase), 0.0, sin(fase)) * a.radio
		a.nodo.position = a.centro + delta
		a.nodo.rotation.y = -fase


## Perfil ligero: dibuja solo los assets a menos de `radio_visible` (+ su radio) del foco, normalmente el robot.
## Con histéresis del 15 % para que un asset en el borde no parpadee. La aplicación lo llama unas 4 veces por
## segundo; son ~50 distancias, despreciable. Devuelve cuántos assets quedan visibles.
func enfocar(foco: Vector3) -> int:
	var visibles := 0
	for a in _assets_visibles:
		var nodo: Node3D = a.nodo
		var limite: float = radio_visible + a.radio
		if nodo.visible:
			limite *= 1.15
		var g := nodo.global_position
		var d := Vector2(g.x - foco.x, g.z - foco.z).length_squared()
		var ver: bool = radio_visible <= 0.0 or d < limite * limite
		if ver != nodo.visible:
			nodo.visible = ver
		if ver:
			visibles += 1
	return visibles


## Contador propio para medir el presupuesto del ADR 0011 sin GPU (vale en headless): triángulos, mallas
## (instancias) y superficies (draws sin contar la pasada de luz) de lo que está visible bajo `raiz`.
## Con `camara`, cuenta solo las mallas cuya esfera envolvente toca el tronco de la cámara y queda a menos de
## 40 m (lo mismo que hacen el motor y gxm_camera_lod.h): es el equivalente en el PC de `submitted_triangles` y
## `visible_instances` del log `[gxm3d]`. Sin cámara es la cota superior.
## `aspecto` > 0 calcula el tronco con esa relación ancho/alto en vez de la de la ventana: en headless la ventana
## es de 64×64 y la Vita es 960×544 (1,765), que abarca bastante más a los lados.
func contar_dibujado(raiz: Node = self, camara: Camera3D = null, aspecto: float = 0.0) -> Dictionary:
	var r := {"triangulos": 0, "mallas": 0, "superficies": 0}
	var planos: Array[Plane] = []
	if camara != null and aspecto > 0.0:
		var proyeccion := Projection.create_perspective(camara.fov, aspecto, camara.near, camara.far)
		for i in 6:
			planos.append(camara.global_transform * proyeccion.get_projection_plane(i))
	elif camara != null:
		planos = camara.get_frustum()
	_contar(raiz, r, planos, camara.global_position if camara != null else Vector3.ZERO)
	return r


func _contar(n: Node, r: Dictionary, planos: Array[Plane], ojo: Vector3) -> void:
	if n is Node3D and not n.visible:
		return
	if n is MeshInstance3D and n.mesh != null and _en_vista(n, planos, ojo):
		r.mallas += 1
		r.superficies += n.mesh.get_surface_count()
		if not _triangulos_malla.has(n.mesh):
			var t := 0
			for s in n.mesh.get_surface_count():
				var arrays: Array = n.mesh.surface_get_arrays(s)
				var indices = arrays[Mesh.ARRAY_INDEX]
				if indices != null and indices.size() > 0:
					t += indices.size() / 3
				else:
					t += arrays[Mesh.ARRAY_VERTEX].size() / 3
			_triangulos_malla[n.mesh] = t
		r.triangulos += _triangulos_malla[n.mesh]
	for hijo in n.get_children():
		_contar(hijo, r, planos, ojo)


func _en_vista(n: MeshInstance3D, planos: Array[Plane], ojo: Vector3) -> bool:
	if planos.is_empty():
		return true
	var caja: AABB = n.mesh.get_aabb()
	var g := n.global_transform
	var centro: Vector3 = g * caja.get_center()
	var escala := g.basis.get_scale().abs()
	var radio: float = caja.size.length() * 0.5 * maxf(escala.x, maxf(escala.y, escala.z))
	if ojo.distance_to(centro) - radio > 40.0:
		return false
	for p in planos:   # los planos del tronco miran hacia fuera
		if p.distance_to(centro) > radio:
			return false
	return true
