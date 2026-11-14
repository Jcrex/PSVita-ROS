extends "res://comun/visor/display_ros_3d.gd"
## Display TF (V9; doc 36a §4.3.3, D geom#15 → ⚖ D3 y D7): EJES por marco en el marco fijo, flecha de cada hijo a su
## padre (solo PC) y nombres con TextoSuperpuesto (nunca `Label3D`, T15). NO se suscribe a `/tf`: consulta
## `visor.tf` cada `periodo` s (RosTfListener en el PC, TfLigero en la Vita: pose2d, robot horneado, estáticos de la
## escena y, opcional, el módulo `tf` del relay). Capa «tf»: 8 instancias en HMI y 32 en Viz (D7).
##
## Decisiones de V9 (las más conservadoras; visor/README.md):
##   - Cupo = `max_marcos_vita` (8) en la Vita y `max_marcos` (32) en el PC, × 2 si hay flechas (apagadas en la Vita).
##     Los marcos que no caben no se crean (en orden de `get_frame_names()`); `filtro` elige cuáles.
##   - Sin caducidad por marco: TfLigero no guarda sello (último valor, como tf-tree) y `get_frame_latest_time` del
##     PC no se usa para no tener dos comportamientos.
##   - Un marco sin transformada al fijo se oculta (como RViz); con TfLigero sin el marco fijo, todo cuelga del
##     origen (D3, `VisorRos.transformada`).

const Prim = preload("res://comun/visor/primitivas_viz.gd")

@export var escala := 0.3                              # RViz «Marker Scale»
@export var periodo := 0.1                             # 10 Hz
@export var mostrar_nombres := false                   # gastan glifos de TextoSuperpuesto (≤ 40 en la Vita, D11)
@export var mostrar_flechas := true                    # hijo → padre; se apagan en la Vita (D7)
@export var filtro := PackedStringArray()              # vacío = todos
@export var max_marcos := 32
@export var max_marcos_vita := 8
@export var color_flecha := Color(1.0, 0.9, 0.2)

var marcos_dibujados := 0                              # pruebas y HUD
var _ejes := {}                                        # marco -> MeshInstance3D (EJES)
var _flechas := {}                                     # marco -> MeshInstance3D (FLECHA)
var _t := 0.0


static func nombre_display() -> String:
	return "TF"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["tf2_msgs/msg/TFMessage"])


func _init() -> void:
	capa = "tf"
	topic = ""                                         # sin suscripción propia: consulta visor.tf


func conectar(v) -> void:
	topic = ""                                         # aunque RegistroDisplays.crear() ponga "/tf": nunca /tf crudo
	topic_vita = ""
	if v.en_vita:
		mostrar_flechas = false                        # D7: 32 marcos × 2 no caben en «tf»
	super.conectar(v)                                  # topic "" → «sin topic»: reserva el cupo y sigue procesando
	if cupo > 0 and estado == "sin topic":
		estado = "ok"


func desconectar() -> void:
	for f in _ejes:
		_ejes[f].queue_free()
	for f in _flechas:
		_flechas[f].queue_free()
	_ejes.clear()
	_flechas.clear()
	marcos_dibujados = 0
	super.desconectar()


func _process(dt: float) -> void:
	super._process(dt)
	_t += dt
	if _t < periodo:
		return
	_t = 0.0
	refrescar()


## Una pasada: crea los ejes que falten (dentro del cupo) y coloca todos. Pública para las pruebas.
func refrescar() -> void:
	if visor == null or visor.tf == null or cupo <= 0:
		return
	var por_marco := 2 if mostrar_flechas else 1
	var n := 0
	for f in visor.tf.get_frame_names():
		if filtro.size() > 0 and not filtro.has(f):
			continue
		if not _ejes.has(f):
			if (_ejes.size() + 1) * por_marco > cupo:
				continue                               # sin cupo: no se crea (lo avisó reservar())
			_ejes[f] = Prim.instancia(Prim.EJES)
			add_child(_ejes[f])
			if mostrar_flechas:
				_flechas[f] = Prim.instancia(Prim.FLECHA, color_flecha)
				add_child(_flechas[f])
		var t = visor.transformada(f)
		_ejes[f].visible = t != null
		if t == null:
			if _flechas.has(f):
				_flechas[f].visible = false
			continue
		var tt: Transform3D = t
		_ejes[f].transform = Transform3D(tt.basis.orthonormalized().scaled_local(Vector3.ONE * escala), tt.origin)
		n += 1
		if mostrar_nombres and visor.texto != null:
			visor.texto.poner("tf/" + f, tt.origin, f)
		if _flechas.has(f):
			var padre: String = visor.tf.get_frame_parent(f)
			var tp = visor.transformada(padre) if padre != "" else null
			var fl = Prim.flecha_hacia((tp as Transform3D).origin - tt.origin) if tp != null else null
			_flechas[f].visible = fl != null
			if fl != null:
				_flechas[f].transform = Transform3D((fl as Transform3D).basis, tt.origin)
	marcos_dibujados = n


## Pose (ejes Godot, marco fijo) de los EJES de `f`, o null si no se dibuja (pruebas).
func pose_de(f: String):
	if not _ejes.has(f) or not _ejes[f].visible:
		return null
	return _ejes[f].transform


func _coste() -> Dictionary:
	var vita: bool = visor != null and visor.en_vita
	var n: int = max_marcos_vita if vita else max_marcos
	var inst: int = n * (2 if mostrar_flechas and not vita else 1)
	return {"instancias": inst, "triangulos": n * Prim.TRIANGULOS[Prim.EJES] +
			(n * Prim.TRIANGULOS[Prim.FLECHA] if inst > n else 0), "quads": 0}
