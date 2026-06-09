/**
 * main.c — App homebrew de la Fase 1: "Vita ROS2 Hello".
 *
 * Objetivo (criterio de validación de docs/02-arquitectura-fase1-microros.md):
 *  1. La Vita PUBLICA en /vita_hello (std_msgs/String), visible en el PC con
 *     `ros2 topic echo /vita_hello`.
 *  2. La Vita RECIBE /pc_hello publicado desde el PC y lo confirma por log.
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
}

static bool exit_requested(void)
{
    SceCtrlData ctrl;
    sceCtrlPeekBufferPositive(0, &ctrl, 1);
    return (ctrl.buttons & SCE_CTRL_START) != 0;
}

int main(void)
{
    /* --- Red: módulo dual net-udp (sceNet por debajo) --- */
    if (net_udp_init() != NET_UDP_OK) {
        sceClibPrintf("[vita-ros2] FATAL: net_udp_init fallo\n");
        sceKernelExitProcess(1);
        return 1;
    }
    netlog_init(NETLOG_IP, NETLOG_PORT);
    LOG("[vita-ros2] red inicializada; agente=%s:%d\n", AGENT_IP, AGENT_PORT);

    /* --- Transporte XRCE: módulo dual microros-transport vía glue --- */
    uxrCustomTransport transport;
    vita_transport_args targs = {AGENT_IP, AGENT_PORT};
    if (!vita_uxr_transport_init(&transport, &targs)) {
        LOG("[vita-ros2] FATAL: transporte no abre (¿agente accesible?)\n");
        goto fatal;
    }

    /* --- Sesión XRCE: LA INCÓGNITA DURA SE RESPONDE AQUÍ --- */
    uxrSession session;
    uxr_init_session(&session, &transport.comm, 0xCAFE0001);
    uxr_set_topic_callback(&session, on_topic, NULL);
    if (!uxr_create_session(&session)) {
        LOG("[vita-ros2] FATAL: uxr_create_session fallo — la sesion XRCE "
            "NO levanta sobre sceNet. Documentar el muro (docs/02).\n");
        goto fatal;
    }
    LOG("[vita-ros2] *** SESION XRCE ESTABLECIDA: incognita dura OK ***\n");

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
    uint16_t req[6];
    req[0] = uxr_buffer_create_participant_xml(&session, out, participant_id,
                                               0, participant_xml, UXR_REPLACE);

    uxrObjectId pub_topic_id = uxr_object_id(0x01, UXR_TOPIC_ID);
    const char *pub_topic_xml =
        "<dds><topic><name>rt/vita_hello</name>"
        "<dataType>std_msgs::msg::dds_::String_</dataType></topic></dds>";
    req[1] = uxr_buffer_create_topic_xml(&session, out, pub_topic_id,
                                         participant_id, pub_topic_xml,
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

    uint8_t status[6];
    if (!uxr_run_session_until_all_status(&session, 3000, req, status, 6)) {
        LOG("[vita-ros2] FATAL: el agente rechazo entidades DDS "
            "(status: %d %d %d %d %d %d)\n", status[0], status[1], status[2],
            status[3], status[4], status[5]);
        goto fatal;
    }
    LOG("[vita-ros2] entidades creadas: pub /vita_hello, sub /pc_hello\n");

    /* Pedir al agente que nos reenvíe datos del datareader sin límite. */
    uxrDeliveryControl delivery = {0};
    delivery.max_samples = UXR_MAX_SAMPLES_UNLIMITED;
    uxr_buffer_request_data(&session, out, datareader_id, in, &delivery);

    /* --- Bucle principal: publicar 1 Hz, atender la sesión, salir con START */
    sceCtrlSetSamplingMode(SCE_CTRL_MODE_DIGITAL);
    uint32_t count = 0;
    while (!exit_requested()) {
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

        /* run_session atiende heartbeats, ACKs y datos entrantes. */
        uxr_run_session_time(&session, 1000 /* ms */);

        if (g_pc_hello_received) {
            g_pc_hello_received = false;
            LOG("[vita-ros2] criterio 2 de la Fase 1 CUMPLIDO (rx desde PC)\n");
        }
    }

    LOG("[vita-ros2] saliendo (START pulsado tras %lu mensajes)\n",
        (unsigned long)count);
    uxr_delete_session(&session);
    uxr_close_custom_transport(&transport);
    netlog_shutdown();
    net_udp_shutdown();
    sceKernelExitProcess(0);
    return 0;

fatal:
    netlog_shutdown();
    net_udp_shutdown();
    sceKernelDelayThread(5 * 1000 * 1000); /* 5 s para leer el log */
    sceKernelExitProcess(1);
    return 1;
}
