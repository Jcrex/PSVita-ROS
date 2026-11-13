/**
 * netlog.c — implementación del log UDP sobre el módulo net-udp.
 * Sin dualidad: es código de app (alto nivel), C/C++ a secas por regla
 * del proyecto (docs/03, "qué no necesita ser dual").
 */
#include "netlog.h"

#include "net_udp.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static net_udp_socket *g_log_sock = NULL;

bool netlog_init(const char *ip, uint16_t port)
{
    if (g_log_sock != NULL) {
        return true;
    }
    g_log_sock = net_udp_open(ip, port);
    return g_log_sock != NULL;
}

void netlog_printf(const char *fmt, ...)
{
    if (g_log_sock == NULL) {
        return;
    }
    char line[512];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    if (n <= 0) {
        return;
    }
    if ((size_t)n >= sizeof line) {
        n = sizeof line - 1; /* truncado */
    }
    net_udp_send(g_log_sock, (const uint8_t *)line, (size_t)n);
}

void netlog_shutdown(void)
{
    if (g_log_sock != NULL) {
        net_udp_close(g_log_sock);
        g_log_sock = NULL;
    }
}
