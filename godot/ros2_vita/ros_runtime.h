// ros_runtime.h — singleton `rclgd`, RosNode, RosPublisher, RosSubscriber, RosTimer, RosQoS
// V13a (2026-11-14): propiedades de RosQoS, latest_only y contadores por suscripción, tipo resuelto al suscribir.
// (Godot 4.x in-tree). Compilado y probado en host (G1). API y semántica copiadas de rclgd (docs/17,
// godot/ros2_vita/API_PARITY.md); el transporte es intercambiable:
//   - LoopbackTransport : publica y recibe en el propio proceso (pruebas de host, sin Vita)
//   - XrceTransport     : micro-ROS sobre WiFi/UDP (xrce_transport.cpp, puerta G5)
#pragma once

#include "core/io/resource.h"
#include "core/object/callable_mp.h" // en 4.8 sustituye a callable_method_pointer.h
#include "core/object/ref_counted.h"
#include "core/os/mutex.h"
#include "core/templates/hash_map.h"
#include "core/templates/list.h"
#include "ros_msg.h"

// ---------------------------------------------------------------------------
class RosQoS : public Resource {
	GDCLASS(RosQoS, Resource);

public:
	enum Reliability { RELIABLE, BEST_EFFORT };
	enum Durability { VOLATILE, TRANSIENT_LOCAL };
	enum History { KEEP_LAST, KEEP_ALL };
	enum Liveliness { AUTOMATIC, MANUAL_BY_TOPIC, SYSTEM_DEFAULT };

private:
	History history = KEEP_LAST;
	int depth = 10;
	Reliability reliability = RELIABLE;
	Durability durability = VOLATILE;
	// V13a: mismas propiedades que rclgd (ros_qos.cpp). XRCE solo traduce reliability, durability, history y depth
	// (xrce_transport.cpp qos_xml/history_xml); estas cuatro se guardan para que el mismo script funcione, pero el
	// transporte las ignora (API_PARITY.md).
	double deadline = 0.0;
	double lifespan = 0.0;
	Liveliness liveliness = SYSTEM_DEFAULT;
	double lease_duration = 0.0;

protected:
	static void _bind_methods();

public:
	void set_history(int p_v) { history = (History)p_v; }
	int get_history() const { return history; }
	void set_depth(int p_v) { depth = p_v; }
	int get_depth() const { return depth; }
	void set_reliability(int p_v) { reliability = (Reliability)p_v; }
	int get_reliability() const { return reliability; }
	void set_durability(int p_v) { durability = (Durability)p_v; }
	int get_durability() const { return durability; }
	void set_deadline(double p_v) { deadline = p_v; }
	double get_deadline() const { return deadline; }
	void set_lifespan(double p_v) { lifespan = p_v; }
	double get_lifespan() const { return lifespan; }
	void set_liveliness(int p_v) { liveliness = (Liveliness)p_v; }
	int get_liveliness() const { return liveliness; }
	void set_lease_duration(double p_v) { lease_duration = p_v; }
	double get_lease_duration() const { return lease_duration; }
};
VARIANT_ENUM_CAST(RosQoS::Reliability);
VARIANT_ENUM_CAST(RosQoS::Durability);
VARIANT_ENUM_CAST(RosQoS::History);
VARIANT_ENUM_CAST(RosQoS::Liveliness);

// ---------------------------------------------------------------------------
// Transporte (no se expone a GDScript)
class RosTransport {
public:
	typedef void (*RxCallback)(void *p_ctx, int p_sub_id, const uint8_t *p_data, size_t p_len);
	RxCallback rx = nullptr; // se invoca desde CUALQUIER hilo; rclgd lo encola
	void *rx_ctx = nullptr;

	virtual ~RosTransport() {}
	virtual Error start(const Dictionary &p_args) = 0;
	virtual void stop() = 0;
	virtual int advertise(const String &p_topic, const String &p_type, const Ref<RosQoS> &p_qos) = 0;
	virtual int subscribe(const String &p_topic, const String &p_type, const Ref<RosQoS> &p_qos) = 0;
	virtual void unadvertise(int p_id) = 0;
	virtual void unsubscribe(int p_id) = 0;
	virtual Error publish(int p_pub_id, const uint8_t *p_data, size_t p_len) = 0;
	// Una vez por frame desde rclgd::_pump (hilo principal), antes de entregar lo recibido.
	// XRCE la usa para atender la sesión sin bloquear; loopback no la necesita.
	virtual void poll() {}
	// Hora del agente (época Unix en ns) si el transporte la sincronizó; false = usar el reloj local.
	// XRCE: uxr_sync_session al abrir la sesión (revisión R2-M7: sellos de la Vita desfasados del PC).
	virtual bool epoch_ns(int64_t *r_ns) { return false; }
};

// ---------------------------------------------------------------------------
class RosPublisher : public RefCounted {
	GDCLASS(RosPublisher, RefCounted);
	int pub_id = -1;
	uint32_t session = 0; // V13a: sesión de rclgd que dio el id (los ids se reutilizan tras shutdown/init)
	String type_name;

protected:
	static void _bind_methods();

public:
	void setup(int p_id, const String &p_type) {
		pub_id = p_id;
		type_name = p_type;
	}
	void set_session(uint32_t p_s) { session = p_s; }
	void publish(const Ref<RosMsg> &p_msg);
	~RosPublisher();
};

class RosSubscriber : public RefCounted {
	GDCLASS(RosSubscriber, RefCounted);

public:
	// V13a: manejador de bytes crudos (sin RosMsg) para consumidores nativos (RosTfListener decodifica TFMessage con
	// modules/msg-cdr). Se llama en el hilo principal, como el Callable.
	typedef void (*RawHandler)(void *p_ctx, const uint8_t *p_data, size_t p_len);

private:
	int sub_id = -1;
	uint32_t session = 0; // V13a: ver RosPublisher
	String type_name;
	uint32_t type_idx = 0xFFFFFFFFu; // MSG_SCHEMA_NO_TYPE: se resuelve UNA vez en setup (V13a)
	Callable callback;
	RawHandler raw = nullptr;
	void *raw_ctx = nullptr;
	// Contadores del hilo principal (V13a, doc 36 §1.5 P2). Los de llegada y descarte viven en rclgd (hilo de red).
	uint64_t decodificados = 0;
	uint64_t errores = 0;

protected:
	static void _bind_methods();

public:
	void setup(int p_id, const String &p_type, uint32_t p_type_idx, const Callable &p_cb) {
		sub_id = p_id;
		type_name = p_type;
		type_idx = p_type_idx;
		callback = p_cb;
	}
	void setup_raw(int p_id, const String &p_type, RawHandler p_fn, void *p_ctx) {
		sub_id = p_id;
		type_name = p_type;
		raw = p_fn;
		raw_ctx = p_ctx;
	}
	int get_id() const { return sub_id; }
	void set_session(uint32_t p_s) { session = p_s; }
	bool _vigente() const; // su sesión sigue abierta (si no, el id puede ser de otra suscripción)
	void deliver(const uint8_t *p_data, size_t p_len); // hilo principal

	// --- extensiones de ros2_vita (no existen en rclgd: usar con has_method) ---
	// «El último gana» ANTES de decodificar (D8): mientras un mensaje de esta suscripción espera en la cola, el
	// siguiente lo sustituye (sin decodificar el viejo y ocupando un solo hueco de la cola de 256).
	void set_latest_only(bool p_v);
	bool is_latest_only() const;
	// {recibidos, descartados, decodificados, errores, latest_only, tipo}
	Dictionary get_stats() const;
	~RosSubscriber();
};

class RosTimer : public RefCounted {
	GDCLASS(RosTimer, RefCounted);
	uint64_t period_us = 0;
	uint64_t next_us = 0;
	bool canceled = false;
	Callable callback;

protected:
	static void _bind_methods();

public:
	void setup(double p_seconds, const Callable &p_cb);
	void tick(uint64_t p_now_us); // hilo principal, desde rclgd::_pump
	void cancel() { canceled = true; }
	void reset();
	bool is_canceled() const { return canceled; }
	bool is_ready() const;
	double get_remaining_time() const;
};

// ---------------------------------------------------------------------------
class RosNode : public RefCounted {
	GDCLASS(RosNode, RefCounted);
	String node_name;
	String node_ns = "/";
	Dictionary params;

	String _resolve_topic(const String &p_topic) const;
	static String _type_from_variant(const Variant &p_type);

protected:
	static void _bind_methods();

public:
	void init(const String &p_name, const String &p_namespace = "");
	String get_name() const { return node_name; }
	String get_namespace() const { return node_ns; }
	String resolve_frame(const String &p_id) const;

	Ref<RosPublisher> create_publisher(const String &p_topic, const Variant &p_type, const Ref<RosQoS> &p_qos = Ref<RosQoS>());
	Ref<RosSubscriber> create_subscription(const String &p_topic, const Variant &p_type, const Callable &p_cb, const Ref<RosQoS> &p_qos = Ref<RosQoS>());
	Ref<RosTimer> create_timer(double p_seconds, const Callable &p_cb);
	// Interno (V13a): suscripción de bytes crudos para clases nativas (RosTfListener). Sin esquema.
	Ref<RosSubscriber> create_subscription_raw(const String &p_topic, const String &p_type, RosSubscriber::RawHandler p_fn,
			void *p_ctx, const Ref<RosQoS> &p_qos);
	Ref<RosMsg> now();

	void declare_parameter(const String &p_name, const Variant &p_default);
	void set_parameter(const String &p_name, const Variant &p_value);
	Variant get_parameter(const String &p_name);
};

// ---------------------------------------------------------------------------
class rclgd : public Object {
	GDCLASS(rclgd, Object);

	static rclgd *singleton;

	struct RxItem {
		int sub_id;
		Vector<uint8_t> payload;
	};

	// Estado por suscripción que toca el hilo de red (protegido por inbox_mutex). V13a: latest_only y contadores.
	struct SubEntry {
		ObjectID obj;
		bool latest_only = false;
		List<RxItem>::Element *pending = nullptr; // con latest_only: su mensaje que aún espera en `inbox`
		uint64_t recibidos = 0;
		uint64_t descartados = 0; // sustituidos por latest_only + expulsados de la cola llena
	};

	bool running = false;
	uint32_t session = 0; // V13a: sube en cada init(); los Ros* guardan la suya
	RosTransport *transport = nullptr;
	Dictionary overrides; // -p clave:=valor
	mutable Mutex inbox_mutex;
	List<RxItem> inbox;
	uint32_t dropped = 0;
	HashMap<int, SubEntry> subs;
	Vector<ObjectID> timers;
	bool pump_connected = false;

	static void _rx_trampoline(void *p_ctx, int p_sub_id, const uint8_t *p_data, size_t p_len);
	void _pump();
	void _ensure_pump();

protected:
	static void _bind_methods();

public:
	static rclgd *get_singleton() { return singleton; }
	rclgd();
	~rclgd();

	Error init(const PackedStringArray &p_args = PackedStringArray());
	void shutdown();
	bool ok() const { return running; }
	uint32_t get_session() const { return session; }
	Dictionary get_overrides() const { return overrides; }
	int get_dropped() const { return dropped; }
	Dictionary get_transport_info() const; // diagnóstico del transporte (XRCE: contadores, WiFi)

	// Convención de ejes REP-103 <-> Godot (idéntica a rclgd; ver docs/17 §3.3)
	Vector3 godot_to_ros_vector(const Vector3 &p_v) const { return Vector3(-p_v.z, -p_v.x, p_v.y); }
	Vector3 ros_to_godot_vector(const Vector3 &p_v) const { return Vector3(-p_v.y, p_v.z, -p_v.x); }
	Quaternion godot_to_ros_quat(const Quaternion &p_q) const { return Quaternion(-p_q.z, -p_q.x, p_q.y, p_q.w); }
	Quaternion ros_to_godot_quat(const Quaternion &p_q) const { return Quaternion(-p_q.y, p_q.z, -p_q.x, p_q.w); }

	// Uso interno de las clases Ros*
	RosTransport *get_transport() const { return transport; }
	void register_subscription(int p_id, ObjectID p_obj);
	void unregister_subscription(int p_id);
	void set_latest_only(int p_id, bool p_v);
	bool is_latest_only(int p_id) const;
	void get_sub_counters(int p_id, uint64_t &r_recibidos, uint64_t &r_descartados) const;
	void register_timer(ObjectID p_obj);
};
