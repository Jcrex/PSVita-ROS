extends Node2D
## HerramientaVisor (ADR 0013; doc 36 §2.9.9 y §6; sentencia W13 C9; tarea V7): base de las herramientas que
## PUBLICAN (≈ `rviz_common::Tool`): meta (`goal_pose`), pose inicial (`initialpose`), punto (`/clicked_point`) y
## teleop (`/cmd_vel`). Mismo script en el PC (ratón y teclado) y en la Vita (táctil delantero como ratón, ✕, SELECT).
##
## Contrato:
##   - vive en el `.tscn` bajo el VisorRos (regla doc 35) y entra en el grupo "display_ros": VisorRos la conecta
##     como a un display (`conectar(visor)` / `desconectar()`, `estado`);
##   - publica FIABLE por defecto (tabla de doc 36 §6): profundidad 5 en el PC y 1 en la Vita, volátil, como RViz
##     (`goal_tool.cpp:67,78`: `rclcpp::QoS(5)`). La QoS se pide SIEMPRE a `visor.contexto.qos()` (usa `set_*()`;
##     nunca `qos.reliability = …`, trampa T3 de doc 36 §8: falla en la Vita);
##   - `header.frame_id` = `visor.marco_fijo` y sello `nodo.now()` (en la Vita, hora del agente);
##   - un toque/clic = un evento; en la Vita la meta y la pose inicial quedan «pendientes» hasta ✕
##     (`confirmar_en_vita`);
##   - SELECT (o Tab en el PC) recorre las herramientas del mismo visor en orden del árbol: ninguna → 1.ª → 2.ª … →
##     ninguna. El nombre de la activa sale en la barra de estado (`barra_estado.gd`, propiedad `herramienta`).
##
## Del punto de pantalla al suelo del marco fijo (`suelo_godot`, `suelo_ros`):
##   - con `planta` (el Node2D «Vista» de la planta 2D, donde dibujan los displays 2D) visible: inversa de
##     `VisorRos.planta_desde` (px → m, norte arriba). Es el camino por defecto en la Vita (D7: la planta gana);
##   - si no, rayo de `visor.camara` contra el plano del suelo de `marco_fijo_nodo` (o del mundo si es null: el
##     marco fijo de los displays es el origen de Godot, `VisorRos.transformada`);
##   - el resultado en ejes de Godot pasa a ROS con `rclgd.godot_to_ros_vector` (ros = (−g.z, −g.x, g.y),
##     `godot/ros2_vita/API_PARITY.md:19`).
##
## Decisiones de V7 no cubiertas por el ADR (las más conservadoras; anotadas en visor/README.md):
##   - `extends Node2D` (no `Node` como el esqueleto de doc 36 §2.9.9): la herramienta dibuja su flecha fantasma
##     (y la meta «pendiente» en naranja) en su propio `_draw()`, en coordenadas de pantalla. Va bajo el CanvasLayer
##     del HUD para quedar encima de la planta. ≤ 4 *quads* (`_coste`).
##   - El ciclo de SELECT incluye «ninguna» y arranca sin herramienta activa (salvo `activa_al_inicio`): una
##     consola de mano no publica nada por un roce.
##   - Quien atiende SELECT es la herramienta activa (o, sin activa, la primera del visor): un solo evento cambia
##     una sola vez aunque haya cuatro herramientas escuchando.
##   - En la Vita imprime `[visor-herr] <nombre> toque n=… publicados=…` en cada pulsación (criterio de hardware
##     «un toque = un evento», doc 36 §9.10).

const Paleta = preload("res://comun/visor/paleta_viz.gd")

signal publicado(msg)                          # tras cada publish (pruebas y HUD)
signal activada(activa: bool)

@export var habilitado := true
@export var topic := ""
@export var tipo := ""
@export_enum("FIABLE", "BEST_EFFORT") var fiabilidad := 0
@export var profundidad := 0                   # 0 = la de la tabla de doc 36 §6 (`_profundidad_tabla`)
@export var confirmar_en_vita := true          # ✕ confirma metas y poses en la Vita (evita roces)
@export var marco_fijo_nodo: Node3D            # nodo alineado con visor.marco_fijo; null = origen del mundo
@export var planta: Node2D                     # «Vista» de la planta 2D; si está visible, se toca en la planta
@export var activa_al_inicio := false
@export var boton_ciclo := JOY_BUTTON_BACK     # SELECT en el port [I, validar en hardware]; −1 = desactivado
@export var tecla_ciclo := KEY_TAB             # PC
@export var boton_confirmar := JOY_BUTTON_A    # ✕ (g6-hmi/main.gd:113, validado en G6); también `ui_accept`
@export var alcance := 200.0                   # m del rayo de cámara

var visor
var pub = null                                 # RosPublisher (sin anotar: no existe sin el módulo, T7)
var qos = null                                 # RosQoS usada (las pruebas leen get_reliability/get_depth)
var activa := false
var estado := "sin conectar"
var publicados := 0
var toques := 0                                # pulsaciones del botón izquierdo recibidas estando activa


static func nombre_herramienta() -> String:
	return "Herramienta"


func _enter_tree() -> void:
	add_to_group("display_ros")                # VisorRos conecta también las herramientas
	add_to_group("herramienta_visor")


func _ready() -> void:
	set_process(false)                         # las herramientas trabajan por eventos (y RosTimer en teleop)


func conectar(v) -> void:
	visor = v
	if not habilitado:
		estado = "desactivado"
		return
	if topic == "" or tipo == "":
		estado = "sin topic"
		return
	if RosMsg.from_type(tipo) == null:
		estado = "sin esquema: " + tipo
		return
	qos = v.contexto.qos(fiabilidad == 1, profundidad if profundidad > 0 else _profundidad_tabla(), false)
	pub = v.contexto.nodo.create_publisher(topic, tipo, qos)
	estado = "ok" if pub != null else "publicador rechazado"
	if activa_al_inicio and pub != null:
		activar(true)


func desconectar() -> void:
	if activa:
		activar(false)
	pub = null
	estado = "sin conectar"


## Tabla de doc 36 §6: meta, pose inicial y punto 5 (PC) / 1 (Vita). Teleop la cambia a 1.
func _profundidad_tabla() -> int:
	return 1 if visor.en_vita else 5


func publicar(m) -> void:
	if pub == null:
		return
	pub.publish(m)
	publicados += 1
	publicado.emit(m)


## Cabecera estándar de lo que publica una herramienta: marco fijo y hora del nodo.
func cabecera(m) -> void:
	m.header.frame_id = visor.marco_fijo
	m.header.stamp = visor.contexto.nodo.now()


# --- activación y ciclo (SELECT) ---------------------------------------------------------------------------------
func activar(on: bool) -> void:
	if on == activa:
		return
	if on:                                     # una sola activa por visor
		for h in hermanas():
			if h != self and h.activa:
				h.activar(false)
	activa = on
	_al_activar(on)
	queue_redraw()
	_avisar_barra()
	activada.emit(on)


## Gancho de las subclases (teleop manda un Twist cero al desactivarse en marcha).
func _al_activar(_on: bool) -> void:
	pass


## Herramientas del mismo visor, en orden del árbol.
func hermanas() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	for h in get_tree().get_nodes_in_group("herramienta_visor"):
		if h.visor == visor and h.estado == "ok":
			out.append(h)
	out.sort_custom(func(a, b): return b.is_greater_than(a))
	return out


## SELECT: ninguna → 1.ª → … → última → ninguna.
func ciclar() -> void:
	var hs := hermanas()
	if hs.is_empty():
		return
	var i := -1
	for k in hs.size():
		if hs[k].activa:
			i = k
	if i >= 0:
		hs[i].activar(false)
	if i + 1 < hs.size():
		hs[i + 1].activar(true)


## Nombre de la herramienta activa en la barra de estado (si la escena tiene una bajo el visor).
func _avisar_barra() -> void:
	if visor == null:
		return
	var nombre := ""
	for h in hermanas():
		if h.activa:
			nombre = h.nombre_herramienta()
	for d in visor.displays:
		if is_instance_valid(d) and "herramienta" in d and d.has_method("componer"):
			d.herramienta = nombre
			d.set("_t", 1000.0)                # recomponer en el próximo fotograma


func _es_ciclo(e: InputEvent) -> bool:
	if e is InputEventJoypadButton:
		return e.pressed and int(boton_ciclo) >= 0 and e.button_index == boton_ciclo
	if e is InputEventKey:
		return e.pressed and not e.echo and e.keycode == tecla_ciclo
	return false


func es_confirmar(e: InputEvent) -> bool:
	if e is InputEventJoypadButton and e.pressed and e.button_index == boton_confirmar:
		return true
	return e.is_action_pressed("ui_accept") and not (e is InputEventJoypadButton)   # Intro/Espacio en el PC


func _unhandled_input(e: InputEvent) -> void:
	if estado != "ok":
		return
	if _es_ciclo(e):
		var hs := hermanas()
		var atiende := activa
		if not atiende and not hs.is_empty():
			atiende = hs[0] == self and hs.all(func(h): return not h.activa)
		if atiende:
			ciclar()
			get_viewport().set_input_as_handled()
		return
	if not activa:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		toques += 1
		if visor.en_vita:
			print("[visor-herr] %s toque n=%d publicados=%d" % [nombre_herramienta(), toques, publicados])
	if _entrada(e):
		get_viewport().set_input_as_handled()


## Gancho de las subclases: true = evento consumido.
func _entrada(_e: InputEvent) -> bool:
	return false


# --- de la pantalla al suelo del marco fijo ----------------------------------------------------------------------
## Punto de pantalla (coordenadas del viewport) → punto del suelo en el marco fijo, ejes de Godot; o null.
func suelo_godot(p: Vector2):
	if planta != null and planta.is_visible_in_tree():
		var l: Vector2 = planta.get_global_transform_with_canvas().affine_inverse() * p
		var px: float = visor.px_por_m
		return Vector3(l.y / px, 0.0, -l.x / px)          # inversa de VisorRos.planta_desde
	var cam: Camera3D = _camara()
	if cam == null:
		return null
	var g := _marco()
	var hit = Plane(g.basis.y.normalized(), g.origin).intersects_ray(cam.project_ray_origin(p), cam.project_ray_normal(p))
	return null if hit == null else g.affine_inverse() * (hit as Vector3)


## Igual que `suelo_godot` pero en ejes ROS (x adelante, y izquierda, z arriba).
func suelo_ros(p: Vector2):
	var g = suelo_godot(p)
	return null if g == null else rclgd.godot_to_ros_vector(g as Vector3)


func _camara() -> Camera3D:
	if visor != null and visor.camara != null:
		return visor.camara
	return get_viewport().get_camera_3d()


func _marco() -> Transform3D:
	return marco_fijo_nodo.global_transform if marco_fijo_nodo != null else Transform3D.IDENTITY


## Pantalla → coordenadas locales de este CanvasItem (para dibujar la flecha fantasma).
func a_local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


## Flecha fina de a a b (3 segmentos = 3 *quads*).
func flecha(a: Vector2, b: Vector2, c: Color) -> void:
	var d := b - a
	if d.length() < 2.0:
		draw_circle(a, 4.0, c)
		return
	var u := d.normalized() * 10.0
	draw_line(a, b, c, -1.0)
	draw_line(b, b - u.rotated(0.45), c, -1.0)
	draw_line(b, b - u.rotated(-0.45), c, -1.0)


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 4}
