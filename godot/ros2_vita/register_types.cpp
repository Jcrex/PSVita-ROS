// ¡SIN COMPILAR! Godot 4.x (in-tree).
#include "register_types.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "ros_msg.h"
#include "ros_runtime.h"

static rclgd *_rclgd_singleton = nullptr;

void initialize_ros2_vita_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	// Mismos nombres que rclgd (docs/17, godot/ros2_vita/API_PARITY.md)
	GDREGISTER_CLASS(rclgd);
	GDREGISTER_CLASS(RosMsg);
	GDREGISTER_CLASS(RosQoS);
	GDREGISTER_CLASS(RosNode);
	GDREGISTER_ABSTRACT_CLASS(RosPublisher);
	GDREGISTER_ABSTRACT_CLASS(RosSubscriber);
	GDREGISTER_ABSTRACT_CLASS(RosTimer);

	_rclgd_singleton = memnew(rclgd);
	Engine::get_singleton()->add_singleton(Engine::Singleton("rclgd", rclgd::get_singleton()));
}

void uninitialize_ros2_vita_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	Engine::get_singleton()->remove_singleton("rclgd");
	if (_rclgd_singleton) {
		memdelete(_rclgd_singleton);
		_rclgd_singleton = nullptr;
	}
}
