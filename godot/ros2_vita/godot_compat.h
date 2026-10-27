// godot_compat.h — ¡ESQUELETO SIN VERIFICAR! (validar en el PC con cada versión)
//
// Aísla las diferencias de API entre Godot 3.5 (godot-vita) y 4.x (godot4-vita)
// que afectan a este módulo. Lista basada en el conocimiento de la API de
// Godot 3→4 (docs/12 §3, ADR 0008); NINGUNA se ha compilado todavía.
//
//   Concepto                3.5                          4.x
//   ------------------------------------------------------------------------
//   include de ClassDB      core/class_db.h              core/object/class_db.h
//   array de bytes          PoolByteArray                PackedByteArray
//   tipo Variant            Variant::POOL_BYTE_ARRAY     Variant::PACKED_BYTE_ARRAY
//   acceso de escritura     arr.write().ptr()            arr.ptrw()
//   registro del módulo     register_X_types()           initialize_X_module(level)
//   registrar clase         ClassDB::register_class<T>() GDREGISTER_CLASS(T)
#ifndef ROS2_VITA_GODOT_COMPAT_H
#define ROS2_VITA_GODOT_COMPAT_H

#include "core/version.h" // define VERSION_MAJOR / VERSION_MINOR en 3.x y 4.x

#if VERSION_MAJOR >= 4
#include "core/object/class_db.h"
typedef PackedByteArray RosBytes;
#define ROS_VARIANT_BYTES Variant::PACKED_BYTE_ARRAY
#define ROS_BYTES_PTRW(arr) ((arr).ptrw())
#else
#include "core/class_db.h"
typedef PoolByteArray RosBytes;
#define ROS_VARIANT_BYTES Variant::POOL_BYTE_ARRAY
// En 3.x hay que mantener vivo el objeto `Write` mientras se escribe.
#define ROS_BYTES_WRITE_BEGIN(arr) PoolByteArray::Write ros_w_ = (arr).write();
#define ROS_BYTES_PTRW(arr) (ros_w_.ptr())
#endif

#endif
