/**
 * main.c — App homebrew: Fase 1 ("Vita ROS2 Hello") + Objetivo 2 (teleop).
 *
 * Fase 1 (criterios de docs/02-arquitectura-fase1-microros.md, CERRADA):
 *  1. La Vita PUBLICA en /vita_hello (std_msgs/String), visible en el PC con
 *     `ros2 topic echo /vita_hello`.
 *  2. La Vita RECIBE /pc_hello publicado desde el PC y lo confirma por log.
 *
 * Objetivo 2 (docs/09-objetivo2-control-robot.md): la Vita es un mando de
 * teleoperación ROS2 — publica geometry_msgs/Twist en /cmd_vel (~20 Hz)
 * desde sticks y botones. El mapeo mandos->Twist vive en teleop.c (lógica
 * pura, testeada en host con scripts/check-teleop.sh); aquí solo se hace
 * el puente SceCtrlData -> teleop_entrada y la serialización CDR.
 *
 * Cadena: esta app -> uxr_glue -> microros-transport -> net-udp -> WiFi/UDP
 *         -> micro-ROS Agent (Docker) -> grafo ROS2 Jazzy.
 *
 * SE COMPILA EN EL PC con VitaSDK + microxrcedds_client (ver README y
 * scripts/build-xrce-client-vita.sh). La incógnita dura se valida aquí:
 * si uxr_create_session() devuelve true sobre nuestro transporte, la
 * Fase 1 está desbloqueada.
 *
 * Nota sobre los nombres DDS: ROS2 antepone prefijos a los nombres crudos.
 * El topic ROS2 /vita_hello es "rt/vita_hello" en DDS, y el tipo
 * std_msgs/msg/String es "std_msgs::msg::dds_::String_". Si esto no se
 * respeta, el agente crea las entidades pero ros2 no las ve como propias.
 */
#include <psp2/ctrl.h>
#include <psp2/kernel/clib.h>
#include <psp2/kernel/processmgr.h>
#include <psp2/kernel/threadmgr.h>

#include <uxr/client/client.h>
#include <ucdr/microcdr.h>

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "net_udp.h"
#include "netlog.h"
#include "teleop.h"
#include "ui.h"
#include "uxr_glue.h"

/* ---------------------------------------------------------------- */
/* Configuración (se puede sobreescribir con -D en CMake)            */
/* ---------------------------------------------------------------- */
#ifndef AGENT_IP
#define AGENT_IP "192.168.1.108" /* laptop: corre el agente en la red WiFi */
#endif
#ifndef AGENT_PORT
#define AGENT_PORT 8888
#endif
#ifndef NETLOG_IP
#define NETLOG_IP "192.168.1.108" /* laptop: nc -u -l -p 9999 */
#endif
#ifndef NETLOG_PORT
#define NETLOG_PORT 9999
#endif

#define STREAM_BUFFER_SIZE 4096
#define STREAM_HISTORY 4

/* Log doble: PrincessLog (sceClibPrintf) + UDP a la laptop. */
#define LOG(...)                      \
    do {                              \
        sceClibPrintf(__VA_ARGS__);  \
        netlog_printf(__VA_ARGS__);  \
    } while (0)

static uint8_t g_output_stream[STREAM_BUFFER_SIZE * STREAM_HISTORY];
static uint8_t g_input_stream[STREAM_BUFFER_SIZE * STREAM_HISTORY];

static bool g_pc_hello_received = false;

/* Estado que la UI declarativa muestra vía bindings (ui_types.h). La app
 * lo actualiza en el bucle principal y ui_draw() lo pinta cada frame. */
static ui_state g_ui;

/* Callback de suscripción: el agente nos entrega un topic serializado CDR.
 * std_msgs/String es solo un campo `data: string`; en CDR un string es
 * uint32 longitud (incluye el NUL) + bytes. ucdr lo deserializa directo. */
static void on_topic(uxrSession *session, uxrObjectId object_id,
                     uint16_t request_id, uxrStreamId stream_id,
                     struct ucdrBuffer *ub, uint16_t length, void *args)
{
    (void)session; (void)object_id; (void)request_id;
    (void)stream_id; (void)length; (void)args;

    char data[256] = {0};
    ucdr_deserialize_string(ub, data, sizeof data);
    LOG("[vita-ros2] /pc_hello recibido: \"%s\"\n", data);
    g_pc_hello_received = true;
    snprintf(g_ui.ultimo_pc_hello, sizeof g_ui.ultimo_pc_hello, "%s", data);
}

/* Puente SceCtrlData -> teleop_entrada (la lógica del mapeo vive en
 * teleop.c; aquí solo se traducen los campos crudos de sceCtrl). */
static teleop_entrada leer_mandos(const SceCtrlData *ctrl)
{
    teleop_entrada in;
    in.lx = ctrl->lx;
    in.ly = ctrl->ly;
    in.rx = ctrl->rx;
    in.ry = ctrl->ry;
    in.arriba = (ctrl->buttons & SCE_CTRL_UP) != 0;
    in.abajo = (ctrl->buttons & SCE_CTRL_DOWN) != 0;
    in.izquierda = (ctrl->buttons & SCE_CTRL_LEFT) != 0;
    in.derecha = (ctrl->buttons & SCE_CTRL_RIGHT) != 0;
    in.l = (ctrl->buttons & SCE_CTRL_LTRIGGER) != 0;
    in.r = (ctrl->buttons & SCE_CTRL_RTRIGGER) != 0;
    in.cruz = (ctrl->buttons & SCE_CTRL_CROSS) != 0;
    in.triangulo = (ctrl->buttons & SCE_CTRL_TRIANGLE) != 0;
    return in;
}

int main(void)
{
    /* --- Red: módulo dual net-udp (sceNet por debajo) --- */
    if (net_udp_init() != NET_UDP_OK) {
        sceClibPrintf("[vita-ros2] FATAL: net_udp_init fallo\n");
        sceKernelExitProcess(1);
        return 1;
    }
    if (!netlog_init(NETLOG_IP, NETLOG_PORT)) {
        sceClibPrintf("[vita-ros2] WARN: netlog_init fallo (ip=%s:%d); "
                       "sin logs UDP, solo sceClibPrintf\n",
                       NETLOG_IP, NETLOG_PORT);
    }
    LOG("[vita-ros2] red inicializada; agente=%s:%d\n", AGENT_IP, AGENT_PORT);

    /* --- UI declarativa (vita2d + ui_layout.h generado; ADR 0005) ---
     * Si la fuente PGF no carga seguimos sin UI (headless como la Fase 1):
     * la conectividad ROS2 no depende de la pantalla. */
    if (!ui_init()) {
        LOG("[vita-ros2] WARN: ui_init fallo; sigo sin UI en pantalla\n");
    }
    snprintf(g_ui.agente, sizeof g_ui.agente, "%s:%d", AGENT_IP, AGENT_PORT);

    /* --- Transporte XRCE: módulo dual microros-transport vía glue --- */
    uxrCustomTransport transport;
    vita_transport_args targs = {AGENT_IP, AGENT_PORT};
    if (!vita_uxr_transport_init(&transport, &targs)) {
        LOG("[vita-ros2] FATAL: transporte no abre (¿agente accesible?)\n");
        ui_draw_fatal("El transporte UDP no abre (agente accesible?)", 5);
        goto fatal;
    }

    /* --- Sesión XRCE: LA INCÓGNITA DURA SE RESPONDE AQUÍ --- */
    uxrSession session;
    uxr_init_session(&session, &transport.comm, 0xCAFE0001);
    uxr_set_topic_callback(&session, on_topic, NULL);
    if (!uxr_create_session(&session)) {
        LOG("[vita-ros2] FATAL: uxr_create_session fallo — la sesion XRCE "
            "NO levanta sobre sceNet. Documentar el muro (docs/02).\n");
        ui_draw_fatal("uxr_create_session fallo (sesion XRCE no levanta)", 5);
        goto fatal;
    }
    LOG("[vita-ros2] *** SESION XRCE ESTABLECIDA: incognita dura OK ***\n");
    g_ui.conectado = true; /* v1: refleja el arranque, no la salud continua */

    /* Streams confiables (XRCE reenvía lo perdido sobre UDP). */
    uxrStreamId out = uxr_create_output_reliable_stream(
        &session, g_output_stream, sizeof g_output_stream, STREAM_HISTORY);
    uxrStreamId in = uxr_create_input_reliable_stream(
        &session, g_input_stream, sizeof g_input_stream, STREAM_HISTORY);

    /* --- Entidades DDS declaradas por XML (las materializa el agente) --- */
    uxrObjectId participant_id = uxr_object_id(0x01, UXR_PARTICIPANT_ID);
    const char *participant_xml =
        "<dds><participant><rtps><name>vita_node</name></rtps>"
        "</participant></dds>";
    uint16_t req[8];
    req[0] = uxr_buffer_create_participant_xml(&session, out, participant_id,
                                               0, participant_xml, UXR_REPLACE);

    uxrObjectId pub_topic_id = uxr_object_id(0x01, UXR_TOPIC_ID);
    const char *pub_topic_xml =
        "<dds><topic><name>rt/vita_hello</name>"
        "<dataType>std_msgs::msg::dds_::String_</dataType></topic></dds>";
    req[1] = uxr_buffer_create_topic_xml(&session, out, pub_topic_id,
                                         participant_id, pub_topic_xml,
                                         UXR_REPLACE);

    /* Objetivo 2: /cmd_vel (rt/cmd_vel, geometry_msgs::msg::dds_::Twist_).
     * Mismo participante y mismo publisher; topic y datawriter propios. */
    uxrObjectId cmdvel_topic_id = uxr_object_id(0x03, UXR_TOPIC_ID);
    const char *cmdvel_topic_xml =
        "<dds><topic><name>rt/cmd_vel</name>"
        "<dataType>geometry_msgs::msg::dds_::Twist_</dataType></topic></dds>";
    req[6] = uxr_buffer_create_topic_xml(&session, out, cmdvel_topic_id,
                                         participant_id, cmdvel_topic_xml,
                                         UXR_REPLACE);

    uxrObjectId publisher_id = uxr_object_id(0x01, UXR_PUBLISHER_ID);
    req[2] = uxr_buffer_create_publisher_xml(&session, out, publisher_id,
                                             participant_id, "", UXR_REPLACE);

    uxrObjectId datawriter_id = uxr_object_id(0x01, UXR_DATAWRITER_ID);
    const char *datawriter_xml =
        "<dds><data_writer><topic><kind>NO_KEY</kind>"
        "<name>rt/vita_hello</name>"
        "<dataType>std_msgs::msg::dds_::String_</dataType></topic>"
        "</data_writer></dds>";
    req[3] = uxr_buffer_create_datawriter_xml(&session, out, datawriter_id,
                                              publisher_id, datawriter_xml,
                                              UXR_REPLACE);

    uxrObjectId cmdvel_dw_id = uxr_object_id(0x02, UXR_DATAWRITER_ID);
    const char *cmdvel_dw_xml =
        "<dds><data_writer><topic><kind>NO_KEY</kind>"
        "<name>rt/cmd_vel</name>"
        "<dataType>geometry_msgs::msg::dds_::Twist_</dataType></topic>"
        "</data_writer></dds>";
    req[7] = uxr_buffer_create_datawriter_xml(&session, out, cmdvel_dw_id,
                                              publisher_id, cmdvel_dw_xml,
                                              UXR_REPLACE);

    uxrObjectId sub_topic_id = uxr_object_id(0x02, UXR_TOPIC_ID);
    const char *sub_topic_xml =
        "<dds><topic><name>rt/pc_hello</name>"
        "<dataType>std_msgs::msg::dds_::String_</dataType></topic></dds>";
    uxr_buffer_create_topic_xml(&session, out, sub_topic_id, participant_id,
                                sub_topic_xml, UXR_REPLACE);

    uxrObjectId subscriber_id = uxr_object_id(0x01, UXR_SUBSCRIBER_ID);
    req[4] = uxr_buffer_create_subscriber_xml(&session, out, subscriber_id,
                                              participant_id, "", UXR_REPLACE);

    uxrObjectId datareader_id = uxr_object_id(0x01, UXR_DATAREADER_ID);
    const char *datareader_xml =
        "<dds><data_reader><topic><kind>NO_KEY</kind>"
        "<name>rt/pc_hello</name>"
        "<dataType>std_msgs::msg::dds_::String_</dataType></topic>"
        "</data_reader></dds>";
    req[5] = uxr_buffer_create_datareader_xml(&session, out, datareader_id,
                                              subscriber_id, datareader_xml,
                                              UXR_REPLACE);

    uint8_t status[8];
    if (!uxr_run_session_until_all_status(&session, 3000, req, status, 8)) {
        LOG("[vita-ros2] FATAL: el agente rechazo entidades DDS "
            "(status: %d %d %d %d %d %d %d %d)\n", status[0], status[1],
            status[2], status[3], status[4], status[5], status[6], status[7]);
        ui_draw_fatal("El agente rechazo las entidades DDS", 5);
        goto fatal;
    }
    LOG("[vita-ros2] entidades creadas: pub /vita_hello + /cmd_vel, "
        "sub /pc_hello\n");

    /* Pedir al agente que nos reenvíe datos del datareader sin límite. */
    uxrDeliveryControl delivery = {0};
    delivery.max_samples = UXR_MAX_SAMPLES_UNLIMITED;
    uxr_buffer_request_data(&session, out, datareader_id, in, &delivery);

    /* --- Bucle principal: /vita_hello a 1 Hz por timestamp, /cmd_vel una
     * vez por vuelta (run_session tarda 50 ms => ~20 Hz, lo que espera un
     * robot real), la sesión atendida en tramos de 50 ms y la UI
     * redibujada en cada vuelta. Salir con START. --- */
    sceCtrlSetSamplingMode(SCE_CTRL_MODE_ANALOG); /* Objetivo 2: sticks */
    teleop_estado teleop;
    teleop_init(&teleop);
    /* Ojo: los floats se preformatean con snprintf (newlib) porque
     * sceClibPrintf no soporta %f. */
    char linea_log[96];
    snprintf(linea_log, sizeof linea_log,
             "[vita-ros2] teleop /cmd_vel activo: vel=%.1f lateral=%.1f "
             "(mapeo en docs/09)", teleop.vel_lineal, teleop.vel_lateral);
    LOG("%s\n", linea_log);

    uint32_t count = 0;
    uint32_t count_cmd = 0;
    uint64_t proxima_pub = sceKernelGetProcessTimeWide(); /* microsegundos */
    uint64_t t_prev = sceKernelGetProcessTimeWide();
    SceCtrlData ctrl;
    while (sceCtrlPeekBufferPositive(0, &ctrl, 1),
           (ctrl.buttons & SCE_CTRL_START) == 0) {
        if (sceKernelGetProcessTimeWide() >= proxima_pub) {
            proxima_pub += 1000000; /* 1 Hz */
            char msg[96];
            snprintf(msg, sizeof msg, "hola desde la vita #%lu",
                     (unsigned long)count);

            /* Serializar std_msgs/String a CDR: uint32 len + bytes + NUL. */
            ucdrBuffer ub;
            uint32_t topic_size = ucdr_alignment(0, 4) + 4 +
                                  (uint32_t)strlen(msg) + 1;
            if (uxr_prepare_output_stream(&session, out, datawriter_id, &ub,
                                          topic_size)) {
                ucdr_serialize_string(&ub, msg);
                count++;
            }
        }

        /* --- Objetivo 2: mandos -> Twist -> /cmd_vel --- */
        uint64_t ahora = sceKernelGetProcessTimeWide();
        double dt_s = (double)(ahora - t_prev) / 1e6;
        t_prev = ahora;

        teleop_entrada mandos = leer_mandos(&ctrl);
        double vel_antes = teleop.vel_lineal;
        teleop_twist tw;
        teleop_update(&teleop, &mandos, dt_s, &tw);
        if (teleop.vel_lineal != vel_antes) {
            /* Solo cambia en flancos de triangulo/X: no inunda el netlog. */
            snprintf(linea_log, sizeof linea_log,
                     "[vita-ros2] vel_lineal %s a %.1f%s",
                     teleop.vel_lineal > vel_antes ? "sube" : "baja",
                     teleop.vel_lineal,
                     teleop.vel_lineal == 0.0 ? " (STOP)" : "");
            LOG("%s\n", linea_log);
        }

        /* geometry_msgs/Twist en CDR: 6 doubles seguidos (linear.xyz +
         * angular.xyz), todos alineados a 8 desde el offset 0 => 48 bytes. */
        ucdrBuffer ub_tw;
        if (uxr_prepare_output_stream(&session, out, cmdvel_dw_id, &ub_tw,
                                      6 * 8)) {
            ucdr_serialize_double(&ub_tw, tw.lin_x);
            ucdr_serialize_double(&ub_tw, tw.lin_y);
            ucdr_serialize_double(&ub_tw, tw.lin_z);
            ucdr_serialize_double(&ub_tw, tw.ang_x);
            ucdr_serialize_double(&ub_tw, tw.ang_y);
            ucdr_serialize_double(&ub_tw, tw.ang_z);
            count_cmd++;
        }

        /* run_session atiende heartbeats, ACKs y datos entrantes. */
        uxr_run_session_time(&session, 50 /* ms */);

        if (g_pc_hello_received) {
            g_pc_hello_received = false;
            LOG("[vita-ros2] criterio 2 de la Fase 1 CUMPLIDO (rx desde PC)\n");
        }

        g_ui.contador = count;
        g_ui.contador_cmd = count_cmd;
        g_ui.vel_lineal = (float)teleop.vel_lineal;
        g_ui.vel_lateral = (float)teleop.vel_lateral;
        g_ui.lin_x = (float)tw.lin_x;
        g_ui.lin_y = (float)tw.lin_y;
        g_ui.ang_z = (float)tw.ang_z;
        ui_draw(&g_ui);
    }

    LOG("[vita-ros2] saliendo (START pulsado tras %lu hellos y %lu "
        "cmd_vel)\n", (unsigned long)count, (unsigned long)count_cmd);
    uxr_delete_session(&session);
    uxr_close_custom_transport(&transport);
    ui_shutdown();
    netlog_shutdown();
    net_udp_shutdown();
    sceKernelExitProcess(0);
    return 0;

fatal:
    ui_shutdown();
    netlog_shutdown();
    net_udp_shutdown();
    sceKernelDelayThread(5 * 1000 * 1000); /* 5 s para leer el log */
    sceKernelExitProcess(1);
    return 1;
}
