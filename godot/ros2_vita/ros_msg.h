// ros_msg.h — RosMsg: mensaje ROS2 dinámico guiado por esquema (Godot 4.x, in-tree).
// ¡SIN COMPILAR! Equivalente en la Vita del RosMsg de rclgd (que usa ros_babel_fish):
// aquí el árbol de valores vive en Variants y el CDR se (de)codifica con
// modules/msg-schema (docs/17 §6.2). Mantiene la API pública de rclgd:
//   RosMsg.from_type("pkg/msg/T"), propiedades anidadas (msg.pose.position.x),
//   get_member/set_member, get_type_name(), get_ros_interface_name().
// Añade serialize()/deserialize() (útiles para el transporte y para las pruebas).
#pragma once

#include "core/io/file_access.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/variant/variant.h"

extern "C" {
#include "msg_schema.h"
}

class RosMsg : public RefCounted {
	GDCLASS(RosMsg, RefCounted);

	uint32_t type_idx = MSG_SCHEMA_NO_TYPE;
	String ros_name; // "geometry_msgs/msg/Twist"
	HashMap<StringName, Variant> members;

	// Esquema global (solo lectura tras cargarlo)
	static Vector<uint8_t> schema_blob;
	static msg_schema schema;
	static bool schema_loaded;

	bool _find_field(const StringName &p_name, msg_field_info &r_info) const;
	Variant _coerce(const msg_field_info &p_field, const Variant &p_value, bool &r_ok) const;
	static Variant _default_for(const msg_field_info &p_field);

protected:
	static void _bind_methods();
	bool _set(const StringName &p_name, const Variant &p_value);
	bool _get(const StringName &p_name, Variant &r_ret) const;
	void _get_property_list(List<PropertyInfo> *p_list) const;

public:
	// --- esquema ---
	static Error load_schema_bytes(const Vector<uint8_t> &p_blob);
	static Error load_schema_file(const String &p_path);
	static bool has_schema() { return schema_loaded; }
	static const msg_schema *get_schema() { return schema_loaded ? &schema : nullptr; }
	static PackedStringArray list_types();

	// --- construcción ---
	static Ref<RosMsg> from_type(const String &p_ros_type);
	void init(const String &p_ros_type);
	void init_idx(uint32_t p_type_idx); // interno: construye valores por defecto

	// --- acceso (API de rclgd) ---
	Variant get_member(const StringName &p_name) const;
	void set_member(const StringName &p_name, const Variant &p_value);
	String get_type_name() const; // nombre de la clase sombra: "RosGeometryMsgsTwist"
	String get_ros_interface_name() const { return ros_name; }
	uint32_t get_type_index() const { return type_idx; }

	// --- CDR (payload SIN encapsulación) ---
	PackedByteArray serialize() const;
	Error deserialize(const PackedByteArray &p_payload);

	String to_string() override;
};
