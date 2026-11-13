extends SceneTree
## Presupuesto de render del perfil «Vita ligero» medido en el PC, sin GPU (ADR 0011 §6; doc 34).
##
##   $GH --headless --path godot/g1-sensores --script res://comun/pruebas/presupuesto.gd -- sin_ros lod=vita
##   … -- sin_ros lod=vita mundo=completo      # el mundo de antes, para comparar (no falla por presupuesto)
##
## Lleva el robot a varios puntos del mundo, gira la cámara 8 veces en cada uno y cuenta lo que cae dentro de la
## vista (mundo_base.contar_dibujado con cámara = equivalente de `submitted_triangles`/`visible_instances` de la
## Vita). Imprime una línea por punto con el PEOR de los 8 giros y falla si el perfil ligero supera el presupuesto.
## Límites: "mundo": {"presupuesto": {"triangulos": N, "mallas": N}} en robot.json, o 15 000 y 80 (HMI a 60 FPS).

const PUNTOS := {
	"spawn": null,                       # donde nace el robot
	"casa": Vector3(10.0, -14.0, 0.0),   # ROS (x, y, z)
	"ciudad": Vector3(12.0, 9.0, 0.0),
	"bosque": Vector3(-13.0, 13.0, 0.0),
	"parque": Vector3(-13.0, -13.0, 0.0),
	"centro": Vector3(0.0, 0.0, 0.0),
}

const ASPECTO_VITA := 960.0 / 544.0

var fallos := 0


func _init() -> void:
	_medir.call_deferred()


func _medir() -> void:
	var Util = load("res://comun/ros/util_ros.gd")
	var escena = load("res://main.tscn").instantiate()
	root.add_child(escena)
	await process_frame
	await process_frame
	var robot: CharacterBody3D = escena.robot
	robot.aceptar_teleop_local = false
	robot.set_physics_process(false)   # quieto donde se le ponga
	var presupuesto: Dictionary = escena.config.get("mundo", {}).get("presupuesto", {})
	var max_tris: int = presupuesto.get("triangulos", 15000)
	var max_mallas: int = presupuesto.get("mallas", 80)
	var solo_robot: Dictionary = escena.mundo.contar_dibujado(robot)
	print("PRESUPUESTO perfil_ligero=%s robot: triangulos=%d mallas=%d superficies=%d | limite: %d triangulos, %d mallas" % [
		escena.perfil_ligero, solo_robot.triangulos, solo_robot.mallas, solo_robot.superficies, max_tris, max_mallas])
	# El tronco calculado a mano con el aspecto de la ventana debe dar lo mismo que el de la cámara.
	var vp: Vector2 = Vector2(root.size)
	var c1: Dictionary = escena.mundo.contar_dibujado(escena, escena.camara)
	var c2: Dictionary = escena.mundo.contar_dibujado(escena, escena.camara, vp.x / vp.y)
	if c1 != c2:
		fallos += 1
		print("PRESUPUESTO FALLO: el tronco calculado no coincide con Camera3D.get_frustum(): ", c1, " ", c2)
	var primera: Dictionary = escena.mundo.contar_dibujado(escena, escena.camara, ASPECTO_VITA)
	print("PRESUPUESTO vista inicial (960x544): triangulos=%d mallas=%d superficies=%d" % [
		primera.triangulos, primera.mallas, primera.superficies])
	var altura: float = robot.global_position.y
	for nombre in PUNTOS:
		if PUNTOS[nombre] != null:
			var p: Vector3 = Util.vector_godot(PUNTOS[nombre])
			robot.global_position = Vector3(p.x, altura, p.z)
		var peor := {"triangulos": 0, "mallas": 0, "superficies": 0}
		for giro in 8:
			escena._yaw_cam = giro * TAU / 8.0
			escena._foco_t = 1.0   # que enfoque en este fotograma
			await process_frame
			await process_frame
			var r: Dictionary = escena.mundo.contar_dibujado(escena, escena.camara, ASPECTO_VITA)
			for k in peor:
				peor[k] = maxi(peor[k], r[k])
		var bien: bool = not escena.perfil_ligero or (peor.triangulos <= max_tris and peor.mallas <= max_mallas)
		if not bien:
			fallos += 1
		print("PRESUPUESTO %-7s triangulos=%5d mallas=%3d superficies=%3d %s" % [
			nombre, peor.triangulos, peor.mallas, peor.superficies, "OK" if bien else "FUERA"])
	print("PRESUPUESTO_RESULTADO ", "OK" if fallos == 0 else "FALLO (%d puntos fuera)" % fallos)
	quit(0 if fallos == 0 else 1)
