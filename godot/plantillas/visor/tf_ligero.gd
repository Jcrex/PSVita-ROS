extends RefCounted
## TfLigero (V9; doc 36 §2.9.6, doc 36a §4.3.4; sentencia W13 D3): subconjunto de `RosTfListener` de rclgd para la
## Vita (y respaldo del host), con la semántica de `modules/tf-tree` (`modules/tf-tree/include/tf_tree.h`):
##   - SIN historial: último valor por marco; `time` y `timeout` se aceptan y se ignoran (como tf-tree).
##   - ≤ MAX_MARCOS (32) marcos contando padres y raíces, como `TF_TREE_MAX_FRAMES`; nombres 1..63 caracteres con
##     una barra inicial opcional («/odom» == «odom»).
##   - `poner(padre, hijo, t)` guarda la pose del hijo EN el padre; rechaza ciclos (padre descendiente del hijo o
##     padre == hijo) y marcos nuevos con el árbol lleno, sin tocar nada.
##   - `lookup_transform(destino, origen)` = M tal que p_destino = M · p_origen (tf2 lookupTransform), en EJES DE
##     GODOT como el `RosTfListener` de rclgd (`class_rostflistener.rst`: «already converted to the Godot axis
##     convention»); `null` si no se puede, con el motivo en `get_last_error()`.
## Misma API que usan los displays: `lookup_transform`, `can_transform`, `frame_exists`, `get_frame_names`,
## `get_frame_parent`, `get_last_error`, `clear`. Sin `class_name` (D15) y sin anotar donde se usa (T7).
##
## Fuentes (0 B extra por defecto, D3):
##   1. por nodo: los links del robot horneado (`registrar_robot`, ADR 0009), movidos por `/vita/joints`;
##   2. por valor: `<p>/pose2d` (`desde_pose2d`: mundo → base), los estáticos de la escena (`VisorRos.tf_estaticos`)
##      y, opcional, el módulo `tf` del relay (`on_tf_marcos`, `on_tf_compacto`, `on_tf_estatico`; VC/1 rev. 2).
##   3. pruebas de host: `poner_ros` y `aplicar_tf_message` (un `tf2_msgs/TFMessage` entero, como
##      `tf_tree_apply_message`). En la Vita NO se suscribe a `/tf` crudo (no cabe: G1 ≈ 4 796 B, docs/27:73-75).

const VC1 = preload("res://comun/ros/vc1.gd")

const MAX_MARCOS := 32                          # = TF_TREE_MAX_FRAMES
const MAX_NOMBRE := 63                          # = TF_TREE_NAME_MAX − 1
const RESERVA_VALOR := 8                        # huecos que `registrar_robot` deja libres para pose2d y el relay
## Códigos de `poner` (= tf_tree_status).
const OK_TF := 0
const ERR_ARG := -1
const ERR_LLENO := -2
const ERR_CICLO := -3
const ERR_DESCONOCIDO := -4
const ERR_SIN_CAMINO := -5
## Columnas = ejes X, Y, Z de ROS en Godot (= PrimitivasViz.C y `ros/util_ros.gd:6`). Sin depender de `rclgd`.
const C := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))

var version := 0                                # sube con cada `poner` aceptado (los displays lo miran)
var _padre := {}                                # marco -> padre ("" = raíz). TODOS los marcos conocidos.
var _local := {}                                # hijo -> Transform3D (Godot) del hijo en el padre (fuente por valor)
var _nodo := {}                                 # hijo -> [Node3D raíz del robot, Node3D link] (fuente por nodo)
var _orden_relay := PackedStringArray()         # índice -> «padre>hijo» (de <p>/tf_marcos)
var _estatico_pendiente = null                  # último <p>/tf_estatico (latched): se reaplica si llega tf_marcos después
var _rechazados := 0
var _error := ""


# ---------------------------------------------------------------------------------------------------------------
# Escritura
# ---------------------------------------------------------------------------------------------------------------

## «/odom» → «odom»; "" si el nombre no vale (vacío, solo «/» o > 63 caracteres).
static func normalizar(f: String) -> String:
	var n := f.trim_prefix("/") if f.begins_with("/") else f
	if n.is_empty() or n.length() > MAX_NOMBRE:
		return ""
	return n


## Pose de `hijo` en `padre` (Transform3D en ejes de Godot). Devuelve OK_TF o un ERR_* (sin modificar nada).
func poner(padre: String, hijo: String, t_local: Transform3D) -> int:
	var p := normalizar(padre)
	var h := normalizar(hijo)
	if p == "" or h == "":
		_error = "TfLigero: nombre de marco no válido («%s» → «%s»)" % [padre, hijo]
		return ERR_ARG
	if p == h or _es_ancestro(h, p):
		_error = "TfLigero: ciclo %s → %s" % [p, h]
		return ERR_CICLO
	var nuevos := (0 if _padre.has(p) else 1) + (0 if _padre.has(h) else 1)
	if _padre.size() + nuevos > MAX_MARCOS:
		_error = "TfLigero: más de %d marcos" % MAX_MARCOS
		return ERR_LLENO
	if not _padre.has(p):
		_padre[p] = ""
	_padre[h] = p
	_local[h] = t_local
	_nodo.erase(h)
	version += 1
	return OK_TF


## Lo mismo con traslación y cuaternión en ejes de ROS (TransformStamped). El cuaternión se normaliza; norma ≈ 0 →
## identidad (como tf_tree_update). Valores no finitos: ERR_ARG (T2).
func poner_ros(padre: String, hijo: String, pos: Vector3, q: Quaternion) -> int:
	if not (pos.is_finite() and is_finite(q.x) and is_finite(q.y) and is_finite(q.z) and is_finite(q.w)):
		_error = "TfLigero: transformada no finita %s → %s" % [padre, hijo]
		return ERR_ARG
	return poner(padre, hijo, desde_ros(pos, q))


## (traslación, cuaternión) en ejes de ROS → Transform3D en ejes de Godot: C · [R | t] · Cᵀ.
static func desde_ros(pos: Vector3, q: Quaternion) -> Transform3D:
	var qn := q.normalized() if q.length_squared() > 1e-12 else Quaternion.IDENTITY
	return Transform3D(C * Basis(qn) * C.transposed(), C * pos)


## Inverso de `desde_ros` (para comparar con valores de ROS en las pruebas).
static func a_ros(t: Transform3D) -> Transform3D:
	return Transform3D(C.transposed() * t.basis * C, C.transposed() * t.origin)


## `tf2_msgs/msg/TFMessage` (RosMsg) entero, como `tf_tree_apply_message`: devuelve cuántos se aplicaron; los
## rechazados suman a `rechazados()`.
func aplicar_tf_message(msg) -> int:
	if msg == null:
		return ERR_ARG
	var n := 0
	for ts in msg.transforms:
		var tr = ts.transform
		var rc := poner_ros(String(ts.header.frame_id), String(ts.child_frame_id),
				Vector3(tr.translation.x, tr.translation.y, tr.translation.z),
				Quaternion(tr.rotation.x, tr.rotation.y, tr.rotation.z, tr.rotation.w))
		if rc == OK_TF:
			n += 1
		else:
			_rechazados += 1
	return n


## `/vita/pose2d` = [x, y, yaw, vx, vy, wz] (vita_relay.gd:87-92; no se amplía, D5.4) → `mundo` → `base`.
## Devuelve OK_TF o un ERR_*; NaN/Inf se ignoran (T2).
func desde_pose2d(d, mundo: String, base: String) -> int:
	if d == null or d.size() < 3:
		return ERR_ARG
	var x: float = d[0]
	var y: float = d[1]
	var yaw: float = d[2]
	if not (is_finite(x) and is_finite(y) and is_finite(yaw)):
		return ERR_ARG
	return poner_ros(mundo, base, Vector3(x, y, 0.0), Quaternion(Vector3(0, 0, 1), yaw))


## Fuente por nodo: los links del robot horneado (ADR 0009) bajo `raiz`, que está en el marco `base`. Solo los
## `Node3D` puros (no mallas) sin metadato `urdf_joint` (las juntas no son marcos de TF) y sin los nodos de servicio
## `RosFrame`/`Base` de urdf2godot. Deja RESERVA_VALOR huecos para pose2d y el relay. Devuelve cuántos registró.
func registrar_robot(raiz: Node3D, base: String, tope: int = MAX_MARCOS - RESERVA_VALOR) -> int:
	var b := normalizar(base)
	if raiz == null or b == "":
		return 0
	var n := 0
	for nodo in raiz.find_children("*", "Node3D", true, false):
		if _padre.size() >= tope:
			break
		if nodo.get_class() != "Node3D" or nodo.has_meta("urdf_joint") or nodo.name in ["RosFrame", "Base"]:
			continue
		var f := normalizar(String(nodo.name))
		if f == "" or f == b or _padre.has(f):
			continue
		if not _padre.has(b):
			_padre[b] = ""
		_padre[f] = b
		_nodo[f] = [raiz, nodo]
		n += 1
	if n > 0:
		version += 1
	return n


## Relay opcional `<p>/tf_marcos` (String F+TL «padre>hijo,padre>hijo,…»): orden de los índices de `tf`/`tf_estatico`.
func on_tf_marcos(m) -> void:
	_orden_relay = VC1.leer_tf_marcos(String(m.data))
	if _estatico_pendiente != null:              # los dos son latched y pueden llegar en cualquier orden
		on_tf_compacto(_estatico_pendiente)


## Relay opcional `<p>/tf` (Float32MultiArray, VC/1 rev. 2): [seq, trozo, n_trozos, n, (idx, x, y, z, qx, qy, qz, qw)·n]
## en ejes de ROS. Índices sin `tf_marcos` todavía: se ignoran. Devuelve cuántos se aplicaron.
func on_tf_compacto(m) -> int:
	var n := 0
	for e in VC1.leer_tf(m.data):
		var k: int = e[0]
		if k < 0 or k >= _orden_relay.size():
			continue
		var par := _orden_relay[k].split(">")
		if par.size() != 2:
			continue
		if poner_ros(par[0], par[1], e[1], e[2]) == OK_TF:
			n += 1
		else:
			_rechazados += 1
	return n


## Relay opcional `<p>/tf_estatico` (F+TL, mismo formato que `tf`).
func on_tf_estatico(m) -> int:
	_estatico_pendiente = m
	return on_tf_compacto(m)


## Vacía el árbol (marcos y rechazos), como `tf_tree_clear`.
func clear() -> void:
	_padre.clear()
	_local.clear()
	_nodo.clear()
	_rechazados = 0
	version += 1


# ---------------------------------------------------------------------------------------------------------------
# Consulta (API de RosTfListener)
# ---------------------------------------------------------------------------------------------------------------

func _es_ancestro(posible: String, f: String) -> bool:
	for _i in MAX_MARCOS + 1:
		if not _padre.has(f):
			return false
		f = _padre[f]
		if f == "":
			return false
		if f == posible:
			return true
	return true                                 # cadena más larga que el tope: se trata como ciclo


func _local_de(f: String) -> Transform3D:
	if _nodo.has(f):
		var r = _nodo[f][0]
		var n = _nodo[f][1]
		if is_instance_valid(r) and is_instance_valid(n) and r.is_inside_tree() and n.is_inside_tree():
			# El link cuelga de `RosFrame` (ejes de ROS): su base global ya lleva C; se pasa a la convención de
			# Godot (−Z = +X de ROS) multiplicando por Cᵀ a la derecha.
			return (r.global_transform.affine_inverse() * n.global_transform) * Transform3D(C.transposed(), Vector3.ZERO)
		return Transform3D.IDENTITY
	return _local.get(f, Transform3D.IDENTITY)


## [Transform3D de f en su raíz, nombre de la raíz].
func _a_raiz(f: String) -> Array:
	var t := Transform3D.IDENTITY
	for _i in MAX_MARCOS:
		var p: String = _padre.get(f, "")
		if p == "":
			break
		t = _local_de(f) * t
		f = p
	return [t, f]


func frame_exists(f: String) -> bool:
	return _padre.has(normalizar(f))


func can_transform(destino: String, origen: String, _time = null, _timeout_sec := 0.0) -> bool:
	return _comprobar(normalizar(destino), normalizar(origen)) == OK_TF


func _comprobar(d: String, o: String) -> int:
	if d == "" or o == "":
		_error = "TfLigero: nombre de marco no válido"
		return ERR_ARG
	if not _padre.has(d) or not _padre.has(o):
		_error = "TfLigero: marco desconocido «%s»" % (o if _padre.has(d) else d)
		return ERR_DESCONOCIDO
	if _a_raiz(d)[1] != _a_raiz(o)[1]:
		_error = "TfLigero: %s y %s no están conectados" % [d, o]
		return ERR_SIN_CAMINO
	_error = ""
	return OK_TF


## Transform3D (ejes de Godot) de `origen` en `destino`, o null. Mismo marco → identidad.
func lookup_transform(destino: String, origen: String, _time = null, _timeout_sec := 0.0):
	var d := normalizar(destino)
	var o := normalizar(origen)
	if _comprobar(d, o) != OK_TF:
		return null
	if d == o:
		return Transform3D.IDENTITY
	var a: Array = _a_raiz(o)
	var b: Array = _a_raiz(d)
	return (b[0] as Transform3D).affine_inverse() * (a[0] as Transform3D)


## Código de error del último `lookup` (= tf_tree_lookup): OK_TF, ERR_ARG, ERR_DESCONOCIDO o ERR_SIN_CAMINO.
func estado_lookup(destino: String, origen: String) -> int:
	return _comprobar(normalizar(destino), normalizar(origen))


func get_frame_names() -> PackedStringArray:
	return PackedStringArray(_padre.keys())


func get_frame_parent(f: String) -> String:
	return _padre.get(normalizar(f), "")


func get_last_error() -> String:
	return _error


## Marcos conocidos (= tf_tree_frame_count) y rechazos de `aplicar_tf_message` / relay (= tf_tree_rejected).
func cuantos() -> int:
	return _padre.size()


func rechazados() -> int:
	return _rechazados


## Del relay: índices de `tf_marcos` conocidos (pruebas y HUD).
func orden_relay() -> PackedStringArray:
	return _orden_relay
