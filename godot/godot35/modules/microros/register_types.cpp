/* register_types.cpp — crea el singleton MicroROS y lo expone a GDScript
 * (Engine.get_singleton("MicroROS")). Godot llama a estas funciones al
 * arrancar/cerrar el engine. */
#include "register_types.h"

#include "core/class_db.h"
#include "core/engine.h"

#include "micro_ros_gd.h"

static MicroROS *microros_ptr = nullptr;

void register_microros_types() {
	ClassDB::register_class<MicroROS>();
	microros_ptr = memnew(MicroROS);
	Engine::get_singleton()->add_singleton(
			Engine::Singleton("MicroROS", MicroROS::get_singleton()));
}

void unregister_microros_types() {
	if (microros_ptr) {
		memdelete(microros_ptr);
		microros_ptr = nullptr;
	}
}
