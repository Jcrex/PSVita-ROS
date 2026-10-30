// xrce_transport.cpp — transporte micro-ROS (XRCE-DDS) de ros2_vita. Puerta G5 (docs/18 §8).
// Probado en host contra el agente micro-ROS en docker; en la Vita: validar en hardware.
//
// Diseño (el mismo que la app Godot 3.5, que funcionó en hardware):
//  - UN hilo: todo (crear entidades, publicar, atender la sesión) va en el hilo principal. poll()
//    se llama una vez por frame desde rclgd::_pump con uxr_run_session_time(0): envía lo pendiente y
//    vacía los paquetes recibidos SIN bloquear. Así no hacen falta mutex alrededor de la sesión.
//  - Las entidades DDS se crean por XML (las materializa el agente): un participante, un
//    publisher y un subscriber compartidos, y un topic + datawriter/datareader por cada
//    create_publisher/create_subscription.
//  - Dos pares de streams: fiable (QoS RELIABLE, por defecto) y best effort (QoS BEST_EFFORT).
//  - Los bytes ya vienen serializados en CDR por RosMsg (sin la cabecera de encapsulación de
//    4 bytes, que pone el agente): aquí solo se copian.
#include "xrce_transport.h"

// Mensajes de log SIN tildes: un const char* se convierte a String como Latin-1 (salen "sesiÃ³n").

#ifdef ROS2_VITA_XRCE // SCsub lo define solo si encuentra las libs XRCE

#include "core/config/project_settings.h"
#include "core/string/print_string.h"

#include <uxr/client/client.h>

extern "C" {
#include "microros_transport.h" // modules/microros-transport (dual C/Rust) -> net-udp
#include "net_udp.h"
}

#ifdef VITA_ENABLED
#include <malloc.h>
#include <psp2/net/net.h>
#include <psp2/net/netctl.h>
#include <psp2/sysmodule.h>
#endif

namespace {

// ---------------------------------------------------------------------------------------------
// Diagnóstico (G5 en hardware): contadores de los 4 callbacks del transporte propio. En la Vita no
// hay consola visible, así que rclgd.get_transport_info() los expone a GDScript para pintarlos.
struct XrceDiag {
	String step = "sin iniciar"; // último paso alcanzado
	String agent;
	int writes = 0, write_errors = 0, write_bytes = 0;
	int reads = 0, read_errors = 0, read_bytes = 0, read_packets = 0;
	int netctl_state = -1; // sceNetCtlInetGetState: 0 desconectado ... 3 IP obtenida
	String vita_ip;
	// Códigos de la inicialización de red (Vita): 0 = OK; 0x8041... = errores de sceNet.
	int rc_sysmodule = 0, rc_netinit = 0, rc_netctl = 0, rc_net_udp = 0;
};
XrceDiag g_diag;

struct TransportArgs {
	const char *ip;
	uint16_t port;
};

// Los 4 callbacks de uxrCustomTransport: delegan 1:1 en microros-transport, como
// vita-app/src/uxr_glue.c, pero contando lo que pasa.
bool cb_open(uxrCustomTransport *t) {
	TransportArgs *a = (TransportArgs *)t->args;
	return a && microros_transport_open(a->ip, a->port);
}
bool cb_close(uxrCustomTransport *) {
	return microros_transport_close();
}
size_t cb_write(uxrCustomTransport *, const uint8_t *buf, size_t len, uint8_t *err) {
	size_t n = microros_transport_write(buf, len, err);
	g_diag.writes++;
	if (n == 0 || (err && *err)) {
		g_diag.write_errors++;
	}
	g_diag.write_bytes += (int)n;
	return n;
}
size_t cb_read(uxrCustomTransport *, uint8_t *buf, size_t len, int timeout, uint8_t *err) {
	size_t n = microros_transport_read(buf, len, (int32_t)timeout, err);
	g_diag.reads++;
	if (err && *err) {
		g_diag.read_errors++;
	}
	if (n > 0) {
		g_diag.read_packets++;
		g_diag.read_bytes += (int)n;
	}
	return n;
}

// Inicializa la red de la Vita ANTES de net_udp_init, guardando el código de cada paso (net_udp solo
// devuelve "fallo"). El pool de sceNetInit sale del montón (memalign) y no del array estático de
// net_udp.c: dentro de libgodot.so ese array vive en la imagen que mapea el cargador, no en memoria
// normal de la app (hipótesis de G5 en hardware). net_udp_init acepta la red ya iniciada (EBUSY).
void vita_net_init() {
#ifdef VITA_ENABLED
	static void *pool = nullptr;
	const int POOL = 1024 * 1024;
	g_diag.rc_sysmodule = sceSysmoduleLoadModule(SCE_SYSMODULE_NET);
	if (!pool) {
		pool = memalign(4096, POOL);
	}
	if (pool) {
		SceNetInitParam param;
		param.memory = pool;
		param.size = POOL;
		param.flags = 0;
		g_diag.rc_netinit = sceNetInit(&param);
	} else {
		g_diag.rc_netinit = -1; // sin memoria para el pool
	}
	g_diag.rc_netctl = sceNetCtlInit();
#endif
	g_diag.rc_net_udp = net_udp_init();
}

void read_netctl() {
#ifdef VITA_ENABLED
	int state = -1;
	if (sceNetCtlInetGetState(&state) >= 0) {
		g_diag.netctl_state = state;
	}
	SceNetCtlInfo info;
	if (sceNetCtlInetGetInfo(SCE_NETCTL_INFO_GET_IP_ADDRESS, &info) >= 0) {
		g_diag.vita_ip = String(info.ip_address);
	}
#endif
}

// Tamaños como en vita-app/src/main.c (probados en hardware). La MTU del transporte propio es 512
// (UXR_CONFIG_CUSTOM_TRANSPORT_MTU): un mensaje mayor se fragmenta (solo en el stream fiable).
constexpr size_t RELIABLE_SLOT = 4096;
constexpr uint16_t RELIABLE_HISTORY = 4;
constexpr size_t BEST_EFFORT_BUF = UXR_CONFIG_CUSTOM_TRANSPORT_MTU;
constexpr int ENTITY_TIMEOUT_MS = 2000; // espera de la respuesta del agente al crear entidades

// "geometry_msgs/msg/Twist" -> "geometry_msgs::msg::dds_::Twist_" (nombre DDS que usa ROS 2).
String dds_type_name(const String &p_ros) {
	Vector<String> parts = p_ros.split("/");
	if (parts.size() != 3) {
		return String();
	}
	return parts[0] + "::" + parts[1] + "::dds_::" + parts[2] + "_";
}

// XML de QoS para data_writer / data_reader (perfil XML de Fast DDS, que es lo que usa el agente).
String qos_xml(const Ref<RosQoS> &p_qos) {
	bool best_effort = p_qos.is_valid() && p_qos->get_reliability() == RosQoS::BEST_EFFORT;
	bool transient = p_qos.is_valid() && p_qos->get_durability() == RosQoS::TRANSIENT_LOCAL;
	return String("<qos><reliability><kind>") + (best_effort ? "BEST_EFFORT" : "RELIABLE") +
			"</kind></reliability><durability><kind>" + (transient ? "TRANSIENT_LOCAL" : "VOLATILE") +
			"</kind></durability></qos>";
}

String history_xml(const Ref<RosQoS> &p_qos) {
	bool keep_all = p_qos.is_valid() && p_qos->get_history() == RosQoS::KEEP_ALL;
	int depth = p_qos.is_valid() ? MAX(1, p_qos->get_depth()) : 10;
	return String("<historyQos><kind>") + (keep_all ? "KEEP_ALL" : "KEEP_LAST") + "</kind><depth>" +
			itos(depth) + "</depth></historyQos>";
}

class XrceTransport : public RosTransport {
	struct Endpoint {
		uxrObjectId entity; // datawriter o datareader
		bool reliable = true;
	};

	uxrCustomTransport transport = {};
	TransportArgs targs = {};
	CharString agent_ip; // targs.ip apunta aquí: debe vivir mientras el transporte
	uxrSession session = {};
	bool transport_open = false;
	bool session_open = false;

	uint8_t reliable_out_buf[RELIABLE_SLOT * RELIABLE_HISTORY];
	uint8_t reliable_in_buf[RELIABLE_SLOT * RELIABLE_HISTORY];
	uint8_t best_effort_out_buf[BEST_EFFORT_BUF];
	uxrStreamId reliable_out = {}, reliable_in = {}, best_effort_out = {}, best_effort_in = {};

	uxrObjectId participant = {}, publisher = {}, subscriber = {};
	HashMap<String, uxrObjectId> topics; // un topic DDS por nombre (crear dos con el mismo nombre falla)
	HashMap<int, Endpoint> pubs;
	HashMap<int, Endpoint> subs;
	uint16_t next_entity = 1; // ids de objeto XRCE (12 bits)
	int next_id = 1;

	uxrObjectId _new_object(uint8_t p_type) { return uxr_object_id(next_entity++, p_type); }

	// Bufferiza peticiones y espera a que el agente responda a todas. true si todas OK.
	bool _wait(const uint16_t *p_req, int p_n, const String &p_what) {
		uint8_t status[4] = {};
		ERR_FAIL_COND_V(p_n > 4, false);
		if (!uxr_run_session_until_all_status(&session, ENTITY_TIMEOUT_MS, p_req, status, p_n)) {
			ERR_PRINT(vformat("ros2_vita/xrce: el agente rechazo o no respondio a %s (status %d %d %d %d).",
					p_what, status[0], status[1], status[2], status[3]));
			return false;
		}
		return true;
	}

	// Devuelve el topic DDS ("rt" + nombre ROS), creándolo si hace falta.
	bool _topic(const String &p_topic, const String &p_dds_type, uxrObjectId *r_id) {
		const uxrObjectId *found = topics.getptr(p_topic);
		if (found) {
			*r_id = *found;
			return true;
		}
		uxrObjectId id = _new_object(UXR_TOPIC_ID);
		CharString xml = ("<dds><topic><name>rt" + p_topic + "</name><dataType>" + p_dds_type +
				"</dataType></topic></dds>")
								 .utf8();
		uint16_t req = uxr_buffer_create_topic_xml(&session, reliable_out, id, participant, xml.get_data(), UXR_REPLACE);
		if (!_wait(&req, 1, "crear el topic")) {
			return false;
		}
		topics[p_topic] = id;
		*r_id = id;
		return true;
	}

	static void _on_topic(uxrSession *, uxrObjectId p_object, uint16_t, uxrStreamId, ucdrBuffer *p_ub, uint16_t p_len, void *p_args) {
		XrceTransport *self = (XrceTransport *)p_args;
		for (const KeyValue<int, Endpoint> &kv : self->subs) {
			if (kv.value.entity.id == p_object.id && kv.value.entity.type == p_object.type) {
				if (self->rx && p_len <= ucdr_buffer_remaining(p_ub)) {
					// El payload empieza en el iterador del buffer (como hace vita-app con ucdr_deserialize_*).
					self->rx(self->rx_ctx, kv.key, p_ub->iterator, p_len);
				}
				return;
			}
		}
	}

	// Fragmentación: cuando se llenan los slots del stream fiable, hay que enviarlos antes de seguir.
	static bool _flush(uxrSession *p_session, void *) {
		return uxr_run_session_time(p_session, 10);
	}

public:
	Error start(const Dictionary &p_args) override {
		ProjectSettings *ps = ProjectSettings::get_singleton();
		String ip = p_args.has("agent_ip") ? String(p_args["agent_ip"])
										   : String(ps->get_setting("ros/agent_ip", "127.0.0.1"));
		int port = p_args.has("agent_port") ? String(p_args["agent_port"]).to_int()
											: int(ps->get_setting("ros/agent_port", 8888));
		int domain = p_args.has("domain_id") ? String(p_args["domain_id"]).to_int()
											 : int(ps->get_setting("ros/domain_id", 0));
		agent_ip = ip.utf8();
		targs.ip = agent_ip.get_data();
		targs.port = (uint16_t)port;
		g_diag = XrceDiag();
		g_diag.agent = vformat("%s:%d", ip, port);
		print_line(vformat("ros2_vita/xrce: conectando con el agente %s:%d (dominio %d)...", ip, port, domain));

		// Abre el socket UDP (en la Vita: sceNetInit + sceNetCtlInit dentro de net_udp_init, docs/18 §4.3 A).
		// false = sin framing: UDP ya delimita datagramas (el framing es para transportes serie).
		uxr_set_custom_transport_callbacks(&transport, false, cb_open, cb_close, cb_write, cb_read);
		g_diag.step = "iniciando red";
		vita_net_init();
		g_diag.step = "abriendo socket UDP";
		bool opened = uxr_init_custom_transport(&transport, &targs);
		read_netctl(); // net_udp_init ya inicializo sceNetCtl
		ERR_FAIL_COND_V_MSG(!opened, ERR_CANT_CONNECT,
				"ros2_vita/xrce: no se pudo abrir el socket UDP (red de la Vita sin conectar?).");
		transport_open = true;
		g_diag.step = "creando sesion XRCE";

		uxr_init_session(&session, &transport.comm, 0xCAFE0005);
		uxr_set_topic_callback(&session, &XrceTransport::_on_topic, this);
		bool created = uxr_create_session(&session);
		read_netctl();
		if (!created) {
			g_diag.step = "sin respuesta del agente";
			stop();
			ERR_FAIL_V_MSG(ERR_CANT_CONNECT, vformat("ros2_vita/xrce: sin respuesta del agente en %s:%d "
													 "(esta corriendo micro-ros-agent udp4 --port %d?).",
													 ip, port, port));
		}
		session_open = true;
		g_diag.step = "creando entidades";

		reliable_out = uxr_create_output_reliable_stream(&session, reliable_out_buf, sizeof(reliable_out_buf), RELIABLE_HISTORY);
		reliable_in = uxr_create_input_reliable_stream(&session, reliable_in_buf, sizeof(reliable_in_buf), RELIABLE_HISTORY);
		best_effort_out = uxr_create_output_best_effort_stream(&session, best_effort_out_buf, sizeof(best_effort_out_buf));
		best_effort_in = uxr_create_input_best_effort_stream(&session);

		participant = _new_object(UXR_PARTICIPANT_ID);
		publisher = _new_object(UXR_PUBLISHER_ID);
		subscriber = _new_object(UXR_SUBSCRIBER_ID);
		uint16_t req[3];
		req[0] = uxr_buffer_create_participant_xml(&session, reliable_out, participant, (uint16_t)domain,
				"<dds><participant><rtps><name>ros2_vita</name></rtps></participant></dds>", UXR_REPLACE);
		req[1] = uxr_buffer_create_publisher_xml(&session, reliable_out, publisher, participant, "", UXR_REPLACE);
		req[2] = uxr_buffer_create_subscriber_xml(&session, reliable_out, subscriber, participant, "", UXR_REPLACE);
		if (!_wait(req, 3, "crear participante/publisher/subscriber")) {
			stop();
			return ERR_CANT_CREATE;
		}
		g_diag.step = "sesion abierta";
		print_line("ros2_vita/xrce: sesion XRCE establecida.");
		return OK;
	}

	void stop() override {
		if (session_open) {
			uxr_delete_session(&session);
			session_open = false;
		}
		if (transport_open) {
			uxr_close_custom_transport(&transport);
			transport_open = false;
		}
		topics.clear();
		pubs.clear();
		subs.clear();
	}

	void poll() override {
		if (session_open) {
			uxr_run_session_time(&session, 0); // no bloquea: envía y vacía lo recibido
		}
	}

	int advertise(const String &p_topic, const String &p_type, const Ref<RosQoS> &p_qos) override {
		ERR_FAIL_COND_V(!session_open, -1);
		String dds = dds_type_name(p_type);
		ERR_FAIL_COND_V_MSG(dds.is_empty(), -1, "ros2_vita/xrce: tipo ROS no valido: " + p_type);
		uxrObjectId topic;
		if (!_topic(p_topic, dds, &topic)) {
			return -1;
		}
		Endpoint ep;
		ep.entity = _new_object(UXR_DATAWRITER_ID);
		ep.reliable = !(p_qos.is_valid() && p_qos->get_reliability() == RosQoS::BEST_EFFORT);
		CharString xml = ("<dds><data_writer><topic><kind>NO_KEY</kind><name>rt" + p_topic + "</name><dataType>" + dds +
				"</dataType>" + history_xml(p_qos) + "</topic>" + qos_xml(p_qos) + "</data_writer></dds>")
								 .utf8();
		uint16_t req = uxr_buffer_create_datawriter_xml(&session, reliable_out, ep.entity, publisher, xml.get_data(), UXR_REPLACE);
		if (!_wait(&req, 1, "crear el datawriter de " + p_topic)) {
			return -1;
		}
		pubs[next_id] = ep;
		return next_id++;
	}

	int subscribe(const String &p_topic, const String &p_type, const Ref<RosQoS> &p_qos) override {
		ERR_FAIL_COND_V(!session_open, -1);
		String dds = dds_type_name(p_type);
		ERR_FAIL_COND_V_MSG(dds.is_empty(), -1, "ros2_vita/xrce: tipo ROS no valido: " + p_type);
		uxrObjectId topic;
		if (!_topic(p_topic, dds, &topic)) {
			return -1;
		}
		Endpoint ep;
		ep.entity = _new_object(UXR_DATAREADER_ID);
		ep.reliable = !(p_qos.is_valid() && p_qos->get_reliability() == RosQoS::BEST_EFFORT);
		CharString xml = ("<dds><data_reader><topic><kind>NO_KEY</kind><name>rt" + p_topic + "</name><dataType>" + dds +
				"</dataType>" + history_xml(p_qos) + "</topic>" + qos_xml(p_qos) + "</data_reader></dds>")
								 .utf8();
		uint16_t req = uxr_buffer_create_datareader_xml(&session, reliable_out, ep.entity, subscriber, xml.get_data(), UXR_REPLACE);
		if (!_wait(&req, 1, "crear el datareader de " + p_topic)) {
			return -1;
		}
		// Pedir al agente que reenvíe todas las muestras de este datareader.
		uxrDeliveryControl delivery = {};
		delivery.max_samples = UXR_MAX_SAMPLES_UNLIMITED;
		uxr_buffer_request_data(&session, reliable_out, ep.entity, ep.reliable ? reliable_in : best_effort_in, &delivery);
		subs[next_id] = ep;
		return next_id++;
	}

	void unadvertise(int p_id) override {
		const Endpoint *ep = pubs.getptr(p_id);
		if (ep && session_open) {
			uxr_buffer_delete_entity(&session, reliable_out, ep->entity);
		}
		pubs.erase(p_id);
	}

	void unsubscribe(int p_id) override {
		const Endpoint *ep = subs.getptr(p_id);
		if (ep && session_open) {
			uxr_buffer_cancel_data(&session, reliable_out, ep->entity);
			uxr_buffer_delete_entity(&session, reliable_out, ep->entity);
		}
		subs.erase(p_id);
	}

	Error publish(int p_id, const uint8_t *p_data, size_t p_len) override {
		ERR_FAIL_COND_V(!session_open, ERR_UNCONFIGURED);
		const Endpoint *ep = pubs.getptr(p_id);
		ERR_FAIL_NULL_V(ep, ERR_DOES_NOT_EXIST);
		ucdrBuffer ub;
		uxrStreamId stream = ep->reliable ? reliable_out : best_effort_out;
		if (uxr_prepare_output_stream(&session, stream, ep->entity, &ub, (uint32_t)p_len) == UXR_INVALID_REQUEST_ID) {
			// No cabe en un datagrama (o los slots fiables están llenos): fragmentar (solo fiable).
			ERR_FAIL_COND_V_MSG(!ep->reliable, ERR_OUT_OF_MEMORY,
					vformat("ros2_vita/xrce: %d bytes no caben en un datagrama best effort (MTU %d).", (int)p_len, (int)BEST_EFFORT_BUF));
			ERR_FAIL_COND_V_MSG(uxr_prepare_output_stream_fragmented(&session, stream, ep->entity, &ub, p_len, &XrceTransport::_flush, nullptr) == UXR_INVALID_REQUEST_ID,
					ERR_BUSY, "ros2_vita/xrce: stream fiable lleno; mensaje descartado.");
		}
		ucdr_serialize_array_uint8_t(&ub, p_data, p_len);
		return OK;
	}
};

} // namespace

Dictionary ros2_vita_xrce_diagnostics() {
	Dictionary d;
	d["step"] = g_diag.step;
	d["agent"] = g_diag.agent;
	d["writes"] = g_diag.writes;
	d["write_errors"] = g_diag.write_errors;
	d["write_bytes"] = g_diag.write_bytes;
	d["reads"] = g_diag.reads;
	d["read_errors"] = g_diag.read_errors;
	d["read_packets"] = g_diag.read_packets;
	d["read_bytes"] = g_diag.read_bytes;
	d["netctl_state"] = g_diag.netctl_state;
	d["vita_ip"] = g_diag.vita_ip;
	d["rc_sysmodule"] = g_diag.rc_sysmodule;
	d["rc_netinit"] = g_diag.rc_netinit;
	d["rc_netctl"] = g_diag.rc_netctl;
	d["rc_net_udp"] = g_diag.rc_net_udp;
	return d;
}

RosTransport *ros2_vita_create_xrce_transport() {
	return memnew(XrceTransport);
}

#endif // ROS2_VITA_XRCE
