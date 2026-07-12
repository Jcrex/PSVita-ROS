/**
 * micro_ros_gd.h — Singleton `MicroROS` expuesto a GDScript.
 *
 * Puente delgado (docs/12): NO contiene lógica propia. Reutiliza:
 *   - vita-app/src/uxr_glue.c   (transporte custom XRCE sobre net-udp)
 *   - vita-app/src/netlog.c     (log UDP a la laptop, puerto 9999)
 *   - vita-app/src/teleop.c     (mapeo mandos -> Twist, testeado en host)
 *   - vita-app/src/config.c     (validación de IPs)
 *   - modules/{mem-pool,net-udp,microros-transport} (variante C o Rust)
 *
 * Espejo de vita-app/src/main.c sin /vita_hello ni /pc_hello (docs/12:
 * el alcance es el teleop). Solo compila para platform=vita (config.py).
 * VALIDAR EN EL PC: en la laptop no hay headers de Godot ni libs cross.
 */
#ifndef MICRO_ROS_GD_H
#define MICRO_ROS_GD_H

#include "core/dictionary.h"
#include "core/object.h"
#include "core/ustring.h"

#include <uxr/client/client.h>

#include "teleop.h"
#include "uxr_glue.h"

#define MICROROS_AGENT_PORT 8888
#define MICROROS_NETLOG_PORT 9999
#define MICROROS_STREAM_BUFFER_SIZE 4096
#define MICROROS_STREAM_HISTORY 4

class MicroROS : public Object {
	GDCLASS(MicroROS, Object);

	static MicroROS *singleton;

	/* Estado de red/sesión (espejo de main.c). */
	bool net_ok;
	bool netlog_ok;
	bool session_ok;
	/* El transporte guarda el puntero a la IP: debe vivir lo que la
	 * sesión (en main.c era una variable de main(); aquí, un miembro). */
	CharString agent_ip;
	uxrCustomTransport transport;
	vita_transport_args targs;
	uxrSession session;
	uxrStreamId stream_out;
	uxrObjectId cmdvel_dw_id;
	uint8_t output_stream_buf[MICROROS_STREAM_BUFFER_SIZE *
			MICROROS_STREAM_HISTORY];

	/* Estado del teleop (la lógica vive en teleop.c). */
	teleop_estado teleop;

protected:
	static void _bind_methods();

public:
	static MicroROS *get_singleton();

	/* Valida IPs (config.c), levanta net-udp y el netlog. */
	bool setup(const String &p_agent_ip, const String &p_netlog_ip);
	/* Transporte + sesión XRCE + entidades DDS de /cmd_vel. */
	bool connect_agent();
	bool is_session_active() const;
	/* Una vuelta del teleop: dict de mandos -> teleop.c -> publica el
	 * Twist. Devuelve {lin_x, lin_y, ang_z, vel_lineal, vel_lateral,
	 * published}. */
	Dictionary teleop_step(const Dictionary &p_input, float p_dt);
	/* Atiende la sesión XRCE (heartbeats/ACKs) hasta p_ms milisegundos. */
	void spin(int p_ms);
	void netlog(const String &p_msg);
	void shutdown();

	MicroROS();
	~MicroROS();
};

#endif /* MICRO_ROS_GD_H */
