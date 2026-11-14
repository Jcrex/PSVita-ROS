extends RefCounted
## Reproductor de los clips de desplazamiento del G1 (anim/g1_marcha.json).
##
## Los clips salen de la política de marcha OFICIAL de Unitree (unitree_rl_gym, motion.pt) corriendo en
## MuJoCo: `docker/g1/g1_sim.py --grabar`. Cada clip = 2 ciclos de marcha (1,6 s) a 50 Hz, todos empiezan en
## la fase 0, así que se puede pasar de uno a otro en el mismo índice de fotograma mezclando 0,25 s.
## Fotograma = [x, y, z, qx, qy, qz, qw, q0..q11] en ejes de ROS, pose relativa al inicio del clip.
## El desplazamiento se integra por incrementos («root motion»): el robot avanza en el mundo lo mismo que
## avanzó en la simulación, y una función de colisión puede bloquearlo (paredes de la casa).

const T_MEZCLA := 0.25

var hz := 50.0
var joints := PackedStringArray()
var clips := {}             # nombre -> Array[PackedFloat32Array]
var actual := "quieto"
var anterior := ""
var mezcla := 1.0           # 0 → pose del clip anterior, 1 → pose del actual
var f := 0.0                # fotograma actual (float) dentro del ciclo [0, largo)
var largo := 80.0           # fotogramas de un bucle (el último ≈ el primero)
var pos := Vector2.ZERO     # posición en el mundo (ROS, m)
var yaw := 0.0              # guiñada en el mundo (rad)
var bloqueado := false

# Perfil «Vita ligero» (2026-11-13): nada de arrays nuevos por tick. Antes cada tick hacía 4–5 `_muestra()` (un
# PackedFloat32Array de 19 valores cada una) más dos `slice()`; ahora se interpola una sola vez por (clip, fotograma)
# sobre estos búferes y el desplazamiento solo interpola x, y y el cuaternión.
var _m := PackedFloat32Array()        # muestra completa de (actual, f)
var _m_clip := ""
var _m_f := -1.0
var _q := PackedFloat32Array()        # juntas que devuelve q_joints() (búfer reutilizado)
var _fin_clip := ""                   # (clip, fotograma) → Vector3(x, y, yaw) del final del último tramo
var _fin_f := -1.0
var _fin := Vector3.ZERO


func cargar(ruta: String) -> bool:
	var fa := FileAccess.open(ruta, FileAccess.READ)
	if fa == null:
		return false
	var d = JSON.parse_string(fa.get_as_text())
	if not d is Dictionary:
		return false
	hz = d.get("hz", 50)
	joints = PackedStringArray(d["joints"])
	for nombre in d["clips"]:
		var fr: Array = []
		for v in d["clips"][nombre]["frames"]:
			fr.append(PackedFloat32Array(v))
		clips[nombre] = fr
		largo = fr.size() - 1
	return clips.has("quieto")


func pedir(clip: String) -> void:
	if clip == actual or not clips.has(clip):
		return
	anterior = actual
	actual = clip
	mezcla = 0.0


## Avanza `dt` segundos. `libre` es un Callable(Vector2) -> bool que dice si el robot cabe en ese punto; con un
## Callable vacío (`Callable()`) no se pregunta (la colisión la hace otro, p. ej. `move_and_slide`).
func avanzar(dt: float, libre: Callable) -> void:
	var f0 := f
	f += dt * hz
	mezcla = minf(1.0, mezcla + dt / T_MEZCLA)
	if f >= largo:
		f = fmod(f, largo)   # un tirón de varios ciclos (fotograma muy lento) no deja f fuera del clip
		_mover(f0, largo, libre)
		_mover(0.0, f, libre)
	else:
		_mover(f0, f, libre)


func _mover(fa: float, fb: float, libre: Callable) -> void:
	var a := _xy_yaw(actual, fa)
	var b := _xy_yaw(actual, fb)
	_fin_clip = actual
	_fin_f = fb
	_fin = b
	var d := Vector2(b.x - a.x, b.y - a.y).rotated(-a.z)   # avance en el marco del robot
	var paso := d.rotated(yaw)
	var nueva := pos + paso
	bloqueado = false
	if not libre.is_valid() or libre.call(nueva):
		pos = nueva
	elif libre.call(pos + Vector2(paso.x, 0)):   # deslizar a lo largo de la pared
		pos += Vector2(paso.x, 0)
		bloqueado = true
	elif libre.call(pos + Vector2(0, paso.y)):
		pos += Vector2(0, paso.y)
		bloqueado = true
	else:
		bloqueado = true
	yaw = wrapf(yaw + wrapf(b.z - a.z, -PI, PI), -PI, PI)


## Pose de la base para urdf_robot.set_base_pose_ros(): posición 3D y cuaternión (ROS).
func pose_base() -> Array:
	_actualizar_muestra()
	var m := _m
	var q := Quaternion(m[3], m[4], m[5], m[6]).normalized()
	var inclinacion := Quaternion(Vector3(0, 0, 1), -_yaw(m)) * q   # quitar la guiñada del clip
	return [Vector3(pos.x, pos.y, m[2]), Quaternion(Vector3(0, 0, 1), yaw) * inclinacion]


## Juntas de las piernas en el orden de `joints`. OJO: devuelve un búfer que se reutiliza en la siguiente llamada;
## quien quiera conservarlo debe copiarlo (`duplicate()`).
func q_joints() -> PackedFloat32Array:
	_actualizar_muestra()
	var n := _m.size() - 7
	if _q.size() != n:
		_q.resize(n)
	if mezcla < 1.0 and anterior != "":
		# Mezcla con el clip anterior en el mismo fotograma, interpolando en línea (sin arrays intermedios).
		var fr: Array = clips[anterior]
		var i := int(f)
		var j := mini(i + 1, fr.size() - 1)
		var t := f - i
		var a: PackedFloat32Array = fr[i]
		var b: PackedFloat32Array = fr[j]
		for k in n:
			_q[k] = lerpf(lerpf(a[k + 7], b[k + 7], t), _m[k + 7], mezcla)
	else:
		for k in n:
			_q[k] = _m[k + 7]
	return _q


## Interpola la muestra completa de (actual, f) en `_m` solo si cambió el clip o el fotograma.
func _actualizar_muestra() -> void:
	if _m_clip == actual and _m_f == f:
		return
	var fr: Array = clips[actual]
	var i := int(f)
	var j := mini(i + 1, fr.size() - 1)
	var t := f - i
	var a: PackedFloat32Array = fr[i]
	var b: PackedFloat32Array = fr[j]
	var n := a.size()
	if _m.size() != n:
		_m.resize(n)
	for k in n:
		_m[k] = lerpf(a[k], b[k], t)
	_m_clip = actual
	_m_f = f


## (x, y, yaw) de la base en el fotograma `x` del clip: lo único que necesita el desplazamiento. El final de un
## tramo es el principio del siguiente, así que se guarda y casi siempre solo se interpola un extremo por tick.
func _xy_yaw(clip: String, x: float) -> Vector3:
	if clip == _fin_clip and x == _fin_f:
		return _fin
	var fr: Array = clips[clip]
	var i := int(x)
	var j := mini(i + 1, fr.size() - 1)
	var t := x - i
	var a: PackedFloat32Array = fr[i]
	var b: PackedFloat32Array = fr[j]
	var qx := lerpf(a[3], b[3], t)
	var qy := lerpf(a[4], b[4], t)
	var qz := lerpf(a[5], b[5], t)
	var qw := lerpf(a[6], b[6], t)
	return Vector3(lerpf(a[0], b[0], t), lerpf(a[1], b[1], t),
			atan2(2.0 * (qw * qz + qx * qy), 1.0 - 2.0 * (qy * qy + qz * qz)))


## Muestra interpolada en un array NUEVO (API antigua; se conserva para pruebas y herramientas, no se usa por tick).
func _muestra(clip: String, x: float) -> PackedFloat32Array:
	var fr: Array = clips[clip]
	var i := int(x)
	var j := mini(i + 1, fr.size() - 1)
	var t := x - i
	var a: PackedFloat32Array = fr[i]
	var b: PackedFloat32Array = fr[j]
	var r := PackedFloat32Array()
	r.resize(a.size())
	for k in a.size():
		r[k] = lerpf(a[k], b[k], t)
	return r


static func _yaw(m: PackedFloat32Array) -> float:
	var x := m[3]; var y := m[4]; var z := m[5]; var w := m[6]
	return atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))
