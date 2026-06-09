/**
 * microros_transport.h — Contrato C-ABI del módulo dual `microros-transport`.
 *
 * ESTE HEADER ES LA VERDAD DEL MÓDULO (docs/03-estrategia-dual-rust-cpp.md).
 *
 * Qué es: los 4 callbacks del transporte personalizado de micro-ROS
 * (open / close / write / read) implementados sobre el módulo `net-udp`.
 * Es el núcleo de la incógnita dura de la Fase 1 (docs/02): si la sesión
 * XRCE no levanta sobre este transporte, no hay Fase 1.
 *
 * Relación con micro-ROS: `microxrcedds_client` define la interfaz
 * uxrCustomTransport con firmas casi idénticas a estas. Este módulo NO
 * incluye headers de micro-ROS (no existen en la laptop): expone funciones
 * propias con la misma semántica, y un pegamento trivial en la app
 * (vita-app/src/uxr_glue.c) las adapta a uxr_set_custom_transport_callbacks
 * cuando se compila en el PC con la lib real.
 *
 * Semántica de errcode (convención uxr):
 *  - éxito: devuelve bytes procesados, *errcode = 0
 *  - timeout en read: devuelve 0, *errcode = 0
 *  - error real: devuelve 0, *errcode = 1
 *  - errcode puede ser NULL (se ignora la escritura)
 *
 * Estado global: hay UN solo transporte por app (una sesión XRCE con un
 * agente). open() con el transporte ya abierto falla; hay que close() antes.
 */
#ifndef VITA_MICROROS_TRANSPORT_H
#define VITA_MICROROS_TRANSPORT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Abre el transporte hacia el agente micro-ROS.
 *  - `agent_ip`: IPv4 "a.b.c.d" (la valida net-udp).
 *  - `agent_port`: puerto UDP del agente (p. ej. 8888).
 * Inicializa net-udp si hace falta y abre el socket UDP conectado.
 * false si: ya estaba abierto, ip/puerto inválidos o fallo de red.
 */
bool microros_transport_open(const char *agent_ip, uint16_t agent_port);

/** Cierra el transporte. false si no estaba abierto. */
bool microros_transport_close(void);

/** ¿Hay transporte abierto? (consulta, no toca la red) */
bool microros_transport_is_open(void);

/**
 * Envía `len` bytes al agente (un datagrama).
 * Devuelve los bytes enviados; 0 con *errcode=1 si hay error o el
 * transporte no está abierto.
 */
size_t microros_transport_write(const uint8_t *buf, size_t len,
                                uint8_t *errcode);

/**
 * Lee hasta `cap` bytes con `timeout_ms`.
 *  - datos: devuelve n > 0, *errcode = 0
 *  - timeout (o sondeo con timeout 0 sin datos): devuelve 0, *errcode = 0
 *  - error (incl. transporte cerrado, args inválidos, timeout_ms < 0):
 *    devuelve 0, *errcode = 1
 */
size_t microros_transport_read(uint8_t *buf, size_t cap, int32_t timeout_ms,
                               uint8_t *errcode);

#ifdef __cplusplus
}
#endif

#endif /* VITA_MICROROS_TRANSPORT_H */
