extends SceneTree

var fallos := 0
var pruebas := 0


func check(condicion: bool, nombre: String) -> void:
	pruebas += 1
	if not condicion:
		fallos += 1
		push_error(nombre)
	else:
		print("OK ", nombre)


func _init() -> void:
	RosMsg.load_schema_file("res://ros/schema.rsch")
	var info = RosMsg.from_type("sensor_msgs/msg/CameraInfo")
	print("CameraInfo p por defecto: ", info.get_member("p").size())
	info.p = PackedFloat64Array([1, 0, 2, 0, 0, 1, 3, 0, 0, 0, 0, 1])
	check(info.get_member("p").size() == 12, "CameraInfo.p de 12 valores")
	check(info.serialize().size() > 0, "CameraInfo serializa")
	var imu = RosMsg.from_type("sensor_msgs/msg/Imu")
	check(imu.serialize().size() <= 488, "IMU cabe en best effort")
	var scan = RosMsg.from_type("sensor_msgs/msg/LaserScan")
	scan.header.frame_id = "laser"
	scan.ranges = PackedFloat32Array()
	scan.ranges.resize(60)
	scan.ranges.fill(1.0)
	scan.intensities = PackedFloat32Array()
	print("LaserScan 60 CDR: ", scan.serialize().size())
	check(scan.serialize().size() <= 488, "LaserScan Vita 60 rayos <= 488 B")
	scan.header.frame_id = "robot_front_laser_link"   # el frame real más largo de las plantillas (revisión R2-B15)
	print("LaserScan 60 CDR con robot_front_laser_link: ", scan.serialize().size())
	check(scan.serialize().size() <= 488, "LaserScan Vita 60 rayos con frame largo <= 488 B")
	var compacto = RosMsg.from_type("std_msgs/msg/Int16MultiArray")
	var datos := PackedInt32Array([0, -21000, 700, 60])
	datos.resize(64)
	compacto.data = datos
	check(compacto.serialize().size() <= 488, "scan compacto <= 488 B")
	_probar_vc1()
	if RosMsg.list_types().has("unitree_go/msg/SportModeState"):
		var sport = RosMsg.from_type("unitree_go/msg/SportModeState")
		var pies := PackedFloat32Array()
		pies.resize(12)
		pies.fill(0.0)
		sport.foot_position_body = pies
		sport.foot_speed_body = pies
		check(sport.get_member("foot_position_body").size() == 12, "Unitree pies fijos de 12")
		check(sport.serialize().size() > 0, "SportModeState serializa")
	print("RESULTADO: ", pruebas - fallos, "/", pruebas)
	quit(0 if fallos == 0 else 1)


## Paridad del contrato VC/1 (revisión R4 §1.6): los mismos vectores que `docker/scripts/vita_relay.py` deben
## dar los mismos números. Las huellas MD5 se generaron con las funciones puras de ese script:
##   empaquetar_scan(rangos, -π, 2π/400, 0,05, 20, 40000) y empaquetar_tesela(rejilla 40×37, …) (ver
##   docs/ia/revision-kimi/arreglos-gdscript.md). Si cambia el formato en un lado, esta prueba falla.
func _probar_vc1() -> void:
	var VC1 = load("res://comun/ros/vc1.gd")
	var rangos := PackedFloat32Array()
	for i in 400:
		match i % 7:
			0: rangos.append(INF)
			1: rangos.append(NAN)
			2: rangos.append(0.01)
			3: rangos.append(25.0)
			_: rangos.append(0.5 + i * 0.0125)
	var scan: PackedInt32Array = VC1.empaquetar_scan(rangos, -PI, TAU / 400.0, 0.05, 20.0, 40000)
	check(scan.size() == 138 and scan[0] == (40000 & 0x7FFF), "VC/1 scan: seq con máscara y diezmado a ≤ 180")
	check(_md5(scan) == "c490f36e2518f8bb307f3fa8568a3e2d", "VC/1 scan = vita_relay.empaquetar_scan")
	var rejilla := PackedInt32Array()
	for y in 37:
		for x in 40:
			rejilla.append((x * 7 + y * 13) % 103 - 2)
	var t11: PackedByteArray = VC1.empaquetar_tesela(rejilla, 40, 37, 1, 1, 513)
	check(t11.size() == 260, "VC/1 tesela de 260 B")
	check(_md5(t11) == "c9b12711c3db36b006ddac7db1697927", "VC/1 tesela (1,1) = vita_relay.empaquetar_tesela")
	check(_md5(VC1.empaquetar_tesela(rejilla, 40, 37, 0, 0, 70000)) == "e1f30b68537023d4191b50fd1436ea20",
		"VC/1 tesela (0,0) con versión > 16 bit")
	check(VC1.celda_2bit(25) == 1 and VC1.celda_2bit(26) == 0 and VC1.celda_2bit(64) == 0
		and VC1.celda_2bit(65) == 2 and VC1.celda_2bit(-1) == 0, "VC/1 umbrales de celda 25/65")
	# VC/1 rev. 2 (V6, doc 36 §5.2): cabecera común troceada. Mismos vectores y huellas que
	# `docker/scripts/test_vita_relay.py` (HUELLA_TROCEAR_F32 / _I16) con `vita_relay_formatos.trocear`.
	var el := []
	for i in 40:
		el.append([i * 3 - 50, i % 7, 1000 + i, -i])
	var t: Array = VC1.trocear(el, 4, [640, 480], 40000)
	var t2: Array = VC1.trocear(el + el + el, 4, [], 7, VC1.MAX_I16, 3)
	var plano := []
	for x in t:
		plano.append_array(x)
	var plano2 := []
	for x in t2:
		plano2.append_array(x)
	check(t.size() == 2 and t[0].size() == VC1.MAX_F32 and VC1.cabecera(t[1]).n == 12
		and _md5(plano) == "5da842991233e493fd04afd2d9c78df6"
		and _md5(plano2) == "e2c81111e76c4b212dd9b5340850a655", "VC/1.2 trocear = vita_relay_formatos.trocear")
	check(VC1.cabecera([1, 2, 2, 0]).is_empty() and VC1.leer_relay_info("VC/1.2;scan,rosout").modulos.size() == 2,
		"VC/1.2 cabecera inválida y relay_info")


func _md5(datos) -> String:
	var partes := PackedStringArray()
	for v in datos:
		partes.append(str(int(v)))
	return ",".join(partes).md5_text()

