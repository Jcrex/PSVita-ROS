// ros_runtime.h — singleton `rclgd`, RosNode, RosPublisher, RosSubscriber, RosTimer, RosQoS
// (Godot 4.x in-tree). ¡SIN COMPILAR! API y semántica copiadas de rclgd (docs/17,
// godot/ros2_vita/API_PARITY.md); el transporte es intercambiable:
//   - LoopbackTransport : publica y recibe en el propio proceso (pruebas de host, sin Vita)
//   - XrceTransport     : micro-ROS sobre WiFi/UDP (pendiente, ver ros_runtime.cpp)
#pragma once

#include "core/io/resource.h"
#include "core/object/callable_method_pointer.h"
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

private:
	History history = KEEP_LAST;
	int depth = 10;
	Reliability reliability = RELIABLE;
	Durability durability = VOLATILE;

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
};
VARIANT_ENUM_CAST(RosQoS::Reliability);
VARIANT_ENUM_CAST(RosQoS::Durability);
VARIANT_ENUM_CAST(RosQoS::History);

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
};

// ---------------------------------------------------------------------------
class RosPublisher : public RefCounted {
	GDCLASS(RosPublisher, RefCounted);
	int pub_id = -1;
	String type_name;

protected:
	static void _bind_methods();

public:
	void setup(int p_id, const String &p_type) {
		pub_id = p_id;
		type_name = p_type;
	}
	void publish(const Ref<RosMsg> &p_msg);
	~RosPublisher();
};

class RosSubscriber : public RefCounted {
	GDCLASS(RosSubscriber, RefCounted);
	int sub_id = -1;
	String type_name;
	Callable callback;

protected:
	static void _bind_methods() {}

public:
	void setup(int p_id, const String &p_type, const Callable &p_cb) {
		sub_id = p_id;
		type_name = p_type;
		callback = p_cb;
	}
	int get_id() const { return sub_id; }
	void deliver(const uint8_t *p_data, size_t p_len); // hilo principal
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

	bool running = false;
	RosTransport *transport = nullptr;
	Dictionary overrides; // -p clave:=valor
	Mutex inbox_mutex;
	List<RxItem> inbox;
	uint32_t dropped = 0;
	HashMap<int, ObjectID> subs;
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
	Dictionary get_overrides() const { return overrides; }
	int get_dropped() const { return dropped; }

	// Convención de ejes REP-103 <-> Godot (idéntica a rclgd; ver docs/17 §3.3)
	Vector3 godot_to_ros_vector(const Vector3 &p_v) const { return Vector3(-p_v.z, -p_v.x, p_v.y); }
	Vector3 ros_to_godot_vector(const Vector3 &p_v) const { return Vector3(-p_v.y, p_v.z, -p_v.x); }
	Quaternion godot_to_ros_quat(const Quaternion &p_q) const { return Quaternion(-p_q.z, -p_q.x, p_q.y, p_q.w); }
	Quaternion ros_to_godot_quat(const Quaternion &p_q) const { return Quaternion(-p_q.y, p_q.z, -p_q.x, p_q.w); }

	// Uso interno de las clases Ros*
	RosTransport *get_transport() const { return transport; }
	void register_subscription(int p_id, ObjectID p_obj);
	void unregister_subscription(int p_id);
	void register_timer(ObjectID p_obj);
};
