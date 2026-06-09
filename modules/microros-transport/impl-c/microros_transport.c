/**
 * microros_transport.c — Implementación C del módulo dual `microros-transport`.
 *
 * Adaptador fino sobre `net-udp`: traduce la semántica de errores de
 * net_udp (códigos negativos) a la convención uxr (bytes + errcode).
 * No contiene #ifdef de plataforma: toda la diferencia Vita/host vive
 * dentro de net-udp.
 */
#include "microros_transport.h"

#include "net_udp.h"

/* El único transporte de la app (una sesión XRCE <-> un agente). */
static net_udp_socket *g_sock = NULL;

static void set_errcode(uint8_t *errcode, uint8_t value)
{
    if (errcode != NULL) {
        *errcode = value;
    }
}

bool microros_transport_open(const char *agent_ip, uint16_t agent_port)
{
    if (g_sock != NULL) {
        return false; /* ya abierto: cerrar antes de reabrir */
    }
    if (net_udp_init() != NET_UDP_OK) {
        return false;
    }
    g_sock = net_udp_open(agent_ip, agent_port);
    return g_sock != NULL;
}

bool microros_transport_close(void)
{
    if (g_sock == NULL) {
        return false;
    }
    net_udp_close(g_sock);
    g_sock = NULL;
    return true;
}

bool microros_transport_is_open(void)
{
    return g_sock != NULL;
}

size_t microros_transport_write(const uint8_t *buf, size_t len,
                                uint8_t *errcode)
{
    if (g_sock == NULL) {
        set_errcode(errcode, 1);
        return 0;
    }
    int32_t sent = net_udp_send(g_sock, buf, len);
    if (sent < 0) {
        set_errcode(errcode, 1);
        return 0;
    }
    set_errcode(errcode, 0);
    return (size_t)sent;
}

size_t microros_transport_read(uint8_t *buf, size_t cap, int32_t timeout_ms,
                               uint8_t *errcode)
{
    if (g_sock == NULL) {
        set_errcode(errcode, 1);
        return 0;
    }
    int32_t got = net_udp_recv(g_sock, buf, cap, timeout_ms);
    if (got == NET_UDP_ERR_TIMEOUT) {
        set_errcode(errcode, 0); /* timeout NO es error para uxr */
        return 0;
    }
    if (got < 0) {
        set_errcode(errcode, 1);
        return 0;
    }
    set_errcode(errcode, 0);
    return (size_t)got;
}
