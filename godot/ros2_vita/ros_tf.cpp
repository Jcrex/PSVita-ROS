// ros_tf.cpp — RosTfListener sobre modules/tf-tree + modules/msg-cdr (V13a, 2026-11-14). Ver ros_tf.h.
// Compilado y probado en host (godot/test/project/runner.gd). En la Vita: compila y pasa verify_runtime.py;
// VALIDAR EN HARDWARE el tamaño de /tf real por XRCE (fiable fragmentado, MAX_RX 16 KB en xrce_transport.cpp) y el
// coste de lookup por fotograma (README de tf-tree).
#include "ros_tf.h"

#include "core/object/class_db.h"

#include <string.h>

namespace {

// Columnas = ejes X, Y, Z de ROS en Godot (= rclgd ros_to_godot_vector, TfLigero.C y PrimitivasViz.C).
const Basis C_ROS_A_GODOT(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0));

String _mensaje_estado(int p_rc, const String &p_target, const String &p_source, bool p_target_ok) {
	switch (p_rc) {
		case TF_TREE_ERR_INVALID_ARG:
			return "RosTfListener: nombre de marco no valido";
		case TF_TREE_ERR_UNKNOWN_FRAME:
			return vformat("RosTfListener: marco desconocido \"%s\"", p_target_ok ? p_source : p_target);
		case TF_TREE_ERR_NO_PATH:
			return vformat("RosTfListener: %s y %s no estan conectados", p_target, p_source);
		default:
			return vformat("RosTfListener: error %d", p_rc);
	}
}

} // namespace

RosTfListener::RosTfListener() {
	static_assert(sizeof(mem) >= 3080, "tf_tree necesita 3080 B (tf_tree.h)");
	tree = tf_tree_create(mem, sizeof(mem));
	memset(&scratch, 0, sizeof(scratch));
}

String RosTfListener::normalizar(const String &p_frame) {
	String n = p_frame.begins_with("/") ? p_frame.substr(1) : p_frame;
	if (n.is_empty() || n.utf8().length() >= TF_TREE_NAME_MAX) {
		return String();
	}
	return n;
}

Error RosTfListener::setup(RosNode *p_node, double p_cache_time_sec) {
	ERR_FAIL_NULL_V_MSG(tree, ERR_BUG, "RosTfListener: tf_tree_create fallo (tamano o alineacion).");
	ERR_FAIL_NULL_V(p_node, ERR_INVALID_PARAMETER);
	cache_time = p_cache_time_sec > 0.0 ? p_cache_time_sec : 10.0; // como rclgd (tf2): solo informativo aquí
	// QoS de tf2_ros (DynamicListenerQoS / StaticListenerQoS): fiables, profundidad 100; /tf_static transient local.
	// En XRCE, fiable es además lo único que admite mensajes > ~490 B (fragmentados).
	Ref<RosQoS> q_tf;
	q_tf.instantiate();
	q_tf->set_depth(100);
	Ref<RosQoS> q_static;
	q_static.instantiate();
	q_static->set_depth(100);
	q_static->set_durability(RosQoS::TRANSIENT_LOCAL);
	sub_tf = p_node->create_subscription_raw("/tf", "tf2_msgs/msg/TFMessage", &RosTfListener::_on_tf, this, q_tf);
	sub_tf_static = p_node->create_subscription_raw("/tf_static", "tf2_msgs/msg/TFMessage", &RosTfListener::_on_tf, this, q_static);
	ERR_FAIL_COND_V_MSG(sub_tf.is_null() || sub_tf_static.is_null(), ERR_CANT_CREATE, "RosTfListener: no se pudo suscribir a /tf o /tf_static.");
	return OK;
}

void RosTfListener::_on_tf(void *p_ctx, const uint8_t *p_data, size_t p_len) {
	// El RosSubscriber lo guarda este mismo objeto: si el listener muere, la suscripción muere antes de llamar aquí.
	((RosTfListener *)p_ctx)->_apply(p_data, p_len);
}

void RosTfListener::_anotar(const String &p_padre, const String &p_hijo, double p_sello) {
	if (!padres.has(p_padre)) {
		padres[p_padre] = String();
		orden.push_back(p_padre);
	}
	if (!padres.has(p_hijo)) {
		orden.push_back(p_hijo);
	}
	padres[p_hijo] = p_padre;
	sellos[p_hijo] = p_sello;
}

void RosTfListener::_apply(const uint8_t *p_data, size_t p_len) {
	static const uint8_t vacio = 0;
	int rc = msg_cdr_decode_tf_message(p_len ? p_data : &vacio, p_len, &scratch);
	if (rc != MSG_CDR_OK && rc != MSG_CDR_ERR_CAPACITY) {
		errores++;
		return;
	}
	mensajes++;
	descartadas += scratch.dropped; // > 32 transformadas en un mensaje
	// Como tf_tree_apply_message, pero transformada a transformada para llevar el espejo de nombres.
	for (uint32_t i = 0; i < scratch.count; i++) {
		const msg_cdr_transform &it = scratch.items[i];
		vizm_vec3 t = { (float)it.translation[0], (float)it.translation[1], (float)it.translation[2] };
		vizm_quat q = { (float)it.rotation[0], (float)it.rotation[1], (float)it.rotation[2], (float)it.rotation[3] };
		bool finito = true;
		for (int k = 0; k < 3; k++) {
			finito = finito && Math::is_finite(it.translation[k]);
		}
		for (int k = 0; k < 4; k++) {
			finito = finito && Math::is_finite(it.rotation[k]);
		}
		if (!finito || tf_tree_update(tree, it.frame_id, it.child_frame_id, &t, &q) != TF_TREE_OK) {
			rechazadas++; // nombre no válido, ciclo, árbol lleno o NaN/Inf (como TfLigero, T2)
			continue;
		}
		transformadas++;
		_anotar(normalizar(String::utf8(it.frame_id)), normalizar(String::utf8(it.child_frame_id)),
				(double)it.stamp.sec + (double)it.stamp.nanosec * 1e-9);
	}
}

int RosTfListener::_lookup(const String &p_target, const String &p_source, Transform3D *r_t) {
	String tn = normalizar(p_target);
	String sn = normalizar(p_source);
	int rc = TF_TREE_OK;
	vizm_mat4 m;
	if (tn.is_empty() || sn.is_empty()) {
		rc = TF_TREE_ERR_INVALID_ARG;
	} else {
		CharString tc = tn.utf8();
		CharString sc = sn.utf8();
		rc = tf_tree_lookup(tree, tc.get_data(), sc.get_data(), &m);
	}
	if (rc != TF_TREE_OK) {
		last_error = _mensaje_estado(rc, tn.is_empty() ? p_target : tn, sn.is_empty() ? p_source : sn, padres.has(tn));
		return rc;
	}
	last_error = String();
	if (r_t) {
		// M (ROS, column-major de viz-math): p_target = R·p_source + t. En Godot: C·R·Cᵀ y C·t (como rclgd y TfLigero).
		Basis r(Vector3(m.m[0], m.m[1], m.m[2]), Vector3(m.m[4], m.m[5], m.m[6]), Vector3(m.m[8], m.m[9], m.m[10]));
		Vector3 t(m.m[12], m.m[13], m.m[14]);
		*r_t = Transform3D(C_ROS_A_GODOT * r * C_ROS_A_GODOT.transposed(), C_ROS_A_GODOT.xform(t));
	}
	return rc;
}

Variant RosTfListener::lookup_transform(const String &p_target, const String &p_source, const Variant &, double) {
	Transform3D t;
	if (_lookup(p_target, p_source, &t) != TF_TREE_OK) {
		return Variant(); // null, como rclgd: distingue el fallo de una identidad real
	}
	return t;
}

bool RosTfListener::can_transform(const String &p_target, const String &p_source, const Variant &, double) {
	return _lookup(p_target, p_source, nullptr) == TF_TREE_OK;
}

Variant RosTfListener::lookup_transform_full(const String &p_target, const Variant &, const String &p_source,
		const Variant &, const String &, double) {
	return lookup_transform(p_target, p_source); // sin historial: los dos instantes son «ahora»
}

bool RosTfListener::can_transform_full(const String &p_target, const Variant &, const String &p_source,
		const Variant &, const String &, double) {
	return can_transform(p_target, p_source);
}

PackedStringArray RosTfListener::get_frame_names() const {
	PackedStringArray out;
	for (const String &f : orden) {
		out.push_back(f);
	}
	return out;
}

bool RosTfListener::frame_exists(const String &p_frame) const {
	return padres.has(normalizar(p_frame));
}

String RosTfListener::get_frame_parent(const String &p_frame) const {
	const String *p = padres.getptr(normalizar(p_frame));
	return p ? *p : String();
}

double RosTfListener::get_frame_latest_time(const String &p_frame) const {
	const double *s = sellos.getptr(normalizar(p_frame));
	return s ? *s : 0.0;
}

String RosTfListener::all_frames_as_yaml() const {
	// Subconjunto del volcado de tf2 (solo padre y último sello: no hay historial ni autoridad).
	String y;
	for (const String &f : orden) {
		const String &p = padres[f];
		if (p.is_empty()) {
			continue; // tf2 solo lista los marcos con padre
		}
		y += vformat("%s: \n  parent: '%s'\n  most_recent_transform: %f\n", f, p, get_frame_latest_time(f));
	}
	return y;
}

void RosTfListener::clear() {
	// Como rclgd: se tiran las transformadas pero los NOMBRES siguen registrados (get_frame_names/frame_exists);
	// para olvidarlos, crear otro listener. tf-tree se vacía entero.
	tf_tree_clear(tree);
	for (KeyValue<String, String> &kv : padres) {
		kv.value = String();
	}
	sellos.clear();
}

Dictionary RosTfListener::get_stats() const {
	Dictionary d;
	d["mensajes"] = (int64_t)mensajes; // TFMessage aplicados
	d["transformadas"] = (int64_t)transformadas; // aceptadas por tf-tree
	d["rechazadas"] = (int64_t)rechazadas; // nombre no válido, ciclo, árbol lleno o NaN
	d["descartadas"] = (int64_t)descartadas; // > 32 por mensaje (msg-cdr)
	d["errores"] = (int64_t)errores; // CDR inválido
	d["marcos"] = (int64_t)tf_tree_frame_count(tree);
	return d;
}

void RosTfListener::_bind_methods() {
	ClassDB::bind_method(D_METHOD("lookup_transform", "target_frame", "source_frame", "time", "timeout_sec"),
			&RosTfListener::lookup_transform, DEFVAL(Variant()), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("can_transform", "target_frame", "source_frame", "time", "timeout_sec"),
			&RosTfListener::can_transform, DEFVAL(Variant()), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("lookup_transform_full", "target_frame", "target_time", "source_frame", "source_time",
								 "fixed_frame", "timeout_sec"),
			&RosTfListener::lookup_transform_full, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("can_transform_full", "target_frame", "target_time", "source_frame", "source_time",
								 "fixed_frame", "timeout_sec"),
			&RosTfListener::can_transform_full, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("get_frame_names"), &RosTfListener::get_frame_names);
	ClassDB::bind_method(D_METHOD("frame_exists", "frame"), &RosTfListener::frame_exists);
	ClassDB::bind_method(D_METHOD("get_frame_parent", "frame"), &RosTfListener::get_frame_parent);
	ClassDB::bind_method(D_METHOD("get_frame_latest_time", "frame"), &RosTfListener::get_frame_latest_time);
	ClassDB::bind_method(D_METHOD("all_frames_as_yaml"), &RosTfListener::all_frames_as_yaml);
	ClassDB::bind_method(D_METHOD("get_last_error"), &RosTfListener::get_last_error);
	ClassDB::bind_method(D_METHOD("clear"), &RosTfListener::clear);
	ClassDB::bind_method(D_METHOD("get_cache_time"), &RosTfListener::get_cache_time);
	// Extensiones de ros2_vita
	ClassDB::bind_method(D_METHOD("get_stats"), &RosTfListener::get_stats);
	ClassDB::bind_method(D_METHOD("apply_cdr", "payload"), &RosTfListener::apply_cdr);
}
