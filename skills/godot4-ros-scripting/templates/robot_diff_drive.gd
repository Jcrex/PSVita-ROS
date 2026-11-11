class_name DiffDriveRobot
extends RigidBody3D
## Plantilla: robot diferencial expuesto a ROS 2 (rclgd en PC / ros2_vita en Vita).
## Adaptado de roomba_ws (c) 2026 Miguel Oroz Zubasti, licencia MIT.
## SIN EJECUTAR en este repo: validar en el PC con `ros2 rclgd editor`.

@export var max_linear_speed: float = 0.5   # m/s (defecto; el parámetro ROS manda)
@export var max_angular_speed: float = 2.5  # rad/s
@export var cmd_vel_timeout: float = 0.5    # s sin /cmd_vel => parar

var _node: RosNode
var _cmd_sub: RosSubscriber
var _odom_pub: RosPublisher
var _tf: RosTfBroadcaster
var _stop_srv: RosService
var _odom: RosMsg  # reutilizado cada tick; se crea en _ready (portable a ros2_vita, que carga el esquema en rclgd.init)
var _odom_origin: Transform3D
var _target_lin := 0.0
var _target_ang := 0.0
var _last_cmd_s := -INF


func _ready() -> void:
	_node = RosNode.new()
	_node.init("robot")
	_cmd_sub = _node.create_subscription("/cmd_vel", "geometry_msgs/msg/Twist", _on_cmd_vel)
	_odom_pub = _node.create_publisher("/odom", "nav_msgs/msg/Odometry")
	_tf = _node.create_tf_broadcaster()
	_odom = RosMsg.from_type("nav_msgs/msg/Odometry")
	_odom.header.frame_id = "odom"
	_odom.child_frame_id = "base_link"
	_odom_origin = global_transform
	_tf.send_transform(_odom_origin, "odom", "map", true)  # map->odom estático
	_stop_srv = _node.create_service("~/stop", "std_srvs/srv/Trigger", _on_stop)
	# Parámetros: declarar con el @export como defecto y releer (gana -p / ros/parameters/*)
	_node.declare_parameter("max_linear_speed", max_linear_speed)
	max_linear_speed = _node.get_parameter("max_linear_speed")
	_node.parameter_changed.connect(_on_param)


func _on_cmd_vel(msg: RosMsg) -> void:  # hilo principal
	_last_cmd_s = Time.get_ticks_msec() / 1000.0
	_target_lin = clampf(msg.linear.x, -max_linear_speed, max_linear_speed)
	_target_ang = clampf(msg.angular.z, -max_angular_speed, max_angular_speed)


func _on_stop(_req: RosMsg, res: RosMsg) -> void:  # ¡hilo del executor!
	_halt.call_deferred()
	res.success = true
	res.message = "parado"


func _halt() -> void:
	_target_lin = 0.0
	_target_ang = 0.0


func _on_param(param_name: String, value: Variant) -> void:
	if param_name == "max_linear_speed":
		max_linear_speed = value


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var forward := -state.transform.basis.z  # adelante en Godot = -Z
	forward.y = 0.0
	state.linear_velocity = forward.normalized() * _target_lin + Vector3.UP * state.linear_velocity.y
	state.angular_velocity = Vector3.UP * _target_ang


func _physics_process(_delta: float) -> void:
	if Time.get_ticks_msec() / 1000.0 - _last_cmd_s > cmd_vel_timeout:
		_halt()
	var pose := _odom_origin.affine_inverse() * global_transform
	_odom.header.stamp = _node.now()
	var p := rclgd.godot_to_ros_vector(pose.origin)
	_odom.pose.pose.position.x = p.x
	_odom.pose.pose.position.y = p.y
	_odom.pose.pose.position.z = p.z
	var q := rclgd.godot_to_ros_quat(pose.basis.get_rotation_quaternion())
	_odom.pose.pose.orientation.x = q.x
	_odom.pose.pose.orientation.y = q.y
	_odom.pose.pose.orientation.z = q.z
	_odom.pose.pose.orientation.w = q.w
	var v := rclgd.godot_to_ros_vector(global_basis.inverse() * linear_velocity)
	_odom.twist.twist.linear.x = v.x
	_odom.twist.twist.angular.z = angular_velocity.y
	_odom_pub.publish(_odom)
	_tf.send_transform(pose, "base_link", "odom")  # el broadcaster convierte ejes solo
