/**
 * net_udp.c — Implementación C del módulo dual `net-udp`.
 *
 * Dos plataformas dentro del mismo archivo, separadas por #ifdef __vita__:
 *  - Vita: sceNet/sceNetCtl. Compila solo con VitaSDK (en el PC). Los pasos
 *    de inicialización siguen el orden requerido por el SO de la consola
 *    (sysmodule -> sceNetInit con pool -> sceNetCtlInit). VALIDAR EN HARDWARE.
 *  - Host (Linux): sockets POSIX, para los tests de paridad en laptop/PC.
 */
#include "net_udp.h"

#include <string.h>

#ifdef __vita__
#include <psp2/net/net.h>
#include <psp2/net/netctl.h>
#include <psp2/sysmodule.h>
#else
#include <errno.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#endif

/* ------------------------------------------------------------------ */
/* Estado interno: tabla estática de sockets, sin malloc.              */
/* ------------------------------------------------------------------ */

struct net_udp_socket {
    int     fd;
    uint8_t in_use;
};

static struct net_udp_socket g_sockets[NET_UDP_MAX_SOCKETS];
static uint8_t g_initialized = 0;

#ifdef __vita__
/* Pool de memoria que exige sceNetInit. 1 MiB es holgado para micro-ROS. */
static char g_net_pool[1024 * 1024] __attribute__((aligned(4096)));
#endif

/* ------------------------------------------------------------------ */
/* Parser IPv4 propio.                                                 */
/* Se implementa a mano (y de forma idéntica en impl-rust) para que el */
/* comportamiento ante cadenas mal formadas no dependa de la libc de   */
/* cada plataforma: misma entrada -> mismo resultado, siempre.         */
/* Devuelve 1 y deja la dirección en big-endian en *out_be, o 0.       */
/* ------------------------------------------------------------------ */
static int parse_ipv4(const char *ip, uint32_t *out_be)
{
    uint32_t addr = 0;
    int octet_idx = 0;
    const char *p = ip;

    while (octet_idx < 4) {
        if (*p < '0' || *p > '9') {
            return 0; /* cada octeto empieza por un dígito */
        }
        uint32_t value = 0;
        int digits = 0;
        while (*p >= '0' && *p <= '9') {
            value = value * 10 + (uint32_t)(*p - '0');
            digits++;
            if (digits > 3 || value > 255) {
                return 0;
            }
            p++;
        }
        addr = (addr << 8) | value;
        octet_idx++;
        if (octet_idx < 4) {
            if (*p != '.') {
                return 0;
            }
            p++;
        }
    }
    if (*p != '\0') {
        return 0; /* basura tras el último octeto */
    }
    /* addr quedó en orden de red conceptual (a en el byte alto); lo
     * serializamos explícitamente a big-endian sin depender de htonl. */
    *out_be = ((addr & 0x000000FFu) << 24) | ((addr & 0x0000FF00u) << 8) |
              ((addr & 0x00FF0000u) >> 8)  | ((addr & 0xFF000000u) >> 24);
    return 1;
}

static uint16_t port_to_be(uint16_t port)
{
    return (uint16_t)((port << 8) | (port >> 8));
}

/* ------------------------------------------------------------------ */
/* init / shutdown                                                     */
/* ------------------------------------------------------------------ */

net_udp_status net_udp_init(void)
{
    if (g_initialized) {
        return NET_UDP_OK;
    }
#ifdef __vita__
    sceSysmoduleLoadModule(SCE_SYSMODULE_NET);

    SceNetInitParam param;
    param.memory = g_net_pool;
    param.size   = sizeof(g_net_pool);
    param.flags  = 0;
    int rc = sceNetInit(&param);
    /* SCE_NET_ERROR_EBUSY: el stack ya estaba inicializado por otro módulo
     * de la app; no es un fallo para nosotros. */
    if (rc < 0 && (unsigned)rc != 0x80410110u /* SCE_NET_ERROR_EBUSY */) {
        return NET_UDP_ERR_INIT;
    }
    rc = sceNetCtlInit();
    if (rc < 0 && (unsigned)rc != 0x80412102u /* NETCTL ya iniciado */) {
        return NET_UDP_ERR_INIT;
    }
#endif
    memset(g_sockets, 0, sizeof(g_sockets));
    for (int i = 0; i < NET_UDP_MAX_SOCKETS; i++) {
        g_sockets[i].fd = -1;
    }
    g_initialized = 1;
    return NET_UDP_OK;
}

void net_udp_shutdown(void)
{
    if (!g_initialized) {
        return;
    }
    for (int i = 0; i < NET_UDP_MAX_SOCKETS; i++) {
        if (g_sockets[i].in_use) {
            net_udp_close(&g_sockets[i]);
        }
    }
#ifdef __vita__
    sceNetCtlTerm();
    sceNetTerm();
#endif
    g_initialized = 0;
}

/* ------------------------------------------------------------------ */
/* open / close                                                        */
/* ------------------------------------------------------------------ */

net_udp_socket *net_udp_open(const char *ip, uint16_t port)
{
    if (!g_initialized || ip == NULL || port == 0) {
        return NULL;
    }
    uint32_t addr_be;
    if (!parse_ipv4(ip, &addr_be)) {
        return NULL;
    }

    net_udp_socket *slot = NULL;
    for (int i = 0; i < NET_UDP_MAX_SOCKETS; i++) {
        if (!g_sockets[i].in_use) {
            slot = &g_sockets[i];
            break;
        }
    }
    if (slot == NULL) {
        return NULL; /* tabla agotada */
    }

#ifdef __vita__
    int fd = sceNetSocket("net_udp", SCE_NET_AF_INET, SCE_NET_SOCK_DGRAM, 0);
    if (fd < 0) {
        return NULL;
    }
    SceNetSockaddrIn sin;
    memset(&sin, 0, sizeof(sin));
    sin.sin_len         = sizeof(sin);
    sin.sin_family      = SCE_NET_AF_INET;
    sin.sin_port        = port_to_be(port);
    sin.sin_addr.s_addr = addr_be;
    /* "Conectar" un socket UDP solo fija el destino por defecto y filtra
     * los datagramas entrantes de otros orígenes. No hay handshake. */
    if (sceNetConnect(fd, (SceNetSockaddr *)&sin, sizeof(sin)) < 0) {
        sceNetSocketClose(fd);
        return NULL;
    }
#else
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        return NULL;
    }
    struct sockaddr_in sin;
    memset(&sin, 0, sizeof(sin));
    sin.sin_family      = AF_INET;
    sin.sin_port        = port_to_be(port);
    sin.sin_addr.s_addr = addr_be;
    if (connect(fd, (struct sockaddr *)&sin, sizeof(sin)) < 0) {
        close(fd);
        return NULL;
    }
#endif

    slot->fd = fd;
    slot->in_use = 1;
    return slot;
}

void net_udp_close(net_udp_socket *sock)
{
    if (sock == NULL || !sock->in_use) {
        return;
    }
#ifdef __vita__
    sceNetSocketClose(sock->fd);
#else
    close(sock->fd);
#endif
    sock->fd = -1;
    sock->in_use = 0;
}

/* ------------------------------------------------------------------ */
/* send / recv                                                         */
/* ------------------------------------------------------------------ */

int32_t net_udp_send(net_udp_socket *sock, const uint8_t *buf, size_t len)
{
    if (sock == NULL || !sock->in_use || buf == NULL || len == 0) {
        return NET_UDP_ERR_INVALID_ARG;
    }
#ifdef __vita__
    int sent = sceNetSend(sock->fd, buf, len, 0);
    if (sent < 0) {
        return NET_UDP_ERR_SEND;
    }
#else
    ssize_t sent = send(sock->fd, buf, len, 0);
    if (sent < 0) {
        return NET_UDP_ERR_SEND;
    }
#endif
    return (int32_t)sent;
}

int32_t net_udp_recv(net_udp_socket *sock, uint8_t *buf, size_t cap,
                     int32_t timeout_ms)
{
    if (sock == NULL || !sock->in_use || buf == NULL || cap == 0 ||
        timeout_ms < 0) {
        return NET_UDP_ERR_INVALID_ARG;
    }

#ifdef __vita__
    int flags = 0;
    if (timeout_ms == 0) {
        flags = SCE_NET_MSG_DONTWAIT;
    } else {
        /* SCE_NET_SO_RCVTIMEO se expresa en microsegundos (int). */
        int usec = timeout_ms * 1000;
        if (sceNetSetsockopt(sock->fd, SCE_NET_SOL_SOCKET,
                             SCE_NET_SO_RCVTIMEO, &usec, sizeof(usec)) < 0) {
            return NET_UDP_ERR_RECV;
        }
    }
    int got = sceNetRecv(sock->fd, buf, cap, flags);
    if (got < 0) {
        /* EAGAIN/EWOULDBLOCK == sin datos dentro del plazo. */
        if ((unsigned)got == 0x80410223u /* SCE_NET_ERROR_EAGAIN */) {
            return NET_UDP_ERR_TIMEOUT;
        }
        return NET_UDP_ERR_RECV;
    }
    return (int32_t)got;
#else
    int flags = 0;
    if (timeout_ms == 0) {
        flags = MSG_DONTWAIT;
    } else {
        struct timeval tv;
        tv.tv_sec  = timeout_ms / 1000;
        tv.tv_usec = (timeout_ms % 1000) * 1000;
        if (setsockopt(sock->fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) < 0) {
            return NET_UDP_ERR_RECV;
        }
    }
    ssize_t got = recv(sock->fd, buf, cap, flags);
    if (got < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return NET_UDP_ERR_TIMEOUT;
        }
        return NET_UDP_ERR_RECV;
    }
    return (int32_t)got;
#endif
}
