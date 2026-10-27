// ¡ESQUELETO SIN VERIFICAR! (Godot 3.x; validar en el PC)
// En Godot 4 esto cambia a initialize_ros2_vita_module(ModuleInitializationLevel).
#include "register_types.h"

#include "core/class_db.h"
#include "ros_node.h"

void register_ros2_vita_types() {
	ClassDB::register_class<RosNode>();
}

void unregister_ros2_vita_types() {
}
