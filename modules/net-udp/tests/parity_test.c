/**
 * parity_test.c — Batería de paridad del módulo `net-udp`.
 *
 * Se compila dos veces (impl-c / impl-rust) y debe dar idéntico resultado.
 * El test corre SOLO en host: crea un "peer" UDP con sockets POSIX puros
 * (el test puede usar libc libremente; las implementaciones no) que hace de
 * micro-agente de eco en 127.0.0.1, sin hilos: UDP almacena en el buffer
 * del kernel, así que send/recv pueden secuenciarse.
 */
#include "net_udp.h"

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

/* Peer UDP de prueba: socket POSIX ligado a 127.0.0.1 con puerto efímero. */
static int peer_fd = -1;
static uint16_t peer_port = 0;

static void peer_setup(void)
{
    peer_fd = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in sin;
    memset(&sin, 0, sizeof sin);
    sin.sin_family = AF_INET;
    sin.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    sin.sin_port = 0; /* el kernel elige puerto */
    CHECK(bind(peer_fd, (struct sockaddr *)&sin, sizeof sin) == 0);
    socklen_t len = sizeof sin;
    CHECK(getsockname(peer_fd, (struct sockaddr *)&sin, &len) == 0);
    peer_port = ntohs(sin.sin_port);
    /* timeout de seguridad para que el test nunca se cuelgue */
    struct timeval tv = {2, 0};
    setsockopt(peer_fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
}

static void test_init_shutdown(void)
{
    /* open antes de init -> NULL */
    CHECK(net_udp_open("127.0.0.1", 9999) == NULL);
    CHECK(net_udp_init() == NET_UDP_OK);
    CHECK(net_udp_init() == NET_UDP_OK); /* idempotente */
    net_udp_shutdown();
    CHECK(net_udp_open("127.0.0.1", 9999) == NULL); /* requiere init otra vez */
    CHECK(net_udp_init() == NET_UDP_OK);
}

static void test_open_invalid(void)
{
    CHECK(net_udp_open(NULL, 1234) == NULL);
    CHECK(net_udp_open("127.0.0.1", 0) == NULL);
    /* parser IPv4 propio: misma semántica en ambas implementaciones */
    CHECK(net_udp_open("", 1234) == NULL);
    CHECK(net_udp_open("256.1.1.1", 1234) == NULL);
    CHECK(net_udp_open("1.2.3", 1234) == NULL);
    CHECK(net_udp_open("1.2.3.4.5", 1234) == NULL);
    CHECK(net_udp_open("a.b.c.d", 1234) == NULL);
    CHECK(net_udp_open("1..2.3", 1234) == NULL);
    CHECK(net_udp_open("1.2.3.4 ", 1234) == NULL);
    CHECK(net_udp_open("-1.2.3.4", 1234) == NULL);
    CHECK(net_udp_open("1234.1.1.1", 1234) == NULL);
    /* ceros a la izquierda son válidos (<= 3 dígitos, valor <= 255) */
    net_udp_socket *s = net_udp_open("01.2.3.4", 1234);
    CHECK(s != NULL);
    net_udp_close(s);
}

static void test_socket_table_exhaustion(void)
{
    net_udp_socket *socks[NET_UDP_MAX_SOCKETS];
    for (int i = 0; i < NET_UDP_MAX_SOCKETS; i++) {
        socks[i] = net_udp_open("127.0.0.1", 9000 + i);
        CHECK(socks[i] != NULL);
    }
    /* tabla llena */
    CHECK(net_udp_open("127.0.0.1", 9100) == NULL);
    /* liberar una entrada permite abrir de nuevo */
    net_udp_close(socks[0]);
    socks[0] = net_udp_open("127.0.0.1", 9100);
    CHECK(socks[0] != NULL);
    for (int i = 0; i < NET_UDP_MAX_SOCKETS; i++) {
        net_udp_close(socks[i]);
    }
    /* close de NULL es no-op seguro */
    net_udp_close(NULL);
}

static void test_send_recv_roundtrip(void)
{
    net_udp_socket *s = net_udp_open("127.0.0.1", peer_port);
    CHECK(s != NULL);

    const uint8_t msg[] = "hola agente";
    CHECK(net_udp_send(s, msg, sizeof msg) == (int32_t)sizeof msg);

    /* el peer recibe y responde al puerto efímero del cliente */
    uint8_t peer_buf[64];
    struct sockaddr_in src;
    socklen_t src_len = sizeof src;
    ssize_t got = recvfrom(peer_fd, peer_buf, sizeof peer_buf, 0,
                           (struct sockaddr *)&src, &src_len);
    CHECK(got == (ssize_t)sizeof msg);
    CHECK(memcmp(peer_buf, msg, sizeof msg) == 0);

    const uint8_t reply[] = "eco";
    CHECK(sendto(peer_fd, reply, sizeof reply, 0,
                 (struct sockaddr *)&src, src_len) == (ssize_t)sizeof reply);

    uint8_t rx[64];
    int32_t n = net_udp_recv(s, rx, sizeof rx, 1000);
    CHECK(n == (int32_t)sizeof reply);
    CHECK(memcmp(rx, reply, sizeof reply) == 0);

    net_udp_close(s);
}

static void test_recv_timeout(void)
{
    net_udp_socket *s = net_udp_open("127.0.0.1", peer_port);
    CHECK(s != NULL);
    uint8_t rx[16];

    /* sin datos: timeout corto expira y devuelve ERR_TIMEOUT */
    struct timeval t0, t1;
    gettimeofday(&t0, NULL);
    CHECK(net_udp_recv(s, rx, sizeof rx, 50) == NET_UDP_ERR_TIMEOUT);
    gettimeofday(&t1, NULL);
    long elapsed_ms = (t1.tv_sec - t0.tv_sec) * 1000 +
                      (t1.tv_usec - t0.tv_usec) / 1000;
    CHECK(elapsed_ms >= 40 && elapsed_ms < 1000);

    /* timeout 0 = sondeo no bloqueante */
    CHECK(net_udp_recv(s, rx, sizeof rx, 0) == NET_UDP_ERR_TIMEOUT);
    /* timeout negativo = argumento inválido */
    CHECK(net_udp_recv(s, rx, sizeof rx, -1) == NET_UDP_ERR_INVALID_ARG);

    net_udp_close(s);
}

static void test_invalid_send_recv_args(void)
{
    net_udp_socket *s = net_udp_open("127.0.0.1", peer_port);
    CHECK(s != NULL);
    uint8_t buf[8] = {0};

    CHECK(net_udp_send(NULL, buf, 8) == NET_UDP_ERR_INVALID_ARG);
    CHECK(net_udp_send(s, NULL, 8) == NET_UDP_ERR_INVALID_ARG);
    CHECK(net_udp_send(s, buf, 0) == NET_UDP_ERR_INVALID_ARG);
    CHECK(net_udp_recv(NULL, buf, 8, 10) == NET_UDP_ERR_INVALID_ARG);
    CHECK(net_udp_recv(s, NULL, 8, 10) == NET_UDP_ERR_INVALID_ARG);
    CHECK(net_udp_recv(s, buf, 0, 10) == NET_UDP_ERR_INVALID_ARG);

    net_udp_close(s);
    /* operar sobre un socket ya cerrado también es argumento inválido */
    CHECK(net_udp_send(s, buf, 8) == NET_UDP_ERR_INVALID_ARG);
    CHECK(net_udp_recv(s, buf, 8, 10) == NET_UDP_ERR_INVALID_ARG);
}

int main(void)
{
    printf("== parity_test net-udp [impl=%s] ==\n", IMPL_NAME);
    peer_setup();

    test_init_shutdown();
    test_open_invalid();
    test_socket_table_exhaustion();
    test_send_recv_roundtrip();
    test_recv_timeout();
    test_invalid_send_recv_args();

    net_udp_shutdown();
    close(peer_fd);

    if (failures == 0) {
        printf("OK: todos los casos pasaron [impl=%s]\n", IMPL_NAME);
        return 0;
    }
    printf("FALLOS: %d [impl=%s]\n", failures, IMPL_NAME);
    return 1;
}
