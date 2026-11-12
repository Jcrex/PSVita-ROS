extends Node

var contexto: RefCounted
var robot: Node3D
var topic := "/joint_trajectory_controller/joint_trajectory"
var _sub: RosSubscriber


func _ready() -> void:
	if contexto == null or contexto.nodo == null:
		return
	_sub = contexto.suscripcion(topic, "trajectory_msgs/msg/JointTrajectory", _on_trajectory, false)


func _on_trajectory(msg) -> void:
	if msg.points.is_empty() or not robot.has_method("fijar_objetivos_joints"):
		return
	var punto = msg.points[msg.points.size() - 1]
	robot.call("fijar_objetivos_joints", msg.joint_names, punto.positions)
