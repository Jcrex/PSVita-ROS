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
	var compacto = RosMsg.from_type("std_msgs/msg/Int16MultiArray")
	var datos := PackedInt32Array([0, -21000, 700, 60])
	datos.resize(64)
	compacto.data = datos
	check(compacto.serialize().size() <= 488, "scan compacto <= 488 B")
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
