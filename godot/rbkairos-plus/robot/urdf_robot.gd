extends Node3D
## Robot importado desde un URDF con tools/urdf2godot/urdf2godot.py (modo solo visual/cinemático).
##
## Los nodos conservan los nombres del URDF: cada joint es un Node3D con metadata `urdf_*` (tipo, eje,
## origen, límites, mimic). Por eso un /joint_states de ROS se aplica tal cual, por nombre.
## Todo lo que cuelga de `RosFrame` está en ejes de ROS (REP-103, Z arriba); `RosFrame` gira a Godot.
## Sin física: funciona igual en el PC y en la Vita (Jolt está desactivado en el port, detect.py:83).

## Si es true, las posiciones se recortan a los límites del URDF (revolute/prismatic).
@export var respetar_limites := true

var _joints := {}        # nombre URDF -> Node3D del joint
var _base: Node3D

# Perfil «Vita ligero» (2026-11-13): los metadatos del URDF se leen UNA vez en _ready() a arrays paralelos. Antes
# cada junta costaba por tick 6–8 get_meta()/has_meta() + set_meta() + normalized(), y se recalculaba aunque su
# ángulo no hubiera cambiado (en el G1, 17 de las 29 juntas —brazos y cintura— no se mueven al andar).
const _FIJO := 0
const _GIRO := 1
const _PRISMA := 2
var _indice := {}                       # nombre URDF -> índice en los arrays de abajo
var _nodos: Array[Node3D] = []
var _tipos := PackedInt32Array()
var _origenes: Array[Transform3D] = []
var _ejes := PackedVector3Array()
var _inferior := PackedFloat32Array()
var _superior := PackedFloat32Array()
var _con_limites := PackedByteArray()
var _q := PackedFloat32Array()          # último ángulo aplicado
var _aplicado := PackedByteArray()      # 0 hasta la primera vez
var _mimicos: Array = []                # [índice esclavo, índice maestro, k, desfase]
var _nombres_cache := PackedStringArray()   # última lista de nombres vista por set_joints()…
var _indices_cache := PackedInt32Array()    # …y sus índices (−1 = junta desconocida)


func _ready() -> void:
	_base = get_node("RosFrame/Base")
	for n in find_children("*", "Node3D", true, false):
		if n.has_meta("urdf_joint"):
			var nombre: String = n.get_meta("urdf_joint")
			_joints[nombre] = n
			_indice[nombre] = _nodos.size()
			_nodos.append(n)
			var tipo: String = n.get_meta("urdf_type")
			_tipos.append(_GIRO if tipo == "revolute" or tipo == "continuous" else (_PRISMA if tipo == "prismatic" else _FIJO))
			_origenes.append(n.get_meta("urdf_origin") if n.has_meta("urdf_origin") else n.transform)
			_ejes.append((n.get_meta("urdf_axis") as Vector3).normalized() if n.has_meta("urdf_axis") else Vector3.ZERO)
			var limites: bool = n.has_meta("urdf_lower") and n.get_meta("urdf_lower") < n.get_meta("urdf_upper")
			_con_limites.append(1 if limites else 0)
			_inferior.append(n.get_meta("urdf_lower") if limites else 0.0)
			_superior.append(n.get_meta("urdf_upper") if limites else 0.0)
			_q.append(0.0)
			_aplicado.append(0)
	for nombre in _joints:
		var n: Node3D = _joints[nombre]
		if n.has_meta("urdf_mimic") and _indice.has(n.get_meta("urdf_mimic")):
			_mimicos.append([_indice[nombre], _indice[n.get_meta("urdf_mimic")],
				float(n.get_meta("urdf_mimic_k")), float(n.get_meta("urdf_mimic_off"))])


## Nombres de los joints que se pueden mover (no fijos), en el orden del URDF.
func nombres_joints_movibles() -> PackedStringArray:
	var r := PackedStringArray()
	for nombre in _joints:
		var t: String = _joints[nombre].get_meta("urdf_type")
		if t != "fixed" and not _joints[nombre].has_meta("urdf_mimic"):
			r.append(nombre)
	return r


## Pone un joint en la posición `q` (rad para revolute/continuous, m para prismatic).
func set_joint(nombre: String, q: float) -> void:
	var i: int = _indice.get(nombre, -1)
	if i >= 0:
		_aplicar(i, q)


## Aplica un sensor_msgs/JointState (o dos arrays paralelos): nombres -> posiciones.
## Si se llama siempre con la misma lista de nombres (lo normal), los nombres solo se resuelven la primera vez.
func set_joints(nombres, posiciones) -> void:
	var n := mini(nombres.size(), posiciones.size())
	if nombres is PackedStringArray and nombres == _nombres_cache:
		for i in n:
			var k := _indices_cache[i]
			if k >= 0:
				_aplicar(k, posiciones[i])
	else:
		var indices := PackedInt32Array()
		indices.resize(nombres.size())
		for i in nombres.size():
			indices[i] = _indice.get(nombres[i], -1)
		for i in n:
			if indices[i] >= 0:
				_aplicar(indices[i], posiciones[i])
		if nombres is PackedStringArray:
			_nombres_cache = nombres.duplicate()
			_indices_cache = indices
	for m in _mimicos:
		if _aplicado[m[1]] != 0:
			_aplicar(m[0], _q[m[1]] * m[2] + m[3])


## Pose del link raíz en el marco del mundo de ROS (p. ej. odom -> pelvis): posición en m y cuaternión de ROS.
func set_base_pose_ros(posicion: Vector3, orientacion: Quaternion) -> void:
	_base.transform = Transform3D(Basis(orientacion.normalized()), posicion)


## Último ángulo aplicado a una junta (0.0 si aún no se ha movido o no existe).
func posicion_joint(nombre: String) -> float:
	var i: int = _indice.get(nombre, -1)
	return _q[i] if i >= 0 else 0.0


func _aplicar(i: int, q: float) -> void:
	if respetar_limites and _con_limites[i] != 0:
		q = clampf(q, _inferior[i], _superior[i])
	# Sin cambio, sin trabajo: escribir `transform` marca sucio todo el subárbol aunque el valor sea el mismo.
	if _aplicado[i] != 0 and _q[i] == q:
		return
	_q[i] = q
	_aplicado[i] = 1
	match _tipos[i]:
		_GIRO:
			_nodos[i].transform = _origenes[i] * Transform3D(Basis(_ejes[i], q), Vector3.ZERO)
		_PRISMA:
			_nodos[i].transform = _origenes[i] * Transform3D(Basis.IDENTITY, _ejes[i] * q)
