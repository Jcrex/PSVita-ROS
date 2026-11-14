extends RefCounted
## TiempoRos (doc 36a §4.1.8, ficha nucleo#15): `builtin_interfaces/Time` y `Duration` y `std_msgs/Header`,
## portable rclgd ↔ ros2_vita. Estático: `const TiempoRos = preload("res://comun/visor/tiempo_ros.gd")`.
##
## En la Vita `now()` es la hora del agente tras `uxr_sync_session`; si falló, reloj local y la latencia no tiene
## sentido. Sin `use_sim_time`: con `/clock` de simulación la latencia es basura → NAN si |latencia| > 1 h [I].


static func segundos(t) -> float:
	return float(t.sec) + float(t.nanosec) * 1e-9


static func a_texto(t) -> String:
	return "%d.%09d" % [t.sec, t.nanosec]


## Latencia (now − header.stamp) en s; NAN si no hay cabecera, si el sello es 0 o si es absurdo.
static func latencia(nodo, msg) -> float:
	if not ("header" in msg):
		return NAN
	var st = msg.header.stamp
	if st.sec == 0 and st.nanosec == 0:
		return NAN
	var l := segundos(nodo.now()) - segundos(st)
	return l if absf(l) < 3600.0 else NAN


## Escribe `s` segundos en un `Time`/`Duration` (RosMsg). Los negativos quedan con `nanosec` en [0, 1e9).
static func escribir_tiempo(t, s: float) -> void:
	var entero := floorf(s)
	t.sec = int(entero)
	t.nanosec = mini(int((s - entero) * 1e9), 999999999)
