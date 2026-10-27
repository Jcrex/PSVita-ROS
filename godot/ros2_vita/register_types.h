// ¡ESQUELETO SIN VERIFICAR! (validar en el PC con godot-vita 3.5 y godot4-vita)
#ifndef ROS2_VITA_REGISTER_TYPES_H
#define ROS2_VITA_REGISTER_TYPES_H

#include "godot_compat.h"

#if VERSION_MAJOR >= 4
#include "modules/register_module_types.h"
void initialize_ros2_vita_module(ModuleInitializationLevel p_level);
void uninitialize_ros2_vita_module(ModuleInitializationLevel p_level);
#else
void register_ros2_vita_types();
void unregister_ros2_vita_types();
#endif

#endif
