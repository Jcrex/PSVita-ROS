/**
 * uxr_glue.h — Adaptador entre nuestro módulo dual `microros-transport`
 * y la interfaz uxrCustomTransport de microxrcedds_client.
 *
 * Este archivo SÍ incluye headers de micro-ROS, por eso vive en la app
 * (que solo se compila en el PC con la lib real) y no en el módulo.
 */
#ifndef VITA_UXR_GLUE_H
#define VITA_UXR_GLUE_H

#include <uxr/client/client.h>

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Parámetros que open() recibe vía el puntero args del transporte. */
typedef struct {
    const char *agent_ip;
    uint16_t agent_port;
} vita_transport_args;

/**
 * Registra los 4 callbacks en `transport` e inicializa con `args`.
 * Devuelve true si uxr_init_custom_transport tuvo éxito (socket abierto).
 */
bool vita_uxr_transport_init(uxrCustomTransport *transport,
                             vita_transport_args *args);

#ifdef __cplusplus
}
#endif

#endif /* VITA_UXR_GLUE_H */
