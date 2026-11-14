// ros_tf.h — RosTfListener de ros2_vita (V13a, 2026-11-14; doc 36 §1.5 P0, sentencia W13 D3/D8).
// Misma API que el RosTfListener de rclgd (godot/rclgd/docs/classes/class_rostflistener.rst), sobre el módulo dual
// `modules/tf-tree` (impl C dentro del módulo; la variante Rust la trae el paraguas) y `modules/msg-cdr` para
// decodificar `tf2_msgs/TFMessage` SIN pasar por RosMsg ni por el esquema `.rsch`.
//
// Diferencias con rclgd (las de tf-tree, a propósito; API_PARITY.md):
//   - SIN historial: último valor por marco. `time`, `timeout_sec`, `*_full` y `fixed_frame` se aceptan y se ignoran.
//   - ≤ 32 marcos (TF_TREE_MAX_FRAMES), nombres 1..63 caracteres; ≤ 32 transformadas por TFMessage (MSG_CDR_MAX_TRANSFORMS;
//     el resto se cuenta en get_stats().descartadas).
//   - /tf y /tf_static se guardan igual (los estáticos no caducan porque nada caduca).
// Igual que rclgd: lookup_transform devuelve Transform3D en EJES DE GODOT (o null y el motivo en get_last_error()).
#pragma once

#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "ros_runtime.h"

extern "C" {
#include "msg_cdr.h"
#include "tf_tree.h"
}

class RosTfListener : public RefCounted {
	GDCLASS(RosTfListener, RefCounted);

	// Respaldo del árbol (tf_tree_create exige 8 B de alineación; uint64_t la garantiza). 3080 B (tf_tree.h).
	static constexpr size_t MEM_WORDS = 512;
	uint64_t mem[MEM_WORDS];
	tf_tree *tree = nullptr;
	msg_cdr_tf_message scratch; // ~6,7 KB: decodificación de cada TFMessage (sin malloc por mensaje)

	// Espejo de nombres y padres: tf-tree no enumera marcos (su contrato no tiene iterador) y nunca borra uno salvo
	// con clear, así que basta con anotar cada tf_tree_update aceptado. [decisión V13a: no ampliar el contrato dual]
	HashMap<String, String> padres; // marco -> padre ("" = raíz)
	HashMap<String, double> sellos; // marco -> header.stamp del último valor (s)
	Vector<String> orden; // orden de llegada (get_frame_names estable)
	String last_error;
	double cache_time = 10.0;
	uint64_t mensajes = 0, transformadas = 0, rechazadas = 0, descartadas = 0, errores = 0;

	Ref<RosSubscriber> sub_tf;
	Ref<RosSubscriber> sub_tf_static;

	static void _on_tf(void *p_ctx, const uint8_t *p_data, size_t p_len);
	void _apply(const uint8_t *p_data, size_t p_len);
	void _anotar(const String &p_padre, const String &p_hijo, double p_sello);
	int _lookup(const String &p_target, const String &p_source, Transform3D *r_t);

protected:
	static void _bind_methods();

public:
	static String normalizar(const String &p_frame); // «/odom» → «odom»; "" si no vale
	Error setup(RosNode *p_node, double p_cache_time_sec);
	// Interno y pruebas: aplica un TFMessage en CDR (sin encapsulación) como si llegara por /tf.
	void apply_cdr(const PackedByteArray &p_payload) { _apply(p_payload.ptr(), p_payload.size()); }

	// --- API de rclgd ---
	Variant lookup_transform(const String &p_target, const String &p_source, const Variant &p_time = Variant(), double p_timeout = 0.0);
	bool can_transform(const String &p_target, const String &p_source, const Variant &p_time = Variant(), double p_timeout = 0.0);
	Variant lookup_transform_full(const String &p_target, const Variant &p_target_time, const String &p_source,
			const Variant &p_source_time, const String &p_fixed, double p_timeout = 0.0);
	bool can_transform_full(const String &p_target, const Variant &p_target_time, const String &p_source,
			const Variant &p_source_time, const String &p_fixed, double p_timeout = 0.0);
	PackedStringArray get_frame_names() const;
	bool frame_exists(const String &p_frame) const;
	String get_frame_parent(const String &p_frame) const;
	double get_frame_latest_time(const String &p_frame) const;
	String all_frames_as_yaml() const;
	String get_last_error() const { return last_error; }
	void clear();
	double get_cache_time() const { return cache_time; }

	// --- extensión de ros2_vita (has_method en código común) ---
	Dictionary get_stats() const;

	RosTfListener();
};
