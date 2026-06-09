/**
 * parity_test.c — Batería de paridad del módulo `microros-transport`.
 *
 * Igual que en net-udp: un peer UDP POSIX en loopback hace de
 * "micro-agente" de eco. Aquí lo importante es la convención uxr:
 * bytes devueltos + errcode (timeout devuelve 0 con errcode 0,
 * error devuelve 0 con errcode 1).
 */
#include "microros_transport.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#ifndef IMPL_NAME
#define IMPL_NAME "?"
#endif

static int failures = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            failures++;                                                    \
            printf("  FALLO [%s:%d] %s\n", __FILE__, __LINE__, #cond);     \
        }                                                                  \
    } while (0)

static int peer_fd = -1;
static uint16_t peer_port = 0;

static void peer_setup(void)
{
    peer_fd = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in sin;
    memset(&sin, 0, sizeof sin);
    sin.sin_family = AF_INET;
    sin.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    CHECK(bind(peer_fd, (struct sockaddr *)&sin, sizeof sin) == 0);
    socklen_t len = sizeof sin;
    CHECK(getsockname(peer_fd, (struct sockaddr *)&sin, &len) == 0);
    peer_port = ntohs(sin.sin_port);
    struct timeval tv = {2, 0};
    setsockopt(peer_fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
}

static void test_before_open(void)
{
    uint8_t buf[8] = {0};
    uint8_t err = 99;

    CHECK(microros_transport_is_open() == false);
    CHECK(microros_transport_write(buf, 8, &err) == 0);
    CHECK(err == 1); /* transporte cerrado = error, no timeout */
    err = 99;
    CHECK(microros_transport_read(buf, 8, 10, &err) == 0);
    CHECK(err == 1);
    CHECK(microros_transport_close() == false); /* nada que cerrar */
}

static void test_open_lifecycle(void)
{
    CHECK(microros_transport_open("999.0.0.1", 1234) == false); /* ip inválida */
    CHECK(microros_transport_open(NULL, 1234) == false);
    CHECK(microros_transport_open("127.0.0.1", 0) == false);

    CHECK(microros_transport_open("127.0.0.1", peer_port) == true);
    CHECK(microros_transport_is_open() == true);
    /* segundo open sin close: rechazado, y el transporte sigue abierto */
    CHECK(microros_transport_open("127.0.0.1", peer_port) == false);
    CHECK(microros_transport_is_open() == true);

    CHECK(microros_transport_close() == true);
    CHECK(microros_transport_is_open() == false);
    CHECK(microros_transport_close() == false); /* doble close */

    /* reabrir tras cerrar funciona */
    CHECK(microros_transport_open("127.0.0.1", peer_port) == true);
}

static void test_write_read_roundtrip(void)
{
    /* (transporte abierto por el test anterior) */
    const uint8_t msg[] = "xrce-hello";
    uint8_t err = 99;
    CHECK(microros_transport_write(msg, sizeof msg, &err) == sizeof msg);
    CHECK(err == 0);

    uint8_t peer_buf[64];
    struct sockaddr_in src;
    socklen_t src_len = sizeof src;
    ssize_t got = recvfrom(peer_fd, peer_buf, sizeof peer_buf, 0,
                           (struct sockaddr *)&src, &src_len);
    CHECK(got == (ssize_t)sizeof msg);
    CHECK(memcmp(peer_buf, msg, sizeof msg) == 0);

    const uint8_t reply[] = "xrce-ack";
    CHECK(sendto(peer_fd, reply, sizeof reply, 0,
                 (struct sockaddr *)&src, src_len) == (ssize_t)sizeof reply);

    uint8_t rx[64];
    err = 99;
    CHECK(microros_transport_read(rx, sizeof rx, 1000, &err) == sizeof reply);
    CHECK(err == 0);
    CHECK(memcmp(rx, reply, sizeof reply) == 0);

    /* errcode NULL se tolera (el contrato lo permite) */
    CHECK(microros_transport_write(msg, sizeof msg, NULL) == sizeof msg);
    recvfrom(peer_fd, peer_buf, sizeof peer_buf, 0, NULL, NULL); /* drenar */
}

static void test_read_timeout_vs_error(void)
{
    uint8_t rx[16];
    uint8_t err = 99;

    /* timeout: 0 bytes y errcode 0 — uxr reintenta, no aborta */
    CHECK(microros_transport_read(rx, sizeof rx, 50, &err) == 0);
    CHECK(err == 0);
    /* sondeo no bloqueante: igual */
    err = 99;
    CHECK(microros_transport_read(rx, sizeof rx, 0, &err) == 0);
    CHECK(err == 0);
    /* timeout negativo: error de argumento -> errcode 1 */
    err = 99;
    CHECK(microros_transport_read(rx, sizeof rx, -5, &err) == 0);
    CHECK(err == 1);
    /* buffer NULL: error */
    err = 99;
    CHECK(microros_transport_read(NULL, sizeof rx, 10, &err) == 0);
    CHECK(err == 1);
}

static void test_write_invalid_args(void)
{
    uint8_t err = 99;
    const uint8_t msg[] = "x";
    CHECK(microros_transport_write(NULL, 1, &err) == 0);
    CHECK(err == 1);
    err = 99;
    CHECK(microros_transport_write(msg, 0, &err) == 0);
    CHECK(err == 1);
}

int main(void)
{
    printf("== parity_test microros-transport [impl=%s] ==\n", IMPL_NAME);
    peer_setup();

    test_before_open();
    test_open_lifecycle();
    test_write_read_roundtrip();
    test_read_timeout_vs_error();
    test_write_invalid_args();

    microros_transport_close();
    close(peer_fd);

    if (failures == 0) {
        printf("OK: todos los casos pasaron [impl=%s]\n", IMPL_NAME);
        return 0;
    }
    printf("FALLOS: %d [impl=%s]\n", failures, IMPL_NAME);
    return 1;
}
