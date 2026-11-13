extends SceneTree
## Pruebas del perfil «Vita ligero» (sin red):
##   $GH --headless --path godot/g1-sensores --script res://comun/pruebas/perfil_ligero.gd -- sin_ros lod=vita
## Comprueba que el perfil cambia lo que se dibuja y NO lo que choca, que las cajas fundidas miran hacia fuera
## y, en g1-sensores, que la marcha sin arrays nuevos da los mismos números que la de antes (salvo redondeo).

var fallos := 0
var pruebas := 0


func check(condicion: bool, nombre: String) -> void:
	pruebas += 1
	if not condicion:
		fallos += 1
		push_error("FALLO " + nombre)
		print("FALLO ", nombre)
	else:
		print("OK ", nombre)


func _init() -> void:
	_probar.call_deferred()


func _probar() -> void:
	var MundoBase = load("res://comun/mundo/mundo_base.gd")
	var completo: Node3D = MundoBase.new()
	var ligero: Node3D = MundoBase.new()
	ligero.perfil_ligero = true
	root.add_child(completo)
	root.add_child(ligero)
	await process_frame
	var a: Dictionary = completo.contar_dibujado()
	ligero.radio_visible = 0.0   # sin límite: se compara el mundo entero
	ligero.enfocar(Vector3.ZERO)
	var b: Dictionary = ligero.contar_dibujado()
	print("MUNDO completo ", a, "  ligero (sin radio) ", b)
	check(b.triangulos < a.triangulos * 6 / 10, "el mundo ligero entero tiene menos del 60 por ciento de los triángulos (%d de %d)" % [b.triangulos, a.triangulos])
	check(b.superficies < a.superficies * 3 / 4, "el mundo ligero entero tiene menos del 75 por ciento de las superficies (%d de %d)" % [b.superficies, a.superficies])
	check(_cuerpos(completo) == _cuerpos(ligero), "mismas colisiones en los dos perfiles (%d)" % _cuerpos(ligero))
	check(_cajas_colision(completo) == _cajas_colision(ligero), "mismas cajas de colisión (posición y tamaño)")
	_probar_orientacion(ligero)
	# Visibilidad por distancia, con histéresis.
	ligero.radio_visible = 14.0
	var n_casa: int = ligero.enfocar(Vector3(-17.0, 0.0, -9.0))    # spawn del G1: ROS (9, −17) → Godot (−17, ·, −9)
	var c: Dictionary = ligero.contar_dibujado()
	var n_lejos: int = ligero.enfocar(Vector3(200.0, 0.0, 200.0))
	check(n_casa > 5 and n_casa < 30, "desde la casa se dibujan solo los assets cercanos (%d)" % n_casa)
	check(c.triangulos < 6000, "mundo visible desde el spawn < 6 000 triángulos (%d)" % c.triangulos)
	check(n_lejos == 0, "lejos de todo no se dibuja ningún asset")
	completo.queue_free()
	ligero.queue_free()
	if ResourceLoader.exists("res://marcha.gd"):
		_probar_marcha()
	_probar_perfil()
	print("RESULTADO: ", pruebas - fallos, "/", pruebas)
	quit(0 if fallos == 0 else 1)


func _cuerpos(n: Node) -> int:
	var t := 1 if n is StaticBody3D else 0
	for h in n.get_children():
		t += _cuerpos(h)
	return t


## Lista ordenada de «posición global | tamaño global» de todas las cajas de colisión.
func _cajas_colision(n: Node, r: Array = []) -> Array:
	if n is CollisionShape3D and n.shape is BoxShape3D:
		var g: Transform3D = n.global_transform
		var tam: Vector3 = (g.basis.get_scale() * n.shape.size).abs()
		r.append("%s|%s" % [g.origin.snapped(Vector3.ONE * 0.001), tam.snapped(Vector3.ONE * 0.001)])
	for h in n.get_children():
		_cajas_colision(h, r)
	if n.get_parent() == root:
		r.sort()
	return r


## Las caras de las cajas fundidas deben tener el mismo sentido de giro que las de BoxMesh (si no, la Vita las
## descartaría por la cara trasera) y su normal debe apuntar hacia fuera.
func _probar_orientacion(mundo: Node3D) -> void:
	var caja := BoxMesh.new()
	var ref: Array = caja.surface_get_arrays(0)
	var signo_ref := _signo(ref[Mesh.ARRAY_VERTEX], ref[Mesh.ARRAY_NORMAL], ref[Mesh.ARRAY_INDEX])
	var revisadas := 0
	var iguales := true
	for h in mundo.get_children():
		if h is MeshInstance3D and String(h.name).begins_with("Cajas"):
			var arr: Array = h.mesh.surface_get_arrays(0)
			var indices = arr[Mesh.ARRAY_INDEX]
			if indices == null:
				indices = PackedInt32Array()
			if _signo(arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_NORMAL], indices) != signo_ref:
				iguales = false
			revisadas += 1
	check(revisadas >= 8 and revisadas <= 14, "cajas fundidas por color: %d mallas (antes 28)" % revisadas)
	check(iguales and signo_ref != 0, "las cajas fundidas giran como BoxMesh (signo %d)" % signo_ref)


## +1 si en todos los triángulos (b−a)×(c−a) va con la normal, −1 si va contra ella, 0 si hay mezcla.
func _signo(v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array) -> int:
	var mas := 0
	var menos := 0
	var total := (idx.size() if idx.size() > 0 else v.size()) / 3
	for t in total:
		var i0 := idx[t * 3] if idx.size() > 0 else t * 3
		var i1 := idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1
		var i2 := idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2
		if (v[i1] - v[i0]).cross(v[i2] - v[i0]).dot(n[i0]) > 0.0:
			mas += 1
		else:
			menos += 1
	return 1 if menos == 0 else (-1 if mas == 0 else 0)


## La marcha optimizada (búferes reutilizados) frente a la referencia hecha con `_muestra()` (un array por
## llamada, como antes): mismas juntas, misma pose y mismo desplazamiento (salvo redondeo), incluida la mezcla de clips.
func _probar_marcha() -> void:
	var Marcha = load("res://marcha.gd")
	var m = Marcha.new()
	check(m.cargar("res://anim/g1_marcha.json"), "marcha: carga los clips")
	var pos := Vector2.ZERO
	var yaw := 0.0
	var iguales_q := true
	var iguales_pose := true
	var max_err_q := 0.0
	var max_err_mov := 0.0
	var plan := ["andar", "andar", "girar_izq", "correr", "quieto", "atras", "derecha", "andar"]
	var dt := 1.0 / 30.0
	for paso in 400:
		if paso % 50 == 0:
			m.pedir(plan[int(paso / 50) % plan.size()])
		var f0: float = m.f
		m.avanzar(dt, Callable())
		# Referencia del desplazamiento (el algoritmo de antes).
		var tramos := [[f0, m.f]] if m.f >= f0 else [[f0, m.largo], [0.0, m.f]]
		for tr in tramos:
			var a: PackedFloat32Array = m._muestra(m.actual, tr[0])
			var b: PackedFloat32Array = m._muestra(m.actual, tr[1])
			var ya: float = Marcha._yaw(a)
			pos += Vector2(b[0] - a[0], b[1] - a[1]).rotated(-ya).rotated(yaw)
			yaw = wrapf(yaw + wrapf(Marcha._yaw(b) - ya, -PI, PI), -PI, PI)
		max_err_mov = maxf(max_err_mov, maxf((pos - m.pos).length(), absf(wrapf(yaw - m.yaw, -PI, PI))))
		# Referencia de juntas y pose.
		var ref: PackedFloat32Array = m._muestra(m.actual, m.f)
		var q_ref: PackedFloat32Array = ref.slice(7)
		if m.mezcla < 1.0 and m.anterior != "":
			var p: PackedFloat32Array = m._muestra(m.anterior, m.f).slice(7)
			for i in q_ref.size():
				q_ref[i] = lerpf(p[i], q_ref[i], m.mezcla)
		var q: PackedFloat32Array = m.q_joints()
		if q.size() != q_ref.size():
			iguales_q = false
		else:
			for i in q.size():
				max_err_q = maxf(max_err_q, absf(q[i] - q_ref[i]))
		var pose: Array = m.pose_base()
		if pose[0].z != ref[2]:
			iguales_pose = false
	# La referencia guarda los pasos intermedios en float32 y la versión nueva los calcula en doble precisión:
	# difieren en el último bit, no más.
	check(iguales_q and max_err_q < 1e-5, "marcha: q_joints() igual a la referencia en 400 ticks con cambios de clip (error máx. %.9f rad)" % max_err_q)
	check(iguales_pose, "marcha: altura de pose_base() idéntica a la referencia")
	check(max_err_mov < 1e-4, "marcha: desplazamiento (pos, yaw) igual a la referencia tras 400 ticks (error máx. %.9f)" % max_err_mov)
	check(m.pos.length() > 1.0, "marcha: el robot se ha desplazado (%.2f m)" % m.pos.length())
	# Con función de colisión que lo bloquea todo, no se mueve y lo dice.
	var antes: Vector2 = m.pos
	m.pedir("andar")
	m.avanzar(dt, func(_p): return false)
	check(m.pos == antes and m.bloqueado, "marcha: una función `libre` que niega bloquea el paso")


func _probar_perfil() -> void:
	var Perfil = load("res://comun/ros/perfil.gd")
	var antes: bool = Perfil.activo
	Perfil.volcar(1)
	var t: int = Perfil.t0()
	Perfil.sumar("prueba", t)
	Perfil.sumar("prueba", t)
	var foto: Dictionary = Perfil.instantanea()
	check(foto.has("prueba") and foto["prueba"][1] == 2, "perfil: acumula por sección")
	var linea: String = Perfil.volcar(2, "triangulos=1")
	check(linea.begins_with("[perfil-gd] fotogramas=2 prueba=") and linea.ends_with("triangulos=1"), "perfil: formato de la línea")
	check(Perfil.instantanea().is_empty(), "perfil: volcar() pone a cero")
	Perfil.activo = antes
