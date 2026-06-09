/**
 * net_udp.h — Contrato C-ABI del módulo dual `net-udp`.
 *
 * ESTE HEADER ES LA VERDAD DEL MÓDULO (docs/03-estrategia-dual-rust-cpp.md).
 *
 * Qué es: la capa de red más baja del proyecto. Encapsula la inicialización
 * del stack de red y los sockets UDP "conectados" a un destino fijo (el
 * micro-ROS Agent). `microros-transport` consume este módulo; nada por
 * encima de él toca sockets directamente.
 *
 * Plataformas (cada implementación resuelve ambas):
 *  - PS Vita: sceNet/sceNetCtl (sceNetSocket, sceNetSendto, ...). La parte
 *    Vita se compila en el PC con VitaSDK y se valida en hardware.
 *  - Host (laptop/PC Linux): sockets POSIX. Permite ejecutar los tests de
 *    paridad sin la consola.
 *
 * Diseño sin malloc: los sockets viven en una tabla estática interna de
 * NET_UDP_MAX_SOCKETS entradas. Agotar la tabla hace fallar net_udp_open.
 */
#ifndef VITA_NET_UDP_H
#define VITA_NET_UDP_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Máximo de sockets UDP simultáneos (tabla estática interna). */
#define NET_UDP_MAX_SOCKETS 4

/* Códigos de estado. 0 = éxito, negativos = error. Los que devuelven
 * tamaño usan int32_t: >= 0 bytes, < 0 es uno de estos códigos. */
typedef enum {
    NET_UDP_OK              = 0,
    NET_UDP_ERR_INVALID_ARG = -1, /* puntero nulo, len 0, ip mal formada    */
    NET_UDP_ERR_NOT_INIT    = -2, /* se llamó open sin net_udp_init previo  */
    NET_UDP_ERR_INIT        = -3, /* falló la inicialización del stack      */
    NET_UDP_ERR_SOCKET      = -4, /* fallo creando/configurando el socket   */
    NET_UDP_ERR_SEND        = -5, /* fallo de envío                         */
    NET_UDP_ERR_TIMEOUT     = -6, /* recv: expiró el timeout sin datos      */
    NET_UDP_ERR_RECV        = -7, /* fallo de recepción distinto de timeout */
} net_udp_status;

/* Handle opaco a una entrada de la tabla estática interna. */
typedef struct net_udp_socket net_udp_socket;

/**
 * Inicializa el stack de red de la plataforma. Idempotente: llamadas
 * repetidas devuelven NET_UDP_OK sin efecto.
 *  - Vita: carga SCE_SYSMODULE_NET, sceNetInit con pool estático, sceNetCtlInit.
 *  - Host: solo marca el módulo como inicializado.
 */
net_udp_status net_udp_init(void);

/**
 * Libera el stack de red. Tras esto, open vuelve a requerir init.
 * Los sockets abiertos quedan invalidados (cerrarlos antes es responsabilidad
 * del llamador).
 */
void net_udp_shutdown(void);

/**
 * Abre un socket UDP lógicamente conectado a `ip:port` (IPv4).
 *  - `ip`: cadena "a.b.c.d" (cada octeto 0-255, sin espacios).
 *  - `port`: puerto destino (1-65535).
 * Devuelve NULL si: módulo sin inicializar, ip NULL o mal formada, port 0,
 * tabla de sockets agotada, o fallo del SO al crear el socket.
 */
net_udp_socket *net_udp_open(const char *ip, uint16_t port);

/** Cierra el socket y libera su entrada de la tabla. NULL es no-op. */
void net_udp_close(net_udp_socket *sock);

/**
 * Envía `len` bytes al destino del socket.
 * Devuelve los bytes enviados (>= 0) o un código negativo:
 * NET_UDP_ERR_INVALID_ARG (sock/buf NULL o len 0), NET_UDP_ERR_SEND.
 */
int32_t net_udp_send(net_udp_socket *sock, const uint8_t *buf, size_t len);

/**
 * Recibe hasta `cap` bytes con timeout.
 *  - `timeout_ms` > 0: espera hasta ese tiempo; NET_UDP_ERR_TIMEOUT si expira.
 *  - `timeout_ms` == 0: sondeo no bloqueante (TIMEOUT si no hay datos ya).
 *  - `timeout_ms` < 0: NET_UDP_ERR_INVALID_ARG.
 * sock/buf NULL o cap 0 -> NET_UDP_ERR_INVALID_ARG.
 * Devuelve los bytes recibidos (>= 0; un datagrama UDP vacío da 0) o un
 * código negativo.
 */
int32_t net_udp_recv(net_udp_socket *sock, uint8_t *buf, size_t cap,
                     int32_t timeout_ms);

#ifdef __cplusplus
}
#endif

#endif /* VITA_NET_UDP_H */
