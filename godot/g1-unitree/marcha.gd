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


## Avanza `dt` segundos. `libre` es un Callable(Vector2) -> bool que dice si el robot cabe en ese punto.
func avanzar(dt: float, libre: Callable) -> void:
	var f0 := f
	f += dt * hz
	mezcla = minf(1.0, mezcla + dt / T_MEZCLA)
	if f >= largo:
		f -= largo
		_mover(f0, largo, libre)
		_mover(0.0, f, libre)
	else:
		_mover(f0, f, libre)


func _mover(fa: float, fb: float, libre: Callable) -> void:
	var a := _muestra(actual, fa)
	var b := _muestra(actual, fb)
	var ya := _yaw(a)
	var d := Vector2(b[0] - a[0], b[1] - a[1]).rotated(-ya)   # avance en el marco del robot
	var paso := d.rotated(yaw)
	var nueva := pos + paso
	bloqueado = false
	if libre.call(nueva):
		pos = nueva
	elif libre.call(pos + Vector2(paso.x, 0)):   # deslizar a lo largo de la pared
		pos += Vector2(paso.x, 0)
		bloqueado = true
	elif libre.call(pos + Vector2(0, paso.y)):
		pos += Vector2(0, paso.y)
		bloqueado = true
	else:
		bloqueado = true
	yaw = wrapf(yaw + wrapf(_yaw(b) - ya, -PI, PI), -PI, PI)


## Pose de la base para urdf_robot.set_base_pose_ros(): posición 3D y cuaternión (ROS).
func pose_base() -> Array:
	var m := _muestra(actual, f)
	var q := Quaternion(m[3], m[4], m[5], m[6]).normalized()
	var inclinacion := Quaternion(Vector3(0, 0, 1), -_yaw(m)) * q   # quitar la guiñada del clip
	return [Vector3(pos.x, pos.y, m[2]), Quaternion(Vector3(0, 0, 1), yaw) * inclinacion]


func q_joints() -> PackedFloat32Array:
	var m := _muestra(actual, f)
	var q := m.slice(7)
	if mezcla < 1.0 and anterior != "":
		var p := _muestra(anterior, f).slice(7)
		for i in q.size():
			q[i] = lerpf(p[i], q[i], mezcla)
	return q


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
