/**
 * uxr_glue.c — los 4 callbacks uxr delegan 1:1 en microros-transport.
 *
 * La firma de los callbacks es la de microxrcedds_client (uxrCustomTransport).
 * Si la versión de la lib cambia firmas, ESTE es el único archivo a tocar:
 * el módulo dual queda intacto.
 *
 * VALIDAR EN EL PC: compila solo con microxrcedds_client instalado
 * (ver scripts/build-xrce-client-vita.sh).
 */
#include "uxr_glue.h"

#include "microros_transport.h"

static bool glue_open(uxrCustomTransport *transport)
{
    vita_transport_args *args = (vita_transport_args *)transport->args;
    if (args == NULL) {
        return false;
    }
    return microros_transport_open(args->agent_ip, args->agent_port);
}

static bool glue_close(uxrCustomTransport *transport)
{
    (void)transport;
    return microros_transport_close();
}

static size_t glue_write(uxrCustomTransport *transport, const uint8_t *buf,
                         size_t len, uint8_t *errcode)
{
    (void)transport;
    return microros_transport_write(buf, len, errcode);
}

static size_t glue_read(uxrCustomTransport *transport, uint8_t *buf,
                        size_t len, int timeout, uint8_t *errcode)
{
    (void)transport;
    return microros_transport_read(buf, len, (int32_t)timeout, errcode);
}

bool vita_uxr_transport_init(uxrCustomTransport *transport,
                             vita_transport_args *args)
{
    /* false = sin framing: UDP ya delimita datagramas (el framing es para
     * transportes de stream como el serie). */
    uxr_set_custom_transport_callbacks(transport, false, glue_open,
                                       glue_close, glue_write, glue_read);
    return uxr_init_custom_transport(transport, args);
}
