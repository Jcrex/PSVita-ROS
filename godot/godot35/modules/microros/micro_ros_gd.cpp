/* micro_ros_gd.cpp — implementación del puente (ver micro_ros_gd.h).
 * VALIDAR EN EL PC (Tarea 7 de docs/13). */
#include "micro_ros_gd.h"

#include <ucdr/microcdr.h>

#include "config.h"
#include "net_udp.h"
#include "netlog.h"

MicroROS *MicroROS::singleton = nullptr;

MicroROS *MicroROS::get_singleton() {
	return singleton;
}

/* Godot normaliza los sticks a [-1,+1] (joypad_vita.cpp: raw/255*2-1);
 * teleop.c espera el rango crudo de sceCtrl 0..255 con centro ~128.
 * Esta es la conversión inversa exacta. */
static uint8_t eje_a_crudo(float v) {
	int crudo = (int)((v + 1.0f) * 127.5f + 0.5f);
	if (crudo < 0) {
		crudo = 0;
	}
	if (crudo > 255) {
		crudo = 255;
	}
	return (uint8_t)crudo;
}

static float dict_f(const Dictionary &d, const char *k) {
	return d.has(k) ? (float)d[k] : 0.0f;
}

static bool dict_b(const Dictionary &d, const char *k) {
	return d.has(k) ? (bool)d[k] : false;
}

bool MicroROS::setup(const String &p_agent_ip, const String &p_netlog_ip) {
	/* Validación con config.c (misma regla que la app nativa). */
	config_ip ip;
	if (!config_ip_parse(p_agent_ip.utf8().get_data(), &ip)) {
		ERR_PRINT("MicroROS.setup: IP del agente invalida");
		return false;
	}
	if (!config_ip_parse(p_netlog_ip.utf8().get_data(), &ip)) {
		ERR_PRINT("MicroROS.setup: IP del netlog invalida");
		return false;
	}
	agent_ip = p_agent_ip.utf8();

	if (!net_ok) {
		if (net_udp_init() != NET_UDP_OK) {
			ERR_PRINT("MicroROS.setup: net_udp_init fallo");
			return false;
		}
		net_ok = true;
	}
	/* Como en main.c: sin netlog se sigue (WARN), no es fatal — pero se
	 * comprueba el retorno (lección del bug de main.c:100). */
	netlog_ok = netlog_init(p_netlog_ip.utf8().get_data(),
			MICROROS_NETLOG_PORT);
	if (!netlog_ok) {
		WARN_PRINT("MicroROS.setup: netlog_init fallo; sin logs UDP");
	}
	netlog_printf("[godot-teleop] setup ok; agente=%s:%d\n",
			agent_ip.get_data(), MICROROS_AGENT_PORT);
	return true;
}

bool MicroROS::connect_agent() {
	if (session_ok) {
		return true;
	}
	if (!net_ok) {
		ERR_PRINT("MicroROS.connect_agent: llama primero a setup()");
		return false;
	}
	targs.agent_ip = agent_ip.get_data();
	targs.agent_port = MICROROS_AGENT_PORT;
	if (!vita_uxr_transport_init(&transport, &targs)) {
		netlog_printf("[godot-teleop] FATAL: transporte no abre "
				"(agente accesible?)\n");
		return false;
	}

	/* Session key distinta de la app nativa (0xCAFE0001) para no chocar
	 * si el agente conserva una sesión anterior de la otra app. */
	uxr_init_session(&session, &transport.comm, 0xCAFE0002);
	if (!uxr_create_session(&session)) {
		netlog_printf("[godot-teleop] FATAL: uxr_create_session fallo "
				"(agente v2.4.3?)\n");
		uxr_close_custom_transport(&transport);
		return false;
	}
	stream_out = uxr_create_output_reliable_stream(&session,
			output_stream_buf, sizeof output_stream_buf,
			MICROROS_STREAM_HISTORY);
	/* Gemelo de entrada (main.c:201): imprescindible para procesar los
	 * ACK/heartbeat que el agente devuelve sobre el stream reliable. Su id
	 * no se reusa luego (como en main.c), pero el stream debe existir. */
	uxr_create_input_reliable_stream(&session, input_stream_buf,
			sizeof input_stream_buf, MICROROS_STREAM_HISTORY);

	/* Entidades DDS de /cmd_vel: mismos XML que main.c (prefijo rt/ y
	 * tipo dds_ o ros2 no ve el topic como propio). */
	uxrObjectId participant_id = uxr_object_id(0x01, UXR_PARTICIPANT_ID);
	const char *participant_xml =
			"<dds><participant><rtps><name>vita_node</name></rtps>"
			"</participant></dds>";
	uint16_t req[4];
	req[0] = uxr_buffer_create_participant_xml(&session, stream_out,
			participant_id, 0, participant_xml, UXR_REPLACE);

	uxrObjectId cmdvel_topic_id = uxr_object_id(0x01, UXR_TOPIC_ID);
	const char *cmdvel_topic_xml =
			"<dds><topic><name>rt/cmd_vel</name>"
			"<dataType>geometry_msgs::msg::dds_::Twist_</dataType>"
			"</topic></dds>";
	req[1] = uxr_buffer_create_topic_xml(&session, stream_out,
			cmdvel_topic_id, participant_id, cmdvel_topic_xml,
			UXR_REPLACE);

	uxrObjectId publisher_id = uxr_object_id(0x01, UXR_PUBLISHER_ID);
	req[2] = uxr_buffer_create_publisher_xml(&session, stream_out,
			publisher_id, participant_id, "", UXR_REPLACE);

	cmdvel_dw_id = uxr_object_id(0x01, UXR_DATAWRITER_ID);
	const char *cmdvel_dw_xml =
			"<dds><data_writer><topic><kind>NO_KEY</kind>"
			"<name>rt/cmd_vel</name>"
			"<dataType>geometry_msgs::msg::dds_::Twist_</dataType>"
			"</topic></data_writer></dds>";
	req[3] = uxr_buffer_create_datawriter_xml(&session, stream_out,
			cmdvel_dw_id, publisher_id, cmdvel_dw_xml, UXR_REPLACE);

	uint8_t status[4];
	if (!uxr_run_session_until_all_status(&session, 3000, req, status, 4)) {
		netlog_printf("[godot-teleop] FATAL: agente rechazo entidades "
				"(status: %d %d %d %d)\n",
				status[0], status[1], status[2], status[3]);
		uxr_delete_session(&session);
		uxr_close_custom_transport(&transport);
		return false;
	}

	teleop_init(&teleop);
	session_ok = true;
	netlog_printf("[godot-teleop] *** SESION XRCE ESTABLECIDA ***\n");
	return true;
}

bool MicroROS::is_session_active() const {
	return session_ok;
}

Dictionary MicroROS::teleop_step(const Dictionary &p_input, float p_dt) {
	teleop_entrada in;
	in.lx = eje_a_crudo(dict_f(p_input, "lx"));
	in.ly = eje_a_crudo(dict_f(p_input, "ly"));
	in.rx = eje_a_crudo(dict_f(p_input, "rx"));
	in.ry = eje_a_crudo(dict_f(p_input, "ry"));
	in.arriba = dict_b(p_input, "up");
	in.abajo = dict_b(p_input, "down");
	in.izquierda = dict_b(p_input, "left");
	in.derecha = dict_b(p_input, "right");
	in.l = dict_b(p_input, "l");
	in.r = dict_b(p_input, "r");
	in.cruz = dict_b(p_input, "cross");
	in.triangulo = dict_b(p_input, "triangle");

	teleop_twist tw;
	teleop_update(&teleop, &in, (double)p_dt, &tw);

	bool published = false;
	if (session_ok) {
		/* geometry_msgs/Twist en CDR: 6 doubles = 48 bytes (main.c). */
		ucdrBuffer ub;
		if (uxr_prepare_output_stream(&session, stream_out, cmdvel_dw_id,
				&ub, 6 * 8)) {
			ucdr_serialize_double(&ub, tw.lin_x);
			ucdr_serialize_double(&ub, tw.lin_y);
			ucdr_serialize_double(&ub, tw.lin_z);
			ucdr_serialize_double(&ub, tw.ang_x);
			ucdr_serialize_double(&ub, tw.ang_y);
			ucdr_serialize_double(&ub, tw.ang_z);
			published = true;
		}
	}

	Dictionary out;
	out["lin_x"] = tw.lin_x;
	out["lin_y"] = tw.lin_y;
	out["ang_z"] = tw.ang_z;
	out["vel_lineal"] = teleop.vel_lineal;
	out["vel_lateral"] = teleop.vel_lateral;
	out["published"] = published;
	return out;
}

void MicroROS::spin(int p_ms) {
	if (session_ok) {
		uxr_run_session_time(&session, p_ms);
	}
}

void MicroROS::netlog(const String &p_msg) {
	netlog_printf("%s\n", p_msg.utf8().get_data());
}

void MicroROS::shutdown() {
	if (session_ok) {
		uxr_delete_session(&session);
		uxr_close_custom_transport(&transport);
		session_ok = false;
	}
	if (netlog_ok) {
		netlog_shutdown();
		netlog_ok = false;
	}
	if (net_ok) {
		net_udp_shutdown();
		net_ok = false;
	}
}

void MicroROS::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "agent_ip", "netlog_ip"),
			&MicroROS::setup);
	ClassDB::bind_method(D_METHOD("connect_agent"),
			&MicroROS::connect_agent);
	ClassDB::bind_method(D_METHOD("is_session_active"),
			&MicroROS::is_session_active);
	ClassDB::bind_method(D_METHOD("teleop_step", "input", "dt"),
			&MicroROS::teleop_step);
	ClassDB::bind_method(D_METHOD("spin", "ms"), &MicroROS::spin);
	ClassDB::bind_method(D_METHOD("netlog", "msg"), &MicroROS::netlog);
	ClassDB::bind_method(D_METHOD("shutdown"), &MicroROS::shutdown);
}

MicroROS::MicroROS() {
	singleton = this;
	net_ok = false;
	netlog_ok = false;
	session_ok = false;
	teleop_init(&teleop);
}

MicroROS::~MicroROS() {
	shutdown();
	singleton = nullptr;
}
