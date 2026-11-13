extends Node3D

const Util = preload("res://comun/ros/util_ros.gd")
const Perfil = preload("res://comun/ros/perfil.gd")

## Perfil «Vita ligero» (2026-11-13, objetivo 60 FPS; ADR 0011 §6: HMI = 15 000 triángulos y 80 instancias).
## Lo activa la aplicación ANTES de añadir el mundo al árbol (en la Vita, o con `-- lod=vita` en el PC). Cambia
## solo lo que se DIBUJA; las colisiones son las mismas, así que rayos, LiDAR y mapa no cambian:
##  1. Cajas del terreno y de la casa fundidas en una malla por color (28 draws → 11) y, en las láminas del suelo,
##     solo la cara de arriba.
##  2. `"modelo_vita"` de assets.json: variante de pocos triángulos (tools/generar-lod-vita.py).
##  3. `"vita": false` de assets.json: adorno pequeño que no se dibuja (comida, libros…).
##  4. Visibilidad por distancia al robot (`enfocar()`): fuera de `radio_visible` no se dibuja nada pequeño. El
##     rasterizador GXM ya descarta a más de 40 m (gxm_camera_lod.h), pero desde la casa se veía media ciudad.
var perfil_ligero := false
## Radio (m) alrededor del foco en el que se dibujan los assets, más el radio del propio asset. ≤ 0 = sin límite.
var radio_visible := 14.0

var _agentes: Array[Dictionary] = []
var _tiempo := 0.0
var _assets_visibles: Array[Dictionary] = []   # {nodo: Node3D, radio: float}; solo con perfil_ligero
var _cajas_por_color := {}                     # Color -> SurfaceTool; solo con perfil_ligero
var _triangulos_malla := {}                    # Mesh -> triángulos (caché de contar_dibujado)


func _ready() -> void:
	_construir_terreno()
	_construir_casa()
	_fundir_cajas()
	_cargar_assets()


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


func _caja(nombre: String, pos_ros: Vector3, tam_ros: Vector3, color: Color, solido: bool = true) -> Node3D:
	if perfil_ligero:
		return _caja_ligera(nombre, pos_ros, tam_ros, color, solido)
	var n := MeshInstance3D.new()
	n.name = nombre
	var mesh := BoxMesh.new()
	mesh.size = Vector3(tam_ros.y, tam_ros.z, tam_ros.x)
	mesh.material = _material(color)
	n.mesh = mesh
	n.position = Util.vector_godot(pos_ros)
	add_child(n)
	if solido:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = mesh.size
		shape.shape = box
		body.add_child(shape)
		n.add_child(body)
	return n


## Perfil ligero: la caja no es un nodo con su malla, sino 2 o 12 triángulos más en la malla de su color. El nodo
## que queda (solo si es sólida) lleva únicamente la colisión, igual que antes.
func _caja_ligera(nombre: String, pos_ros: Vector3, tam_ros: Vector3, color: Color, solido: bool) -> Node3D:
	var tam := Vector3(tam_ros.y, tam_ros.z, tam_ros.x)
	var centro := Util.vector_godot(pos_ros)
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
		var c: Vector3 = centro + nrm * h
		var p0 := c - u - v
		var p1 := c + u - v
		var p2 := c + u + v
		var p3 := c - u + v
		for p in [p0, p2, p1, p0, p3, p2]:
			st.set_normal(nrm)
			st.add_vertex(p)
	if not solido:
		return null
	var cuerpo := StaticBody3D.new()
	cuerpo.name = nombre
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = tam
	shape.shape = box
	cuerpo.add_child(shape)
	cuerpo.position = centro
	add_child(cuerpo)
	return cuerpo


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


func _construir_terreno() -> void:
	_caja("Suelo", Vector3(0.0, 0.0, -0.15), Vector3(52.0, 52.0, 0.3), Color(0.32, 0.48, 0.24))
	_caja("Bosque", Vector3(-13.0, 13.0, 0.01), Vector3(24.0, 24.0, 0.03), Color(0.18, 0.34, 0.16), false)
	_caja("Ciudad", Vector3(13.0, 13.0, 0.02), Vector3(24.0, 24.0, 0.04), Color(0.48, 0.48, 0.43), false)
	_caja("Parque", Vector3(-13.0, -13.0, 0.02), Vector3(24.0, 24.0, 0.04), Color(0.35, 0.55, 0.25), false)
	_caja("CarreteraNS", Vector3(12.0, 12.0, 0.05), Vector3(4.0, 24.0, 0.04), Color(0.12, 0.13, 0.15), false)
	_caja("CarreteraEO", Vector3(12.0, 12.0, 0.06), Vector3(24.0, 4.0, 0.04), Color(0.12, 0.13, 0.15), false)
	for i in 10:
		_caja("PasoPeatones%d" % i, Vector3(9.0 + i * 0.65, 9.8, 0.09), Vector3(0.35, 2.0, 0.02), Color(0.85, 0.85, 0.78), false)
	_caja("SenderoParque", Vector3(-12.0, -12.0, 0.06), Vector3(2.0, 20.0, 0.03), Color(0.65, 0.53, 0.36), false)
	_caja("Colina", Vector3(-20.0, 20.0, 0.35), Vector3(7.0, 6.0, 0.7), Color(0.25, 0.4, 0.18))
	_caja("ObstaculoRampa", Vector3(-4.0, -4.0, 0.2), Vector3(2.0, 1.0, 0.4), Color(0.62, 0.4, 0.18))


func _construir_casa() -> void:
	var pared := Color(0.82, 0.78, 0.68)
	_caja("CasaSuelo", Vector3(10.0, -14.0, 0.08), Vector3(12.0, 10.0, 0.16), Color(0.55, 0.37, 0.22))
	_caja("CasaNorte", Vector3(10.0, -9.0, 1.25), Vector3(12.0, 0.18, 2.5), pared)
	_caja("CasaSurIzq", Vector3(5.5, -19.0, 1.25), Vector3(3.0, 0.18, 2.5), pared)
	_caja("CasaSurDer", Vector3(13.5, -19.0, 1.25), Vector3(5.0, 0.18, 2.5), pared)
	_caja("CasaOeste", Vector3(4.0, -14.0, 1.25), Vector3(0.18, 10.0, 2.5), pared)
	_caja("CasaEste", Vector3(16.0, -14.0, 1.25), Vector3(0.18, 10.0, 2.5), pared)
	_caja("CasaTabiqueA", Vector3(10.0, -12.0, 1.25), Vector3(0.15, 5.0, 2.5), pared)
	_caja("CasaTabiqueB", Vector3(7.0, -14.5, 1.25), Vector3(5.0, 0.15, 2.5), pared)


func _cargar_assets() -> void:
	var datos = JSON.parse_string(FileAccess.get_file_as_string("res://comun/mundo/assets.json"))
	if datos == null:
		push_error("Falta o es inválido res://comun/mundo/assets.json")
		return
	for entrada in datos:
		var dibujar: bool = not (perfil_ligero and entrada.get("vita", true) == false)
		if not dibujar and not entrada.has("colision") and not entrada.has("movimiento"):
			continue   # adorno sin colisión: en el perfil ligero no existe
		var ruta: String = entrada.modelo
		if perfil_ligero and entrada.has("modelo_vita") and ResourceLoader.exists(entrada.modelo_vita):
			ruta = entrada.modelo_vita
		var recurso = load(ruta) if dibujar else null
		if dibujar and recurso == null:
			push_warning("Asset ausente: " + ruta)
			continue
		var n: Node3D
		if not dibujar:
			n = Node3D.new()   # solo sostiene la colisión
		elif recurso is PackedScene:
			n = recurso.instantiate()
		else:
			var instancia := MeshInstance3D.new()
			instancia.mesh = recurso
			n = instancia
		n.name = entrada.get("nombre", entrada.modelo.get_file().get_basename())
		var p: Array = entrada.pos
		n.position = Util.vector_godot(Vector3(p[0], p[1], p[2]))
		n.rotation.y = entrada.get("yaw", 0.0)
		var e = entrada.get("escala", 1.0)
		n.scale = Vector3.ONE * e if e is float or e is int else Util.vector_godot(Vector3(e[0], e[1], e[2])).abs()
		add_child(n)
		if perfil_ligero and dibujar:
			var radio := 1.0
			if n is MeshInstance3D and n.mesh != null:
				radio = n.mesh.get_aabb().size.length() * 0.5 * maxf(n.scale.x, maxf(n.scale.y, n.scale.z))
			_assets_visibles.append({"nodo": n, "radio": radio})
		if entrada.has("colision"):
			var c: Array = entrada.colision
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(c[1], c[2], c[0])
			shape.shape = box
			if c.size() > 3:
				shape.position = Util.vector_godot(Vector3(c[3], c[4], c[5]))
			body.add_child(shape)
			body.scale = Vector3.ONE / n.scale
			n.add_child(body)
		if entrada.has("movimiento"):
			_agentes.append({"nodo": n, "centro": n.position, "radio": entrada.movimiento[0], "velocidad": entrada.movimiento[1], "fase": entrada.get("fase", 0.0)})


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
		var d := Vector2(nodo.position.x - foco.x, nodo.position.z - foco.z).length_squared()
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
