extends SceneTree
## Prueba de host de V2 (doc 36 §10; W13 D2 y D11): PrimitivasViz, PaletaViz y TextoSuperpuesto.
## Cada forma: una superficie, solo PRIMITIVE_TRIANGLES, nº de triángulos = tabla D2, el material único de la
## paleta, sin color por vértice ni normales (H1, H3); UV en centros de texel; mallas compartidas por forma;
## ≤ 64 variantes. Paleta: texel 255 con alfa 0 (H8), índices y rampas de mapa. Texto: tope de glifos y descarte
## de lo que queda detrás de la cámara. No mide la Vita: `lit=` = 0 y `drawn` = 80 son el gate E-W8-1 en hardware.
##
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_primitivas.gd

const Prim = preload("res://comun/visor/primitivas_viz.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")
const Texto = preload("res://comun/visor/texto_superpuesto.gd")

var fallos := 0
var pruebas := 0


func check(condicion: bool, nombre: String) -> void:
	pruebas += 1
	if not condicion:
		fallos += 1
		push_error(nombre)
	else:
		print("OK ", nombre)


func _init() -> void:
	_correr.call_deferred()


func _correr() -> void:
	_probar_paleta()
	_probar_formas()
	_probar_variantes()
	_probar_conversiones()
	await _probar_texto()
	await _probar_banco()
	print("RESULTADO: ", pruebas - fallos, "/", pruebas)
	quit(0 if fallos == 0 else 1)


func _probar_paleta() -> void:
	var img := Paleta.imagen()
	check(img.get_width() == 16 and img.get_height() == 16, "paleta: textura 16×16")
	check(img.get_pixel(15, 15).a == 0.0, "paleta: texel 255 con alfa 0 (H8)")
	check(img.detect_alpha() != Image.ALPHA_NONE, "paleta: la imagen se detecta con alfa")
	var bien := true
	for i in 255:
		var u := Paleta.uv(i) * 16.0
		var px := img.get_pixel(int(u.x), int(u.y))
		if px.to_rgba32() != Paleta.color(i).to_rgba32() or absf(u.x - floorf(u.x) - 0.5) > 1e-4:
			bien = false
	check(bien, "paleta: uv(i) cae en el centro del texel de color(i) (RGBA8)")
	bien = true
	for i in 255:
		if not Paleta.color(Paleta.indice(Paleta.color(i))).is_equal_approx(Paleta.color(i)):
			bien = false
	check(bien, "paleta: indice(color(i)) devuelve ese color")
	check(Paleta.indice(Color(0.98, 0.02, 0.01)) != Paleta.TRANSPARENTE, "paleta: indice() nunca da el transparente")
	check(Paleta.indice(Paleta.STALE) == Paleta.I_STALE, "paleta: STALE tiene índice con nombre")
	var de: Color = Paleta.de_ros({"r": 0.5, "g": 0.25, "b": 1.0, "a": 0.5})
	check(de.is_equal_approx(Color(0.5, 0.25, 1.0, 0.5)), "paleta: de_ros(ColorRGBA)")
	check(Paleta.material() == Paleta.material(), "paleta: un único material")
	check(Paleta.material().texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "paleta: filtro NEAREST")
	var m := Paleta.rampa_mapa(Paleta.ESQUEMA_MAP)
	check(m.get_width() == 256 and m.get_height() == 1, "rampa map: 256×1")
	check(m.get_pixel(0, 0).is_equal_approx(Color.WHITE) and m.get_pixel(100, 0).is_equal_approx(Color.BLACK),
			"rampa map: 0 blanco, 100 negro")
	check(m.get_pixel(255, 0).to_rgba32() == 0x708986ff, "rampa map: −1 = 0x708986")
	var c := Paleta.rampa_mapa(Paleta.ESQUEMA_COSTMAP)
	check(c.get_pixel(0, 0).a == 0.0 and c.get_pixel(99, 0).is_equal_approx(Color(0, 1, 1)) \
			and c.get_pixel(100, 0).is_equal_approx(Color(1, 0, 1)), "rampa costmap: libre transparente, 99 cian, 100 magenta")
	var r := Paleta.rampa_mapa(Paleta.ESQUEMA_RAW, true, 100)
	check(r.get_pixel(99, 0).r8 == 0 and r.get_pixel(100, 0).r8 == 255, "rampa raw binaria: umbral 100")
	var lut := Paleta.lut16_costmap()
	check(lut.size() == 16 and lut[1].a == 0.0 and lut[0].to_rgba32() == 0x708986ff, "lut16 costmap")


func _probar_formas() -> void:
	Prim.vaciar()
	for f in Prim.FORMAS:
		var m := Prim.malla(f, Paleta.ROJO)
		var nombre := "forma %d" % f
		check(m != null and m.get_surface_count() == 1, nombre + ": una superficie")
		if m == null or m.get_surface_count() != 1:
			continue
		check(m.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES, nombre + ": PRIMITIVE_TRIANGLES (H1)")
		var arr := m.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		check(arr[Mesh.ARRAY_INDEX] == null and v.size() == 3 * int(Prim.TRIANGULOS[f]),
				nombre + ": %d triángulos (tabla D2), sin índices" % Prim.TRIANGULOS[f])
		check(arr[Mesh.ARRAY_COLOR] == null and arr[Mesh.ARRAY_NORMAL] == null, nombre + ": sin color ni normales (H3)")
		check(m.surface_get_material(0) == Paleta.material(), nombre + ": el material de la paleta")
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var bien := uvs.size() == v.size()
		var esperado := [Paleta.ROJO, Paleta.VERDE, Paleta.AZUL] if f == Prim.EJES else [Paleta.ROJO]
		for u in uvs:
			var hay := false
			for i in esperado:
				hay = hay or u.is_equal_approx(Paleta.uv(i))
			bien = bien and hay
		check(bien, nombre + ": UV solo en los texels esperados")
		check(Prim.malla(f, Paleta.ROJO) == m, nombre + ": malla compartida (caché)")
		var a := Prim.instancia(f, Paleta.color(Paleta.ROJO))
		var b := Prim.instancia(f, Paleta.color(Paleta.ROJO))
		check(a.mesh == m and b.mesh == m, nombre + ": dos instancias, la misma malla")
		a.free()
		b.free()
	# Geometría que importa a los displays: la flecha apunta a −Z (ROS +X) y mide 1; el cono tiene su vértice en 0.
	var aabb := Prim.malla(Prim.FLECHA).get_aabb()
	check(is_equal_approx(aabb.position.z, -1.0) and is_equal_approx(aabb.end.z, 0.0), "flecha: largo 1 sobre −Z")
	aabb = Prim.malla(Prim.CONO).get_aabb()
	check(is_equal_approx(aabb.position.z, -1.0) and is_equal_approx(aabb.end.z, 0.0), "cono: de 0 a −1 en Z")
	aabb = Prim.malla(Prim.CILINDRO).get_aabb()
	check(aabb.size.is_equal_approx(Vector3(1, 1, 1)), "cilindro: unidad, eje +Y")
	aabb = Prim.malla(Prim.DISCO).get_aabb()
	check(is_zero_approx(aabb.size.y) and is_equal_approx(aabb.size.x, 1.0), "disco: plano XZ de Godot (XY de ROS)")
	check(Prim.malla(Prim.EJES, Paleta.AMARILLO) == Prim.malla(Prim.EJES, Paleta.ROJO), "ejes: una sola variante")
	check(Prim.malla(99, 0) == null, "forma desconocida: null")


func _probar_variantes() -> void:
	Prim.vaciar()
	for f in Prim.FORMAS:
		for i in range(16, 40):                # 8 × 24 colores = 192 peticiones (EJES cuenta una)
			Prim.malla(f, i)
	check(Prim.variantes() <= Prim.MAX_VARIANTES, "variantes: %d ≤ %d" % [Prim.variantes(), Prim.MAX_VARIANTES])
	var b := Prim.malla(Prim.CUBO, 200)        # caché llena: devuelve el blanco
	check(b == Prim.malla(Prim.CUBO, Paleta.BLANCO), "variantes: con la caché llena se reutiliza el blanco")
	for f in Prim.FORMAS:
		Prim.malla(f, Paleta.BLANCO)
	check(Prim.variantes() <= Prim.MAX_VARIANTES, "variantes: con los blancos sigue ≤ 64")
	var c := Prim.cinta(PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 0, -1)]), 0.1, Paleta.PATH_RVIZ)
	var n := c.surface_get_array_len(0) / 3
	check(n == 4 and c.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES, "cinta: 2 triángulos por segmento")
	check(Prim.cinta(PackedVector3Array([Vector3.ZERO]), 0.1).get_surface_count() == 0, "cinta: < 2 puntos, vacía")
	Prim.vaciar()


func _probar_conversiones() -> void:
	var t := Prim.pose_godot({"position": {"x": 1.0, "y": 2.0, "z": 3.0},
			"orientation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 0.0}})
	check(t.origin.is_equal_approx(Vector3(-2, 3, -1)), "pose_godot: (1,2,3) ROS → (−2,3,−1) Godot")
	check(t.basis.is_equal_approx(Basis.IDENTITY), "pose_godot: cuaternión nulo → identidad (T14)")
	var yaw := Quaternion(Vector3(0, 0, 1), PI / 2)          # 90° en ROS: X ROS → Y ROS
	t = Prim.pose_godot({"position": {"x": 0.0, "y": 0.0, "z": 0.0},
			"orientation": {"x": yaw.x, "y": yaw.y, "z": yaw.z, "w": yaw.w}})
	check((t.basis * Vector3(0, 0, -1)).is_equal_approx(Prim.C * Vector3(0, 1, 0)), "pose_godot: yaw 90° gira la flecha")
	check(Prim.flecha_hacia(Vector3.ZERO) == null, "flecha_hacia: vector nulo → null (T13)")
	for v in [Vector3(1, 2, -3), Vector3(0, 5, 0), Vector3(0, -2, 0)]:
		var f: Transform3D = Prim.flecha_hacia(v)
		check((f.basis * Vector3(0, 0, -1)).is_equal_approx(v), "flecha_hacia %s: punta en v" % v)
	check(Prim.escala_ros({"x": 1.0, "y": 2.0, "z": -3.0}) == Vector3(2, 3, 1), "escala_ros: (x,y,z) → (y,z,x)")
	var cov := Basis(Vector3(1, 0, 0), Vector3(0, 4, 0), Vector3(0, 0, 9))   # varianzas x=1, y=4, z=9 (ROS)
	var g := Prim.a_godot(cov)
	check(is_equal_approx(g.z.z, 1.0) and is_equal_approx(g.x.x, 4.0) and is_equal_approx(g.y.y, 9.0),
			"a_godot: C·B·Cᵀ lleva las varianzas a sus ejes Godot")
	check(absf(Prim.grosor_minimo(3.0) - 0.0086) < 1e-3, "grosor mínimo a 3 m ≈ 9 mm")


func _probar_texto() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var tx: Control = Texto.new()
	tx.camara = cam
	root.add_child(tx)
	check(tx.mouse_filter == Control.MOUSE_FILTER_IGNORE, "texto: no captura la entrada")
	tx.max_glifos = Texto.MAX_GLIFOS_VITA                     # simula la Vita
	tx.poner("a", Vector3(0, 0, -5), "base_link")             # 9 glifos, delante
	tx.poner("b", Vector3(0, 0, 5), "detras")                 # detrás de la cámara (mira a −Z)
	for i in 5:
		tx.poner("c%d" % i, Vector3(i, 0, -5), "marco_%d" % i)   # 7 glifos cada uno
	var p: Array = tx.preparar()
	var glifos := 0
	for e in p:
		glifos += String(e[1]).length()
		check(e[1] != "detras", "texto: lo de detrás de la cámara no se pinta")
	check(glifos <= Texto.MAX_GLIFOS_VITA and p.size() == 5, "texto: tope de 40 glifos en la Vita (%d)" % glifos)
	tx.max_glifos = 0
	if not OS.has_feature("vita"):
		check(tx.preparar().size() == 6, "texto: sin tope en el PC")
	tx.quitar("a")
	check(tx.cuantos() == 6, "texto: quitar()")
	await process_frame
	await process_frame
	tx.queue_free()
	cam.queue_free()


## Banco del gate E-W8-1 (godot/visor-ros/banco_primitivas.gd; revisión V1): 80 instancias, todas delante de la
## cámara de main.tscn y dentro de la pantalla, sin pasar de 64 variantes. Solo si el proyecto lo trae.
func _probar_banco() -> void:
	if not ResourceLoader.exists("res://banco_primitivas.gd"):
		return
	Prim.vaciar()
	var cam := Camera3D.new()
	cam.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0.70710677, -0.70710677),
			Vector3(0, 0.70710677, 0.70710677)), Vector3(0, 6, 6))           # la Camara de visor-ros/main.tscn
	root.add_child(cam)
	cam.current = true
	var banco: Node3D = load("res://banco_primitivas.gd").new()
	root.add_child(banco)
	check(not banco.visible and banco.creadas == 0, "banco: apagado al arrancar (la .vpk mide G-W13-H0 sin él)")
	var ev := InputEventKey.new()
	ev.keycode = KEY_B
	ev.pressed = true
	banco._unhandled_input(ev)
	await process_frame
	var mallas := banco.find_children("*", "MeshInstance3D", false, false)
	check(banco.visible and mallas.size() == 80, "banco: 80 instancias al encenderlo (%d)" % mallas.size())
	check(Prim.variantes() <= Prim.MAX_VARIANTES, "banco: %d variantes ≤ 64" % Prim.variantes())
	var fuera := 0
	for m in mallas:
		if not cam.is_position_in_frustum((m as Node3D).global_position):
			fuera += 1
	check(fuera == 0, "banco: las 80 delante de la cámara y en pantalla (fuera %d)" % fuera)
	banco.queue_free()
	cam.queue_free()
	Prim.vaciar()
