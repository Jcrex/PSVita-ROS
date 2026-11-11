// Compilado y probado en host (G1, 2026-10-29); para la Vita: compilado con verify_runtime.py PASS (G3, 2026-10-30) y validado en hardware (G4–G6, 2026-10-30). Godot 4.x (in-tree). Nombre del módulo = nombre de la carpeta.
#pragma once

#include "modules/register_module_types.h"

void initialize_ros2_vita_module(ModuleInitializationLevel p_level);
void uninitialize_ros2_vita_module(ModuleInitializationLevel p_level);
