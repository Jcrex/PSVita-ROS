/**
 * netlog.h — Log de la app por UDP hacia la laptop/PC.
 *
 * En la Vita no hay consola: los printf van al vacío salvo plugin
 * (PrincessLog). Este pequeño logger manda cada línea como datagrama UDP
 * usando NUESTRO módulo net-udp, así que sirve además de primera prueba
 * de fuego de la pila de red en hardware real.
 *
 * Escucha en la laptop con:  nc -u -l -p 9999
 */
#ifndef VITA_NETLOG_H
#define VITA_NETLOG_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Abre el socket de log hacia ip:port. Requiere net_udp_init() previo. */
bool netlog_init(const char *ip, uint16_t port);

/** printf por UDP (máx. 512 bytes por línea). No-op si no hay init. */
void netlog_printf(const char *fmt, ...)
    __attribute__((format(printf, 1, 2)));

/** Cierra el socket de log. */
void netlog_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif /* VITA_NETLOG_H */
