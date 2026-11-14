// ros_runtime.cpp — Godot 4.x in-tree. V13a (2026-11-14): ver la cabecera de ros_runtime.h. Compilado y probado en host (G1, 2026-10-29); corre en la Vita en loopback (G4,
// 2026-10-30). El transporte XRCE vive en xrce_transport.cpp (G5).
#include "ros_runtime.h"

#include "core/config/project_settings.h"
#include "core/object/class_db.h"
#include "core/object/script_language.h"
#include "core/os/os.h"
#include "scene/main/scene_tree.h"

#ifdef ROS2_VITA_XRCE
#include "xrce_transport.h"
#endif

rclgd *rclgd::singleton = nullptr;

// ============================================================ transportes
namespace {

class LoopbackTransport : public RosTransport {
	struct Endpoint {
		String topic;
		String type;
	};
	HashMap<int, Endpoint> pubs;
	HashMap<int, Endpoint> subs;
	int next_id = 1;

public:
	Error start(const Dictionary &) override { return OK; }
	void stop() override {
		pubs.clear();
		subs.clear();
	}
	int advertise(const String &t, const String &ty, const Ref<RosQoS> &) override {
		pubs[next_id] = { t, ty };
		return next_id++;
	}
	int subscribe(const String &t, const String &ty, const Ref<RosQoS> &) override {
		subs[next_id] = { t, ty };
		return next_id++;
	}
	void unadvertise(int id) override { pubs.erase(id); }
	void unsubscribe(int id) override { subs.erase(id); }
	Error publish(int id, const uint8_t *data, size_t len) override {
		const Endpoint *p = pubs.getptr(id);
		ERR_FAIL_NULL_V(p, ERR_DOES_NOT_EXIST);
		for (const KeyValue<int, Endpoint> &kv : subs) {
			if (kv.value.topic == p->topic && kv.value.type == p->type && rx) {
				rx(rx_ctx, kv.key, data, len);
			}
		}
		return OK;
	}
};

#ifndef ROS2_VITA_XRCE
// Compilado sin las libs XRCE (SCsub no las encontró): el transporte xrce no está disponible.
// Se construyen con tools/build-xrce-client-vita.sh (XRCE_PIC=1 Vita, XRCE_HOST=1 host).
class XrceUnavailable : public RosTransport {
public:
	Error start(const Dictionary &) override {
		ERR_FAIL_V_MSG(ERR_UNAVAILABLE, "ros2_vita: compilado sin XRCE (faltan las libs; ver godot/README.md).");
	}
	void stop() override {}
	int advertise(const String &, const String &, const Ref<RosQoS> &) override { return -1; }
	int subscribe(const String &, const String &, const Ref<RosQoS> &) override { return -1; }
	void unadvertise(int) override {}
	void unsubscribe(int) override {}
	Error publish(int, const uint8_t *, size_t) override { return ERR_UNAVAILABLE; }
};
#endif

} // namespace

// ================================================================== RosQoS
void RosQoS::_bind_methods() {
	// V13a: setters/getters con propiedades, como rclgd (godot/rclgd/rclgd/src/rclgd/ros_qos.cpp): así
	// `qos.reliability = RosQoS.BEST_EFFORT` funciona igual en el PC y en la Vita. Los set_*() se mantienen.
	ClassDB::bind_method(D_METHOD("set_history", "v"), &RosQoS::set_history);
	ClassDB::bind_method(D_METHOD("get_history"), &RosQoS::get_history);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "history", PROPERTY_HINT_ENUM, "Keep Last,Keep All"), "set_history", "get_history");
	ClassDB::bind_method(D_METHOD("set_depth", "v"), &RosQoS::set_depth);
	ClassDB::bind_method(D_METHOD("get_depth"), &RosQoS::get_depth);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "depth"), "set_depth", "get_depth");
	ClassDB::bind_method(D_METHOD("set_reliability", "v"), &RosQoS::set_reliability);
	ClassDB::bind_method(D_METHOD("get_reliability"), &RosQoS::get_reliability);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "reliability", PROPERTY_HINT_ENUM, "Reliable,Best Effort"), "set_reliability", "get_reliability");
	ClassDB::bind_method(D_METHOD("set_durability", "v"), &RosQoS::set_durability);
	ClassDB::bind_method(D_METHOD("get_durability"), &RosQoS::get_durability);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "durability", PROPERTY_HINT_ENUM, "Volatile,Transient Local"), "set_durability", "get_durability");
	// Guardadas pero ignoradas por XRCE (API_PARITY.md):
	ClassDB::bind_method(D_METHOD("set_deadline", "v"), &RosQoS::set_deadline);
	ClassDB::bind_method(D_METHOD("get_deadline"), &RosQoS::get_deadline);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "deadline_seconds"), "set_deadline", "get_deadline");
	ClassDB::bind_method(D_METHOD("set_lifespan", "v"), &RosQoS::set_lifespan);
	ClassDB::bind_method(D_METHOD("get_lifespan"), &RosQoS::get_lifespan);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "lifespan_seconds"), "set_lifespan", "get_lifespan");
	ClassDB::bind_method(D_METHOD("set_liveliness", "v"), &RosQoS::set_liveliness);
	ClassDB::bind_method(D_METHOD("get_liveliness"), &RosQoS::get_liveliness);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "liveliness", PROPERTY_HINT_ENUM, "Automatic,Manual By Topic,System Default"), "set_liveliness", "get_liveliness");
	ClassDB::bind_method(D_METHOD("set_lease_duration", "v"), &RosQoS::set_lease_duration);
	ClassDB::bind_method(D_METHOD("get_lease_duration"), &RosQoS::get_lease_duration);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "lease_duration_seconds"), "set_lease_duration", "get_lease_duration");
	BIND_ENUM_CONSTANT(RELIABLE);
	BIND_ENUM_CONSTANT(BEST_EFFORT);
	BIND_ENUM_CONSTANT(VOLATILE);
	BIND_ENUM_CONSTANT(TRANSIENT_LOCAL);
	BIND_ENUM_CONSTANT(KEEP_LAST);
	BIND_ENUM_CONSTANT(KEEP_ALL);
	BIND_ENUM_CONSTANT(AUTOMATIC);
	BIND_ENUM_CONSTANT(MANUAL_BY_TOPIC);
	BIND_ENUM_CONSTANT(SYSTEM_DEFAULT);
}

// ============================================================ Pub/Sub/Timer
void RosPublisher::_bind_methods() {
	ClassDB::bind_method(D_METHOD("publish", "msg"), &RosPublisher::publish);
}

void RosPublisher::publish(const Ref<RosMsg> &p_msg) {
	rclgd *r = rclgd::get_singleton();
	ERR_FAIL_NULL_MSG(r, "RosPublisher: rclgd no inicializado.");
	ERR_FAIL_COND_MSG(!r->ok() || pub_id < 0 || session != r->get_session(), "RosPublisher: contexto ROS no activo.");
	ERR_FAIL_COND_MSG(p_msg.is_null(), "RosPublisher: mensaje nulo.");
	ERR_FAIL_COND_MSG(p_msg->get_ros_interface_name() != type_name,
			vformat("RosPublisher: se esperaba %s y llego %s.", type_name, p_msg->get_ros_interface_name()));
	PackedByteArray bytes = p_msg->serialize();
	ERR_FAIL_COND(bytes.is_empty());
	r->get_transport()->publish(pub_id, bytes.ptr(), bytes.size());
}

RosPublisher::~RosPublisher() {
	rclgd *r = rclgd::get_singleton();
	// V13a: solo en SU sesión. Antes, un publicador liberado tras shutdown()+init() borraba el id reutilizado de otro.
	if (r && r->get_transport() && pub_id >= 0 && session == r->get_session()) {
		r->get_transport()->unadvertise(pub_id);
	}
}

void RosSubscriber::_bind_methods() {
	// Extensiones de ros2_vita (V13a; rclgd no las tiene: comprobar con has_method en código común).
	ClassDB::bind_method(D_METHOD("set_latest_only", "enabled"), &RosSubscriber::set_latest_only);
	ClassDB::bind_method(D_METHOD("is_latest_only"), &RosSubscriber::is_latest_only);
	ClassDB::bind_method(D_METHOD("get_stats"), &RosSubscriber::get_stats);
}

void RosSubscriber::deliver(const uint8_t *p_data, size_t p_len) {
	if (raw) { // consumidor nativo: bytes tal cual (RosTfListener)
		raw(raw_ctx, p_data, p_len);
		decodificados++;
		return;
	}
	if (!callback.is_valid()) {
		return;
	}
	// V13a: el tipo se resolvió al suscribir (antes, RosMsg::from_type buscaba el nombre en CADA mensaje y además
	// construía un árbol por defecto que deserialize() tiraba).
	Error err = OK;
	Ref<RosMsg> msg = RosMsg::decode_new(type_idx, p_data, p_len, &err);
	if (msg.is_null()) {
		errores++;
		if (errores == 1 || (errores % 100) == 0) { // sin inundar la consola (un aviso y luego cada 100)
			WARN_PRINT(vformat("RosSubscriber: CDR invalido para %s (%d errores).", type_name, (int64_t)errores));
		}
		return;
	}
	decodificados++;
	callback.call(msg);
}

bool RosSubscriber::_vigente() const {
	rclgd *r = rclgd::get_singleton();
	return r && r->ok() && sub_id >= 0 && session == r->get_session();
}

void RosSubscriber::set_latest_only(bool p_v) {
	rclgd *r = rclgd::get_singleton();
	if (_vigente()) {
		r->set_latest_only(sub_id, p_v);
	}
}

bool RosSubscriber::is_latest_only() const {
	return _vigente() && rclgd::get_singleton()->is_latest_only(sub_id);
}

Dictionary RosSubscriber::get_stats() const {
	uint64_t rec = 0, desc = 0;
	if (_vigente()) {
		rclgd::get_singleton()->get_sub_counters(sub_id, rec, desc);
	}
	Dictionary d;
	d["recibidos"] = (int64_t)rec; // llegados del transporte
	d["descartados"] = (int64_t)desc; // sin decodificar: latest_only o cola llena
	d["decodificados"] = (int64_t)decodificados; // entregados al callback (o al consumidor nativo)
	d["errores"] = (int64_t)errores; // CDR inválido
	d["latest_only"] = is_latest_only();
	d["tipo"] = type_name;
	return d;
}

RosSubscriber::~RosSubscriber() {
	rclgd *r = rclgd::get_singleton();
	if (_vigente()) { // V13a: ver ~RosPublisher
		r->unregister_subscription(sub_id);
		if (r->get_transport()) {
			r->get_transport()->unsubscribe(sub_id);
		}
	}
}

void RosTimer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("cancel"), &RosTimer::cancel);
	ClassDB::bind_method(D_METHOD("reset"), &RosTimer::reset);
	ClassDB::bind_method(D_METHOD("is_canceled"), &RosTimer::is_canceled);
	ClassDB::bind_method(D_METHOD("is_ready"), &RosTimer::is_ready);
	ClassDB::bind_method(D_METHOD("get_remaining_time"), &RosTimer::get_remaining_time);
}

void RosTimer::setup(double p_seconds, const Callable &p_cb) {
	period_us = (uint64_t)(p_seconds * 1000000.0);
	callback = p_cb;
	reset();
}

void RosTimer::reset() {
	canceled = false;
	next_us = OS::get_singleton()->get_ticks_usec() + period_us;
}

bool RosTimer::is_ready() const {
	return !canceled && OS::get_singleton()->get_ticks_usec() >= next_us;
}

double RosTimer::get_remaining_time() const {
	uint64_t now = OS::get_singleton()->get_ticks_usec();
	return now >= next_us ? 0.0 : (double)(next_us - now) / 1000000.0;
}

void RosTimer::tick(uint64_t p_now_us) {
	if (canceled || p_now_us < next_us || !callback.is_valid()) {
		return;
	}
	next_us += period_us; // sin acumular deriva
	if (next_us <= p_now_us) {
		next_us = p_now_us + period_us; // tras un parón largo, no disparar en ráfaga
	}
	callback.call();
}

// ==================================================================== RosNode
void RosNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("init", "node_name", "namespace"), &RosNode::init, DEFVAL(""));
	ClassDB::bind_method(D_METHOD("get_name"), &RosNode::get_name);
	ClassDB::bind_method(D_METHOD("get_namespace"), &RosNode::get_namespace);
	ClassDB::bind_method(D_METHOD("resolve_frame", "frame_id"), &RosNode::resolve_frame);
	ClassDB::bind_method(D_METHOD("create_publisher", "topic", "type", "qos"), &RosNode::create_publisher, DEFVAL(Ref<RosQoS>()));
	ClassDB::bind_method(D_METHOD("create_subscription", "topic", "type", "callback", "qos"), &RosNode::create_subscription, DEFVAL(Ref<RosQoS>()));
	ClassDB::bind_method(D_METHOD("create_timer", "seconds", "callback"), &RosNode::create_timer);
	ClassDB::bind_method(D_METHOD("now"), &RosNode::now);
	ClassDB::bind_method(D_METHOD("declare_parameter", "name", "default_value"), &RosNode::declare_parameter);
	ClassDB::bind_method(D_METHOD("set_parameter", "name", "value"), &RosNode::set_parameter);
	ClassDB::bind_method(D_METHOD("get_parameter", "name"), &RosNode::get_parameter);
	ADD_SIGNAL(MethodInfo("parameter_changed", PropertyInfo(Variant::STRING, "name"), PropertyInfo(Variant::NIL, "value", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NIL_IS_VARIANT)));
}

void RosNode::init(const String &p_name, const String &p_namespace) {
	ERR_FAIL_COND_MSG(!node_name.is_empty(), "RosNode: ya inicializado.");
	ERR_FAIL_COND_MSG(p_name.is_empty() || p_name.contains("/"), "RosNode: nombre de nodo invalido.");
	node_name = p_name;
	String ns = p_namespace.strip_edges();
	if (ns.is_empty() || ns == "/") {
		node_ns = "/";
	} else {
		node_ns = (ns.begins_with("/") ? ns : "/" + ns).rstrip("/");
	}
}

String RosNode::_resolve_topic(const String &p_topic) const {
	if (p_topic.begins_with("/")) {
		return p_topic;
	}
	String base = node_ns == "/" ? String() : node_ns;
	if (p_topic.begins_with("~")) { // "~/marker" -> "/<ns>/<nodo>/marker"
		return base + "/" + node_name + p_topic.substr(1);
	}
	return base + "/" + p_topic;
}

String RosNode::resolve_frame(const String &p_id) const {
	String s = p_id;
	if (s.begins_with("~")) {
		s = node_ns + "/" + s.substr(1);
	}
	while (s.begins_with("/")) { // TF no admite "/" inicial
		s = s.substr(1);
	}
	return s;
}

String RosNode::_type_from_variant(const Variant &p_type) {
	if (p_type.get_type() == Variant::STRING) {
		return p_type;
	}
	if (p_type.get_type() == Variant::OBJECT) { // clase sombra con ROS_TYPE_NAME
		Ref<Script> scr = p_type;
		if (scr.is_valid()) {
			Dictionary consts = scr->call(SNAME("get_script_constant_map"));
			if (consts.has("ROS_TYPE_NAME")) {
				return consts["ROS_TYPE_NAME"];
			}
		}
	}
	return String();
}

Ref<RosPublisher> RosNode::create_publisher(const String &p_topic, const Variant &p_type, const Ref<RosQoS> &p_qos) {
	rclgd *r = rclgd::get_singleton();
	ERR_FAIL_COND_V_MSG(!r || !r->ok(), Ref<RosPublisher>(), "RosNode: rclgd.init() primero.");
	ERR_FAIL_COND_V_MSG(node_name.is_empty(), Ref<RosPublisher>(), "RosNode: llama a init().");
	String type = _type_from_variant(p_type);
	ERR_FAIL_COND_V_MSG(type.is_empty(), Ref<RosPublisher>(), "RosNode: no se pudo resolver el tipo ROS.");
	int id = r->get_transport()->advertise(_resolve_topic(p_topic), type, p_qos);
	ERR_FAIL_COND_V_MSG(id < 0, Ref<RosPublisher>(), "RosNode: el transporte rechazo el publisher.");
	Ref<RosPublisher> pub;
	pub.instantiate();
	pub->setup(id, type);
	pub->set_session(r->get_session());
	return pub;
}

Ref<RosSubscriber> RosNode::create_subscription(const String &p_topic, const Variant &p_type, const Callable &p_cb, const Ref<RosQoS> &p_qos) {
	rclgd *r = rclgd::get_singleton();
	ERR_FAIL_COND_V_MSG(!r || !r->ok(), Ref<RosSubscriber>(), "RosNode: rclgd.init() primero.");
	ERR_FAIL_COND_V_MSG(node_name.is_empty(), Ref<RosSubscriber>(), "RosNode: llama a init().");
	String type = _type_from_variant(p_type);
	ERR_FAIL_COND_V_MSG(type.is_empty(), Ref<RosSubscriber>(), "RosNode: no se pudo resolver el tipo ROS.");
	// V13a: el tipo se resuelve UNA vez aquí. Antes la suscripción se creaba igual y cada muestra fallaba en
	// RosMsg.from_type sin que el callback llegara nunca (doc 36 §1.2). Ahora no se suscribe (no se gasta red en
	// la Vita) y se dice por qué. [decisión V13a: null, como pide la regla de doc 36 §2.9.2]
	uint32_t idx = RosMsg::find_type_index(type);
	ERR_FAIL_COND_V_MSG(idx == MSG_SCHEMA_NO_TYPE, Ref<RosSubscriber>(),
			vformat("RosNode: el tipo '%s' de '%s' no esta en el esquema .rsch cargado (%s); no se suscribe. "
					"Anadelo a TIPOS y regenera el esquema (tools/gen_msg_schema.py).",
					type, p_topic, RosMsg::has_schema() ? "falta el tipo" : "no hay esquema"));
	int id = r->get_transport()->subscribe(_resolve_topic(p_topic), type, p_qos);
	ERR_FAIL_COND_V_MSG(id < 0, Ref<RosSubscriber>(), "RosNode: el transporte rechazo la suscripcion.");
	Ref<RosSubscriber> sub;
	sub.instantiate();
	sub->setup(id, type, idx, p_cb);
	sub->set_session(r->get_session());
	r->register_subscription(id, sub->get_instance_id());
	return sub;
}

Ref<RosSubscriber> RosNode::create_subscription_raw(const String &p_topic, const String &p_type, RosSubscriber::RawHandler p_fn,
		void *p_ctx, const Ref<RosQoS> &p_qos) {
	rclgd *r = rclgd::get_singleton();
	ERR_FAIL_COND_V_MSG(!r || !r->ok(), Ref<RosSubscriber>(), "RosNode: rclgd.init() primero.");
	ERR_FAIL_COND_V_MSG(node_name.is_empty(), Ref<RosSubscriber>(), "RosNode: llama a init().");
	int id = r->get_transport()->subscribe(_resolve_topic(p_topic), p_type, p_qos);
	ERR_FAIL_COND_V_MSG(id < 0, Ref<RosSubscriber>(), "RosNode: el transporte rechazo la suscripcion.");
	Ref<RosSubscriber> sub;
	sub.instantiate();
	sub->setup_raw(id, p_type, p_fn, p_ctx);
	sub->set_session(r->get_session());
	r->register_subscription(id, sub->get_instance_id());
	return sub;
}

Ref<RosTimer> RosNode::create_timer(double p_seconds, const Callable &p_cb) {
	rclgd *r = rclgd::get_singleton();
	ERR_FAIL_COND_V_MSG(!r || !r->ok(), Ref<RosTimer>(), "RosNode: rclgd.init() primero.");
	ERR_FAIL_COND_V_MSG(p_seconds <= 0.0, Ref<RosTimer>(), "RosNode: periodo del timer invalido.");
	Ref<RosTimer> t;
	t.instantiate();
	t->setup(p_seconds, p_cb);
	r->register_timer(t->get_instance_id());
	return t;
}

Ref<RosMsg> RosNode::now() {
	Ref<RosMsg> t = RosMsg::from_type("builtin_interfaces/msg/Time");
	ERR_FAIL_COND_V_MSG(t.is_null(), t, "RosNode: el esquema no incluye builtin_interfaces/msg/Time.");
	// Con XRCE, la hora del agente (sincronizada al abrir la sesión): el reloj de la Vita puede ir minutos
	// por detrás del PC y tf2 descartaría los mensajes por «extrapolation». Si no, el reloj local.
	rclgd *r = rclgd::get_singleton();
	int64_t ns = 0;
	if (r && r->get_transport() && r->get_transport()->epoch_ns(&ns) && ns > 0) {
		t->set_member("sec", (int64_t)(ns / 1000000000));
		t->set_member("nanosec", (int64_t)(ns % 1000000000));
		return t;
	}
	double unix_s = OS::get_singleton()->get_unix_time();
	int64_t sec = (int64_t)unix_s;
	t->set_member("sec", sec);
	t->set_member("nanosec", (int64_t)((unix_s - (double)sec) * 1e9));
	return t;
}

void RosNode::declare_parameter(const String &p_name, const Variant &p_default) {
	if (params.has(p_name)) {
		ERR_FAIL_MSG(vformat("RosNode: parametro '%s' ya declarado.", p_name));
	}
	Variant v = p_default;
	rclgd *r = rclgd::get_singleton();
	if (r) { // -p nodo.nombre:=valor o -p nombre:=valor (gana el de la línea de órdenes)
		Dictionary ov = r->get_overrides();
		String key = node_name + "." + p_name;
		Variant raw = ov.has(key) ? ov[key] : (ov.has(p_name) ? ov[p_name] : Variant());
		if (raw.get_type() != Variant::NIL) {
			String s = raw;
			switch (p_default.get_type()) {
				case Variant::BOOL: v = (s.to_lower() == "true" || s == "1"); break;
				case Variant::INT: v = s.to_int(); break;
				case Variant::FLOAT: v = s.to_float(); break;
				default: v = s; break;
			}
		}
	}
	params[p_name] = v;
}

void RosNode::set_parameter(const String &p_name, const Variant &p_value) {
	ERR_FAIL_COND_MSG(!params.has(p_name), vformat("RosNode: parametro '%s' no declarado.", p_name));
	params[p_name] = p_value;
	emit_signal(SNAME("parameter_changed"), p_name, p_value);
}

Variant RosNode::get_parameter(const String &p_name) {
	return params.has(p_name) ? params[p_name] : Variant();
}

// ================================================================= singleton
rclgd::rclgd() {
	singleton = this;
}

rclgd::~rclgd() {
	shutdown();
	singleton = nullptr;
}

void rclgd::_bind_methods() {
	ClassDB::bind_method(D_METHOD("init", "args"), &rclgd::init, DEFVAL(PackedStringArray()));
	ClassDB::bind_method(D_METHOD("shutdown"), &rclgd::shutdown);
	ClassDB::bind_method(D_METHOD("ok"), &rclgd::ok);
	ClassDB::bind_method(D_METHOD("get_dropped"), &rclgd::get_dropped);
	ClassDB::bind_method(D_METHOD("get_transport_info"), &rclgd::get_transport_info);
	ClassDB::bind_method(D_METHOD("godot_to_ros_vector", "v"), &rclgd::godot_to_ros_vector);
	ClassDB::bind_method(D_METHOD("ros_to_godot_vector", "v"), &rclgd::ros_to_godot_vector);
	ClassDB::bind_method(D_METHOD("godot_to_ros_quat", "q"), &rclgd::godot_to_ros_quat);
	ClassDB::bind_method(D_METHOD("ros_to_godot_quat", "q"), &rclgd::ros_to_godot_quat);
	ADD_SIGNAL(MethodInfo("ros_ready"));
}

Dictionary rclgd::get_transport_info() const {
#ifdef ROS2_VITA_XRCE
	return ros2_vita_xrce_diagnostics();
#else
	return Dictionary();
#endif
}

Error rclgd::init(const PackedStringArray &p_args) {
	if (running) {
		return OK;
	}
	// Argumentos estilo ROS: --ros-args -p clave:=valor ...
	overrides.clear();
	for (int i = 0; i < p_args.size(); i++) {
		if (p_args[i] == "-p" && i + 1 < p_args.size()) {
			Vector<String> kv = p_args[i + 1].split(":=", true, 1);
			if (kv.size() == 2) {
				overrides[kv[0]] = kv[1];
			}
			i++;
		}
	}

	// Esquema de mensajes (generado en el PC por tools/gen_msg_schema.py)
	if (!RosMsg::has_schema()) {
		ProjectSettings *ps = ProjectSettings::get_singleton();
		String path = overrides.has("schema") ? String(overrides["schema"])
				: (ps->has_setting("ros/schema_path") ? String(ps->get_setting("ros/schema_path")) : String("res://ros/schema.rsch"));
		if (RosMsg::load_schema_file(path) != OK) {
			WARN_PRINT(vformat("rclgd: sin esquema (%s); RosMsg.from_type no funcionara.", path));
		}
	}

#ifdef VITA_ENABLED
	String def_transport = "xrce";
#else
	String def_transport = "loopback";
#endif
	String which = overrides.has("transport") ? String(overrides["transport"]) : def_transport;
	if (which == "xrce") {
#ifdef ROS2_VITA_XRCE
		transport = ros2_vita_create_xrce_transport();
#else
		transport = memnew(XrceUnavailable);
#endif
	} else {
		transport = memnew(LoopbackTransport);
	}
	transport->rx = &rclgd::_rx_trampoline;
	transport->rx_ctx = this;
	Error err = transport->start(overrides);
	if (err != OK) {
		memdelete(transport);
		transport = nullptr;
		return err;
	}
	running = true;
	session++;
	_ensure_pump();
	emit_signal(SNAME("ros_ready"));
	return OK;
}

void rclgd::shutdown() {
	if (!running) {
		return;
	}
	running = false;
	if (transport) {
		transport->stop();
		memdelete(transport);
		transport = nullptr;
	}
	MutexLock lock(inbox_mutex);
	inbox.clear();
	subs.clear();
	timers.clear();
}

void rclgd::_ensure_pump() {
	if (pump_connected) {
		return;
	}
	SceneTree *tree = Object::cast_to<SceneTree>(OS::get_singleton()->get_main_loop());
	if (tree) {
		tree->connect("process_frame", callable_mp(this, &rclgd::_pump));
		pump_connected = true;
	}
}

void rclgd::register_subscription(int p_id, ObjectID p_obj) {
	MutexLock lock(inbox_mutex);
	SubEntry e;
	e.obj = p_obj;
	subs[p_id] = e;
}

void rclgd::unregister_subscription(int p_id) {
	MutexLock lock(inbox_mutex);
	// Sus mensajes pendientes se quedan en la cola y _pump los salta (ya no hay entrada); `pending` muere con ella.
	subs.erase(p_id);
}

void rclgd::set_latest_only(int p_id, bool p_v) {
	MutexLock lock(inbox_mutex);
	SubEntry *e = subs.getptr(p_id);
	if (e) {
		e->latest_only = p_v;
		if (!p_v) {
			e->pending = nullptr;
		}
	}
}

bool rclgd::is_latest_only(int p_id) const {
	MutexLock lock(inbox_mutex);
	const SubEntry *e = subs.getptr(p_id);
	return e && e->latest_only;
}

void rclgd::get_sub_counters(int p_id, uint64_t &r_recibidos, uint64_t &r_descartados) const {
	MutexLock lock(inbox_mutex);
	const SubEntry *e = subs.getptr(p_id);
	r_recibidos = e ? e->recibidos : 0;
	r_descartados = e ? e->descartados : 0;
}

void rclgd::register_timer(ObjectID p_obj) {
	timers.push_back(p_obj);
	_ensure_pump();
}

void rclgd::_rx_trampoline(void *p_ctx, int p_sub_id, const uint8_t *p_data, size_t p_len) {
	rclgd *self = (rclgd *)p_ctx;
	MutexLock lock(self->inbox_mutex);
	SubEntry *e = self->subs.getptr(p_sub_id);
	if (!e) {
		return; // suscripción liberada (antes se encolaba y _pump la saltaba)
	}
	e->recibidos++;
	if (e->latest_only && e->pending) {
		// V13a (D8): «el último gana» ANTES de decodificar: se pisa el payload que aún espera, en su sitio.
		Vector<uint8_t> &pl = e->pending->get().payload;
		pl.resize(p_len);
		if (p_len) {
			memcpy(pl.ptrw(), p_data, p_len);
		}
		e->descartados++;
		return;
	}
	if (self->inbox.size() >= 256) { // cola acotada: se descarta el MÁS ANTIGUO (docs/13 §4)
		List<RxItem>::Element *old = self->inbox.front();
		SubEntry *oe = self->subs.getptr(old->get().sub_id);
		if (oe) {
			oe->descartados++;
			if (oe->pending == old) {
				oe->pending = nullptr;
			}
		}
		self->inbox.pop_front();
		self->dropped++;
	}
	RxItem item;
	item.sub_id = p_sub_id;
	item.payload.resize(p_len);
	if (p_len) {
		memcpy(item.payload.ptrw(), p_data, p_len);
	}
	List<RxItem>::Element *el = self->inbox.push_back(item);
	if (e->latest_only) {
		e->pending = el;
	}
}

void rclgd::_pump() {
	if (!running) {
		return;
	}
	// 0) el transporte atiende la red (XRCE: envía lo pendiente y recibe sin bloquear)
	if (transport) {
		transport->poll();
	}
	// 1) mensajes recibidos (todos los callbacks al hilo principal, como rclgd)
	List<RxItem> local;
	{
		MutexLock lock(inbox_mutex);
		local = inbox;
		inbox.clear();
		for (KeyValue<int, SubEntry> &kv : subs) {
			kv.value.pending = nullptr; // lo pendiente pasa a `local`: lo que llegue ahora va a la cola nueva
		}
	}
	for (const RxItem &it : local) {
		ObjectID oid;
		{
			MutexLock lock(inbox_mutex);
			const SubEntry *p = subs.getptr(it.sub_id);
			if (!p) {
				continue; // suscripción liberada
			}
			oid = p->obj;
		}
		RosSubscriber *sub = Object::cast_to<RosSubscriber>(ObjectDB::get_instance(oid));
		if (sub) {
			sub->deliver(it.payload.ptr(), it.payload.size());
		}
	}
	// 2) timers
	uint64_t now = OS::get_singleton()->get_ticks_usec();
	for (int i = timers.size() - 1; i >= 0; i--) {
		RosTimer *t = Object::cast_to<RosTimer>(ObjectDB::get_instance(timers[i]));
		if (!t) {
			timers.remove_at(i); // liberado (el usuario soltó la referencia)
		} else {
			t->tick(now);
		}
	}
}
