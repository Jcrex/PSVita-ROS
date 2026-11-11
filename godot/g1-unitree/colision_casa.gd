extends RefCounted
## Colisión 2D del G1 con la casa (modo «marcha» local, sin física): el robot es un círculo en el plano del
## suelo y cada muro o mueble una caja girada. Las cajas se leen de la propia escena casa/casa.tscn
## (generada por docker/g1/casa.py desde casa.json), así que coinciden con las colisiones de MuJoCo.
## En el modo «ros» no hace falta: la física de MuJoCo ya choca con la misma casa.

const RADIO := 0.25          # m, medio ancho de hombros del G1 aprox.
const ALTURA_MAX := 0.3      # cajas que empiezan más arriba (la tele) no bloquean

var _cajas: Array = []       # [centro: Vector2, medio: Vector2, cos, sin]


func cargar(casa: Node3D) -> void:
	_cajas.clear()
	for grupo in ["RosFrame/Muros", "RosFrame/Muebles"]:
		var g := casa.get_node_or_null(grupo)
		if g == null:
			continue
		for n in g.get_children():
			if not (n is MeshInstance3D and n.mesh is BoxMesh):
				continue
			var t: Transform3D = n.transform
			var s: Vector3 = n.mesh.size
			if t.origin.z - s.z / 2 > ALTURA_MAX:
				continue
			var ang := atan2(t.basis.x.y, t.basis.x.x)
			_cajas.append([Vector2(t.origin.x, t.origin.y), Vector2(s.x, s.y) / 2, cos(ang), sin(ang)])


func libre(p: Vector2) -> bool:
	for c in _cajas:
		var d: Vector2 = p - c[0]
		var lx: float = c[2] * d.x + c[3] * d.y
		var ly: float = -c[3] * d.x + c[2] * d.y
		var m: Vector2 = c[1]
		if absf(lx) < m.x + RADIO and absf(ly) < m.y + RADIO:
			return false
	return true
