extends RefCounted
## Contadores de tiempo propios de las plantillas (perfil «Vita ligero», 2026-11-13).
##
## El log del motor en la Vita (`[vita-prof]`) da el total de «scripts de física» y de `_process`, pero no dice
## QUÉ script lo gasta. Esto lo desglosa: cada sección mide con `Time.get_ticks_usec()` y, cada `CADA` fotogramas,
## la aplicación vuelca una línea a stderr (en la Vita acaba en `ux0:/data/gxm3d/godot_stderr.log`):
##
##   [perfil-gd] fotogramas=300 robot=1850 sensor/imu_pelvis=40 … hud=120 (µs por fotograma, media)
##
## Uso:  var t := Perfil.t0()  …trabajo…  Perfil.sumar("nombre", t)   (solo si Perfil.activo)
## Activo en la Vita y con el argumento `perfil` en el PC; `ros/perfil_gd=false` en project.godot lo apaga.
## Coste propio: dos lecturas de reloj y una suma en un diccionario por sección (unos µs en la Vita [I]).

const CADA := 300

static var activo := false
static var _us := {}      # sección -> µs acumulados desde el último volcado
static var _veces := {}   # sección -> llamadas desde el último volcado


## ¿Perfil «Vita ligero» (doc 34)? En la Vita, o en el PC con `-- lod=vita`; `-- mundo=completo` lo anula para
## comparar. Lo consultan la aplicación y el mundo (mundo_base.gd), que ahora está dentro de main.tscn y hace su
## _ready() antes que la aplicación, así que no puede esperar a que esta se lo diga.
static func es_ligero() -> bool:
	var args := OS.get_cmdline_user_args()
	return (OS.has_feature("vita") or args.has("lod=vita")) and not args.has("mundo=completo")


static func t0() -> int:
	return Time.get_ticks_usec()


static func sumar(seccion: String, desde: int) -> void:
	_us[seccion] = _us.get(seccion, 0) + (Time.get_ticks_usec() - desde)
	_veces[seccion] = _veces.get(seccion, 0) + 1


## Línea con la media por fotograma de cada sección y puesta a cero. `extra` se añade tal cual (p. ej. triángulos).
static func volcar(fotogramas: int, extra: String = "") -> String:
	var claves := _us.keys()
	claves.sort()
	var partes := PackedStringArray()
	for c in claves:
		partes.append("%s=%d" % [c, int(_us[c] / maxi(fotogramas, 1))])
	var linea := "[perfil-gd] fotogramas=%d %s" % [fotogramas, " ".join(partes)]
	if extra != "":
		linea += " " + extra
	_us.clear()
	_veces.clear()
	return linea


## Copia de los acumulados actuales (para pruebas): sección -> [µs, llamadas].
static func instantanea() -> Dictionary:
	var r := {}
	for c in _us:
		r[c] = [_us[c], _veces[c]]
	return r
