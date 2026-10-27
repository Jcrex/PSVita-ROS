// ¡ESQUELETO SIN VERIFICAR! (validar en el PC con cada versión de Godot)
#include "register_types.h"

#include "ros_node.h"

#if VERSION_MAJOR >= 4
void initialize_ros2_vita_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(RosNode);
}

void uninitialize_ros2_vita_module(ModuleInitializationLevel p_level) {
	(void)p_level;
}
#else
void register_ros2_vita_types() {
	ClassDB::register_class<RosNode>();
}

void unregister_ros2_vita_types() {
}
#endif
