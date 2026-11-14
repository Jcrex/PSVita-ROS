extends Node
## VisorRos (ADR 0013 §1; doc 36 §2.9.1): contexto único de los displays (≈ rviz_common::DisplayContext).
##
## Vive en el `.tscn` (regla doc 35) y conecta, al arrancar, cada nodo del grupo "display_ros" que cuelga de él:
## les da el nodo ROS (`contexto`), el marco fijo, el TF, el prefijo compacto del relay y los cupos de render.
## El mismo script corre en el PC (rclgd o el editor de host con ros2_vita) y en la PS Vita.
##
## Decisiones de V1 no cubiertas por el ADR 0013 (las más conservadoras; anotadas en visor/README.md):
##   - TF: en V1 no hay `TfLigero` (tarea V9). Si el nodo tiene `create_tf_listener` (rclgd del PC) se usa; si no,
##     `tf` queda en null y `transformada()` supone que todo está ya en el marco fijo (D3).
##     → V9: sin `create_tf_listener`, `tf` es un TfLigero (pose2d, robot horneado, `tf_estaticos` y relay `tf`
##     opcional); mientras no conozca `marco_fijo`, `transformada()` sigue suponiendo el marco fijo.
##     → V13a: ros2_vita ya trae `create_tf_listener` (RosTfListener sobre tf-tree); se usa solo con `tf_nativo`
##     (`usa_tf_nativo()`); los displays no cambian (misma API de consulta).
##   - Transporte: argumento `transporte=` > `@export transporte` > `ros/transport` del proyecto SOLO con ros2_vita
##     (con rclgd «xrce» no significa nada y activaría el camino compacto en el PC por error).
##   - Si ROS no arranca (agente caído al abrir), se reintenta cada `reintento_s`. Las caídas posteriores las
##     resuelve ya el transporte XRCE (reconexión en xrce_transport.cpp). «validar en hardware».

signal listo                                   # displays conectados (o ROS no disponible y sin reintentos)
## V9 (revisión V2): cada `<p>/pose2d` que recibe TfLigero, ya aplicado. robot_joints se cuelga de aquí en lugar de
## abrir su propia suscripción (cada lector XRCE recibe su copia: 40 B × 30 Hz y 30 datagramas/s por suscripción).
signal pose2d_tf(m)

const Contexto = preload("res://comun/ros/contexto_ros.gd")
const PerfilGd = preload("res://comun/ros/perfil.gd")   # contadores [perfil-gd] (≠ enum Perfil)
const TfLigero = preload("res://comun/visor/tf_ligero.gd")   # V9: TF sin RosTfListener (Vita y host)

enum Perfil { HMI, VIZ }

## Cupos por capa (ADR 0013 §4; ADR 0011 §6; docs/31:255). Instancias 3D en las capas 3D y *quads* en las 2D.
## Solo se aplican en la Vita (en el PC `reservar()` concede todo).
const CUPOS := {
	Perfil.HMI: {"robot": 40, "mundo": 12, "tf": 8, "marcadores": 12, "poses": 4, "lento": 0, "reserva": 4,
		"hud": 400, "sensores_2d": 800, "resto_2d": 300},
	Perfil.VIZ: {"robot": 40, "mundo": 12, "tf": 32, "marcadores": 32, "poses": 16, "lento": 4, "reserva": 14,
		"hud": 400, "sensores_2d": 800, "resto_2d": 300},
}

@export var nombre_nodo := "visor"
@export var transporte := ""                   # "" = argumento, o el de la plataforma (ver cabecera)
@export var marco_fijo := "map"
@export var prefijo_compacto := "/vita"        # /vita o /vita/<robot> (vita_relay.py:21); robot.json lo cambia
@export var perfil: Perfil = Perfil.HMI
@export var px_por_m := 40.0                   # escala de la planta 2D
@export var forzar_compacto := false           # probar en el PC el camino de la Vita (igual que `-- compacto=1`)
@export var camara: Camera3D
@export var texto: Control                     # TextoSuperpuesto (V2); opcional
@export_file("*.json") var config_json := "res://robot.json"   # solo `prefijo_compacto` en V1
@export var reintento_s := 3.0                 # 0 = no reintentar si ROS no arranca
@export_group("TF ligero (V9)")
## Solo sin `create_tf_listener` (Vita y editor de host): TfLigero con fuentes locales (D3).
@export var marco_base := "base_link"          # hijo de `<p>/pose2d` y padre de los links del robot horneado
@export var marco_pose2d := ""                 # padre de pose2d; "" = marco_fijo (supone map ≈ odom, doc 36 §9.3.3).
                                               # Si aún no está unido al fijo (relay sin `tf`), se usa el fijo (V2).
@export var tf_relay := false                  # suscribir `<p>/tf`, `tf_marcos` y `tf_estatico` (módulo tf opcional)
## Estáticos de la escena (regla doc 35), «padre>hijo x y z yaw» en ROS (m, rad); el relay `tf_estatico` los pisa.
@export var tf_estaticos := PackedStringArray()
## V13a: con ros2_vita, usar su `RosTfListener` nativo (tf-tree; suscrito a `/tf` y `/tf_static` crudos) en vez de
## TfLigero, si la plantilla lo trae; si no, TfLigero. Apagado por defecto: el camino compacto (relay) no manda `/tf`
## crudo (no cabe: G1 ≈ 4 796 B, docs/27:73-75) y TfLigero tiene fuentes locales (pose2d, robot horneado,
## estáticos de la escena). Con rclgd (PC) siempre se usa su listener. [decisión V13a, visor/README.md]
@export var tf_nativo := false
@export_group("")

var contexto = Contexto.new()
var tf = null                                  # RosTfListener (PC) o null: SIN anotar (no existe en la Vita, T7)
var en_vita := OS.has_feature("vita")          # las pruebas de host lo ponen a true para simular la Vita
var ros_listo := false
var estado := "sin conectar"
var displays: Array = []                       # los conectados por este visor
var _usados := {}                              # capa -> unidades reservadas
var _avisados := {}                            # quien -> true (aviso de cupo una sola vez)
var _args_compacto := false
var _perfil_propio := false                    # este visor activó PerfilGd y vuelca `[perfil-gd]` (revisión V1)
var _perfil_n := 0
var _gestor: Node = null                       # GestorHud bajo el visor (para el informe de *quads* del HUD)
var _subs_tf: Array = []                       # V9: suscripciones de TfLigero (pose2d y relay tf)


func _ready() -> void:
	_leer_argumentos()
	_leer_config()
	# Medida en hardware (revisión V1): sin aplicacion_robot.gd nadie activaba Perfil en visor-ros, así que los
	# `Perfil.sumar` de las bases no se volcaban. En la Vita o con `-- perfil`, y si otro no lo activó ya, este
	# visor escribe cada PerfilGd.CADA fotogramas `[perfil-gd] … visor/<display>=µs … hud_barra= hud_pestana= …`.
	if not PerfilGd.activo and (OS.has_feature("vita") or OS.get_cmdline_user_args().has("perfil")) \
			and ProjectSettings.get_setting("ros/perfil_gd", true):
		PerfilGd.activo = true
		_perfil_propio = true
	set_process(_perfil_propio)
	# Se conecta dos fotogramas después, como aplicacion_robot.gd: abrir la sesión XRCE puede tardar y así se ve
	# la primera imagen antes.
	_conectar_deferred.call_deferred()


func _leer_argumentos() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("transporte="):
			transporte = a.substr(11)
		elif a == "compacto=1":
			_args_compacto = true
		elif a.begins_with("agente="):
			ProjectSettings.set_setting("ros/agent_ip", a.substr(7))
		elif a.begins_with("puerto="):
			ProjectSettings.set_setting("ros/agent_port", a.substr(7).to_int())
	if transporte == "" and rclgd.has_method("get_transport_info"):   # solo ros2_vita tiene este método
		transporte = String(ProjectSettings.get_setting("ros/transport", ""))


func _leer_config() -> void:
	if config_json == "" or not FileAccess.file_exists(config_json):
		return
	var datos = JSON.parse_string(FileAccess.get_file_as_string(config_json))
	if datos is Dictionary and datos.has("prefijo_compacto"):
		prefijo_compacto = String(datos["prefijo_compacto"])


func _conectar_deferred() -> void:
	for _i in 2:
		if not is_inside_tree():                 # la escena se cambió antes de conectar (SelectorEscena)
			return
		await get_tree().process_frame
	if not is_inside_tree():
		return
	if contexto.iniciar(nombre_nodo, "", transporte) != OK:
		estado = "ROS no arranca (%s)" % transporte
		push_warning("VisorRos: " + estado)
		if reintento_s > 0.0:
			get_tree().create_timer(reintento_s).timeout.connect(_conectar_deferred)
		else:
			listo.emit()
		return
	ros_listo = true
	estado = "ok"
	if usa_tf_nativo():
		tf = contexto.nodo.call("create_tf_listener", 10.0)
	if tf == null:
		_iniciar_tf_ligero()                     # V9 (y respaldo si el nativo no se pudo crear)
	for d in get_tree().get_nodes_in_group("display_ros"):
		if is_ancestor_of(d):
			d.conectar(self)
			displays.append(d)
			print("[visor] %s: %s" % [d.name, d.estado])
	for g in find_children("*", "Control", true, false):
		if g.has_method("informe") and "pestanas" in g:
			_gestor = g
			break
	listo.emit()


func _process(_dt: float) -> void:
	_perfil_n += 1
	if _perfil_n < PerfilGd.CADA:
		return
	var extra := "displays=%d" % displays.size()
	if is_instance_valid(_gestor):
		var h: Dictionary = _gestor.informe()
		extra += " hud_pestana=%s hud_barra_q=%d hud_pestana_q=%d hud_glifos=%d" % [h["pestana"], h["barra_quads"],
				h["pestana_quads"], h["barra_glifos"] + h["pestana_glifos"]]
	# Revisión V2: contadores del transporte (solo ros2_vita) para los gates V6 (`reliable_dropped` = 0) y M3.
	if rclgd.has_method("get_transport_info"):
		var ti: Dictionary = rclgd.call("get_transport_info")
		extra += " rx_paq=%d topic_dropped=%d reliable_dropped=%d be_dropped=%d reconexiones=%d" % [
				int(ti.get("read_packets", 0)), int(ti.get("topic_dropped", 0)), int(ti.get("reliable_dropped", 0)),
				int(ti.get("be_dropped", 0)), int(ti.get("reconexiones", 0))]
	printerr(PerfilGd.volcar(_perfil_n, extra))
	_perfil_n = 0


## Camino compacto (relay /vita/*): Vita, transporte XRCE, `-- compacto=1` o `forzar_compacto`.
func usa_compactos() -> bool:
	return forzar_compacto or _args_compacto or en_vita or contexto.transporte == "xrce"


## Reserva n unidades de la capa (instancias 3D o *quads* 2D); devuelve lo concedido. En el PC, todo.
func reservar(capa: String, n: int, quien: String) -> int:
	if not en_vita or n <= 0:
		return n
	var tope: int = CUPOS[perfil].get(capa, 0)
	var usado: int = _usados.get(capa, 0)
	var dado := clampi(tope - usado, 0, n)
	_usados[capa] = usado + dado
	if dado < n and not _avisados.has(quien):
		_avisados[quien] = true
		push_warning("VisorRos: %s pide %d en «%s» y recibe %d" % [quien, n, capa, dado])
	return dado


func liberar(capa: String, n: int) -> void:
	if n <= 0:
		return
	var usado: int = _usados.get(capa, 0)
	_usados[capa] = maxi(0, usado - n)


func usado(capa: String) -> int:
	return _usados.get(capa, 0)


## Pose de `frame` en el marco fijo (ejes Godot); null si TF no la conoce.
func transformada(frame: String):
	if frame == "" or frame == marco_fijo or tf == null:
		return Transform3D.IDENTITY              # D3: sin TF se supone que el frame ya es el fijo
	if es_tf_ligero() and not tf.frame_exists(marco_fijo):
		return Transform3D.IDENTITY              # V9: TfLigero sin el marco fijo (sin pose2d aún) = como sin TF
	if not tf.can_transform(marco_fijo, frame):
		return null
	return tf.lookup_transform(marco_fijo, frame)


# --- V9: TfLigero (doc 36 §2.9.6; sentencia W13 D3) ---------------------------------------------------------------

## Qué TF crea `_conectar_deferred`: el `RosTfListener` del nodo si existe (`create_tf_listener`) y es rclgd, o es
## ros2_vita con `tf_nativo`; si no, TfLigero. (rclgd no tiene `get_transport_info`: así se distinguen, como arriba.)
func usa_tf_nativo() -> bool:
	if contexto.nodo == null or not contexto.nodo.has_method("create_tf_listener"):
		return false                             # plantilla de la Vita anterior a V13a: solo TfLigero
	return tf_nativo or not rclgd.has_method("get_transport_info")


## true si `tf` es el TfLigero de GDScript (no el RosTfListener nativo).
func es_tf_ligero() -> bool:
	return tf != null and tf.has_method("desde_pose2d")


## Padre real de pose2d. Revisión V2: con `marco_pose2d` puesto pero sin unir aún al marco fijo (relay sin el módulo
## `tf`, o antes de que llegue map → odom) se usa el fijo, como con "": así la MISMA escena vale con y sin el módulo
## `tf` (antes, «odom» sin `tf` dejaba todo en el origen: TfLigero nunca conocía «map»). Al llegar map → odom, el
## siguiente pose2d cuelga la base de odom (TfLigero.poner admite el cambio de padre).
func marco_mundo_pose2d() -> String:
	if marco_pose2d == "" or marco_pose2d == marco_fijo:
		return marco_fijo
	if es_tf_ligero() and not tf.can_transform(marco_fijo, marco_pose2d):
		return marco_fijo
	return marco_pose2d


## true si VisorRos ya está suscrito a `<p>/pose2d` (TfLigero en el camino compacto): los displays usan `pose2d_tf`.
func suscrito_pose2d() -> bool:
	return es_tf_ligero() and not _subs_tf.is_empty()


func _iniciar_tf_ligero() -> void:
	tf = TfLigero.new()
	for linea in tf_estaticos:
		if not poner_estatico(linea):
			push_warning("VisorRos: tf_estaticos «%s» no vale («padre>hijo x y z yaw»)" % linea)
	if not usa_compactos():
		return                                   # PC/host sin relay: solo estáticos y robot (registrar_robot)
	var n = contexto.nodo
	var pre: String = prefijo_compacto.trim_suffix("/")
	var be = contexto.qos(true, 1, false)
	_subs_tf.append(n.create_subscription(pre + "/pose2d", "std_msgs/msg/Float32MultiArray", _al_pose2d_tf, be))
	if tf_relay:
		var fiable = contexto.qos(false, 1, true)
		_subs_tf.append(n.create_subscription(pre + "/tf_marcos", "std_msgs/msg/String", _al_tf_marcos, fiable))
		_subs_tf.append(n.create_subscription(pre + "/tf_estatico", "std_msgs/msg/Float32MultiArray", _al_tf_estatico,
				fiable))
		_subs_tf.append(n.create_subscription(pre + "/tf", "std_msgs/msg/Float32MultiArray", _al_tf_relay, be))


## «padre>hijo x y z yaw» (ROS) → TfLigero. false si la línea no vale.
func poner_estatico(linea: String) -> bool:
	var partes := linea.strip_edges().split(" ", false)
	if partes.size() != 5 or partes[0].count(">") != 1 or not es_tf_ligero():
		return false
	var par := partes[0].split(">")
	var v := PackedFloat64Array()
	for k in range(1, 5):
		if not partes[k].is_valid_float():
			return false
		v.append(partes[k].to_float())
	return tf.poner_ros(par[0], par[1], Vector3(v[0], v[1], v[2]), Quaternion(Vector3(0, 0, 1), v[3])) == TfLigero.OK_TF


func _al_pose2d_tf(m) -> void:
	if es_tf_ligero():
		tf.desde_pose2d(m.data, marco_mundo_pose2d(), marco_base)
		pose2d_tf.emit(m)


func _al_tf_marcos(m) -> void:
	if es_tf_ligero():
		tf.on_tf_marcos(m)


func _al_tf_estatico(m) -> void:
	if es_tf_ligero():
		tf.on_tf_estatico(m)


func _al_tf_relay(m) -> void:
	if es_tf_ligero():
		tf.on_tf_compacto(m)


## Transform3D (ejes Godot) → Transform2D de la planta: x = ROS x, y = −ROS y (norte arriba), en px.
func planta_desde(t: Transform3D) -> Transform2D:
	var adelante: Vector3 = t.basis * Vector3.FORWARD          # +X de ROS = −Z de Godot
	var yaw := atan2(-adelante.x, -adelante.z)                  # yaw ROS
	return Transform2D(-yaw, Vector2(-t.origin.z, t.origin.x) * px_por_m)


func _exit_tree() -> void:
	for d in displays:
		if is_instance_valid(d):
			d.desconectar()
	displays.clear()
	_subs_tf.clear()
	tf = null
	if ros_listo:
		contexto.cerrar()
	ros_listo = false
	if _perfil_propio:
		PerfilGd.activo = false
		_perfil_propio = false
