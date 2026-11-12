extends Node3D

const Util = preload("res://comun/ros/util_ros.gd")

var _agentes: Array[Dictionary] = []
var _tiempo := 0.0


func _ready() -> void:
	_construir_terreno()
	_construir_casa()
	_cargar_assets()


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


func _caja(nombre: String, pos_ros: Vector3, tam_ros: Vector3, color: Color, solido: bool = true) -> MeshInstance3D:
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
		var recurso = load(entrada.modelo)
		if recurso == null:
			push_warning("Asset ausente: " + entrada.modelo)
			continue
		var n: Node3D
		if recurso is PackedScene:
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
	_tiempo += dt
	for a in _agentes:
		var fase: float = _tiempo * a.velocidad + a.fase
		var delta: Vector3 = Vector3(cos(fase), 0.0, sin(fase)) * a.radio
		a.nodo.position = a.centro + delta
		a.nodo.rotation.y = -fase
