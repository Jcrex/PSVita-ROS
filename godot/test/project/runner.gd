extends SceneTree
## Pruebas de host del módulo ros2_vita (Godot 4). ¡SIN EJECUTAR!: requieren un Godot
## compilado con el módulo (puerta G1 de docs/18). Se ejecutan con:
##   godot --headless --path godot/test/project --script res://runner.gd -- fixtures=<dir>
## donde <dir> = modules/msg-schema/tests/fixtures (schema.rsch + casos .bin/.type).
## Cubre lo que se puede probar SIN Vita: RosMsg dinámico (CDR <-> propiedades),
## pub/sub con el transporte loopback, timers, resolución de topics y ejes.

var fixtures := ""
var failures := 0
var checks := 0


func expect(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("  FALLO: ", msg)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("fixtures="):
			fixtures = a.substr(9)
	_run()


func _payload(case_name: String) -> PackedByteArray:
	# El .bin trae la encapsulación de 4 bytes (00 01 00 00): el payload empieza después.
	return FileAccess.get_file_as_bytes(fixtures.path_join(case_name + ".bin")).slice(4)


func _run() -> void:
	expect(not fixtures.is_empty(), "falta -- fixtures=<dir>")
	expect(RosMsg.load_schema_file(fixtures.path_join("schema.rsch")) == OK, "carga de schema.rsch")
	expect(RosMsg.list_types().size() > 20, "list_types")

	_test_roundtrip_all()
	_test_set_properties()
	_test_bad_values()
	await _test_pubsub_and_timer()
	_test_axes()

	print("ros2_vita host tests: %d comprobaciones, %d fallos" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_roundtrip_all() -> void:
	var names := FileAccess.get_file_as_string(fixtures.path_join("cases.txt")).split("\n", false)
	for n in names:
		var type_name := FileAccess.get_file_as_string(fixtures.path_join(n + ".type")).strip_edges()
		var want := _payload(n)
		var msg := RosMsg.from_type(type_name)
		expect(msg != null, "from_type " + type_name)
		if msg == null:
			continue
		expect(msg.deserialize(want) == OK, "deserialize " + n)
		expect(msg.serialize() == want, "roundtrip bit a bit " + n)
		expect(msg.get_ros_interface_name() == type_name, "interface name " + n)
		# deserialize debe fallar (no crashear) con cualquier recorte
		for cut in range(0, want.size(), max(1, want.size() / 8)):
			expect(msg.deserialize(want.slice(0, cut)) != OK or cut == want.size(), "recorte " + n)
	expect(RosMsg.from_type("no/existe/Tipo") == null, "tipo desconocido => null")
	expect(RosMsg.from_type("geometry_msgs/msg/Twist").get_type_name() == "RosGeometryMsgsTwist", "get_type_name")


func _test_set_properties() -> void:
	# Twist: valores del fixture twist.bin
	var t := RosMsg.from_type("geometry_msgs/msg/Twist")
	t.linear.x = 0.5
	t.linear.z = -0.25
	t.angular.y = 0.125
	t.angular.z = 1.5
	expect(t.serialize() == _payload("twist"), "Twist por propiedades == fixture")
	expect(t.linear.x == 0.5 and t.angular.z == 1.5, "lectura de propiedades anidadas")

	# Imu: cabecera anidada, arrays fijos de float64
	var imu := RosMsg.from_type("sensor_msgs/msg/Imu")
	imu.header.stamp.sec = 100
	imu.header.stamp.nanosec = 200
	imu.header.frame_id = "imu_link"
	imu.orientation.w = 1.0
	var cov := PackedFloat64Array()
	for i in 9:
		cov.append(i * 0.5)
	imu.orientation_covariance = cov
	imu.angular_velocity.x = 0.01
	imu.angular_velocity.y = 0.02
	imu.angular_velocity.z = 0.03
	var cov2 := PackedFloat64Array()
	var cov3 := PackedFloat64Array()
	for i in 9:
		cov2.append(i * 0.5 * 2)
		cov3.append(i * 0.5 * 3)
	imu.angular_velocity_covariance = cov2
	imu.linear_acceleration.z = 9.81
	imu.linear_acceleration_covariance = cov3
	expect(imu.serialize() == _payload("imu"), "Imu por propiedades == fixture")

	# TFMessage: array de structs
	var tf := RosMsg.from_type("tf2_msgs/msg/TFMessage")
	var a := RosMsg.from_type("geometry_msgs/msg/TransformStamped")
	a.header.stamp.sec = 1234
	a.header.stamp.nanosec = 5678
	a.header.frame_id = "odom"
	a.child_frame_id = "base_link"
	a.transform.translation.x = 1.5
	a.transform.translation.y = -2.25
	a.transform.translation.z = 0.5
	a.transform.rotation.w = 1.0
	var b := RosMsg.from_type("geometry_msgs/msg/TransformStamped")
	b.header.stamp.sec = 1234
	b.header.stamp.nanosec = 5678
	b.header.frame_id = "base_link"
	b.child_frame_id = "laser"
	b.transform.translation.x = 0.1
	b.transform.translation.z = 0.2
	b.transform.rotation.w = 1.0
	tf.transforms = [a, b]
	expect(tf.serialize() == _payload("tf"), "TFMessage por propiedades == fixture")

	# JointState: array de strings + arrays de float64 (velocity vacío)
	var js := RosMsg.from_type("sensor_msgs/msg/JointState")
	js.header.stamp.sec = 7
	js.header.stamp.nanosec = 8
	js.name = PackedStringArray(["wheel_left", "wheel_right", "arm_joint_1"])
	js.position = PackedFloat64Array([0.5, -1.25, 3.0])
	js.effort = PackedFloat64Array([0.125, 0.25, 0.375])
	expect(js.serialize() == _payload("joint_state"), "JointState por propiedades == fixture")

	# Image: bytes (PackedByteArray) + strings
	var img := RosMsg.from_type("sensor_msgs/msg/Image")
	img.header.stamp.sec = 7
	img.header.stamp.nanosec = 8
	img.header.frame_id = "camera"
	img.height = 4
	img.width = 5
	img.encoding = "rgba8"
	img.step = 20
	var px := PackedByteArray()
	for i in 80:
		px.append(i)
	img.data = px
	expect(img.serialize() == _payload("image"), "Image por propiedades == fixture")


func _test_bad_values() -> void:
	var imu := RosMsg.from_type("sensor_msgs/msg/Imu")
	# array fijo de 9 con 3 elementos: se rechaza y el valor anterior se conserva
	var before := imu.orientation_covariance
	imu.orientation_covariance = PackedFloat64Array([1.0, 2.0, 3.0])
	expect(imu.orientation_covariance == before, "array fijo con longitud errónea se rechaza")
	# compuesto de otro tipo
	var wrong := RosMsg.from_type("geometry_msgs/msg/Vector3")
	imu.header = wrong
	expect(imu.header.get_ros_interface_name() == "std_msgs/msg/Header", "struct de otro tipo se rechaza")


func _test_pubsub_and_timer() -> void:
	var args := PackedStringArray(["-p", "transport:=loopback", "-p", "schema:=" + fixtures.path_join("schema.rsch")])
	expect(rclgd.init(args) == OK, "rclgd.init")
	expect(rclgd.ok(), "rclgd.ok")

	var node := RosNode.new()
	node.init("roomba", "/r1")
	expect(node.get_name() == "roomba" and node.get_namespace() == "/r1", "nombre y namespace")
	expect(node.resolve_frame("~base_link") == "r1/base_link", "resolve_frame ~")
	expect(node.resolve_frame("/odom") == "odom", "resolve_frame /")

	var got := []
	var sub := node.create_subscription("/r1/roomba/cmd", "geometry_msgs/msg/Twist",
			func(m): got.append(m))
	var pub := node.create_publisher("~/cmd", "geometry_msgs/msg/Twist")   # "~" => /r1/roomba/cmd
	var m := RosMsg.from_type("geometry_msgs/msg/Twist")
	m.linear.x = 0.75
	pub.publish(m)
	expect(got.is_empty(), "los callbacks NO se ejecutan en la publicación (van al hilo principal)")
	await process_frame
	await process_frame
	expect(got.size() == 1, "mensaje entregado por loopback")
	if got.size() == 1:
		expect(got[0].linear.x == 0.75, "contenido del mensaje recibido")

	# Tipo equivocado: no se publica
	var wrong := RosMsg.from_type("std_msgs/msg/String")
	pub.publish(wrong)   # imprime error, no entrega
	await process_frame
	expect(got.size() == 1, "tipo incorrecto no se entrega")

	# Soltar la referencia cancela la suscripción (RefCounted, como rclgd)
	sub = null
	pub.publish(m)
	await process_frame
	expect(got.size() == 1, "suscripción liberada deja de recibir")

	# Timer
	var ticks := [0]
	var timer := node.create_timer(0.05, func(): ticks[0] += 1)
	await create_timer(0.35).timeout
	expect(ticks[0] >= 3 and ticks[0] <= 8, "timer disparó %d veces" % ticks[0])
	timer.cancel()
	var after: int = ticks[0]
	await create_timer(0.15).timeout
	expect(ticks[0] == after, "timer cancelado no dispara")

	# Parámetros
	node.declare_parameter("max_speed", 0.5)
	var changed := []
	node.parameter_changed.connect(func(n, v): changed.append([n, v]))
	node.set_parameter("max_speed", 0.9)
	expect(node.get_parameter("max_speed") == 0.9 and changed.size() == 1, "parámetros y señal")

	rclgd.shutdown()
	expect(not rclgd.ok(), "rclgd.shutdown")


func _test_axes() -> void:
	# Misma convención que rclgd (docs/17 §3.3): ros = (-g.z, -g.x, g.y)
	var v := Vector3(1, 2, 3)
	var r: Vector3 = rclgd.godot_to_ros_vector(v)
	expect(r == Vector3(-3, -1, 2), "godot_to_ros_vector")
	expect(rclgd.ros_to_godot_vector(r) == v, "ros_to_godot_vector inversa")
	var q := Quaternion(0.1, 0.2, 0.3, 0.9)
	expect(rclgd.ros_to_godot_quat(rclgd.godot_to_ros_quat(q)).is_equal_approx(q), "quat inversa")
