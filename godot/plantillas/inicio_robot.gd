@tool
extends Marker3D
## Dónde y mirando hacia dónde aparece el robot (regla de escenas, doc 35). Sustituye a `spawn_ros` de robot.json:
## muévelo y gíralo (solo en Y) en el editor. La tecla R / el botón △ devuelven el robot aquí.
##
## En el editor muestra el modelo de PC del robot (`visual_pc` de robot.json) como vista previa. Esa vista es un
## hijo sin `owner`: no se guarda en la escena ni existe al ejecutar; el robot de verdad lo crea
## aplicacion_robot.gd con su física, sus sensores y el modelo de su plataforma.

## Mostrar el modelo del robot en el editor.
@export var vista_previa := true:
	set(v):
		vista_previa = v
		_refrescar()


func _ready() -> void:
	_refrescar()


func _refrescar() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var vieja := get_node_or_null("Vista")
	if vieja != null:
		remove_child(vieja)
		vieja.queue_free()
	if not vista_previa:
		return
	var padre := get_parent()
	var ruta: String = padre.get("ruta_config") if padre != null and padre.get("ruta_config") != null else "res://robot.json"
	var config = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	if not config is Dictionary or config.get("visual_pc", "") == "":
		return
	var escena = load(config.visual_pc)
	if escena is PackedScene:
		var vista: Node3D = escena.instantiate()
		vista.name = "Vista"
		add_child(vista)
