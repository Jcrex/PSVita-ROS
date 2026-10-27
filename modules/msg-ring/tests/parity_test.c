/**
 * parity_test.c — Batería de paridad del módulo `msg-ring`.
 * El MISMO archivo se enlaza contra impl-c y contra impl-rust (staticlib).
 * Incluye una prueba de estrés con DOS hilos reales (productor/consumidor).
 */
#include "msg_ring.h"

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

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

static uint8_t backing[1 << 16] __attribute__((aligned(8)));

static void test_required_size(void)
{
    /* stride = redondeo8(4 + slot_size); total = 64 + stride * n */
    CHECK(msg_ring_required_size(1, 1) == 64 + 8);
    CHECK(msg_ring_required_size(4, 2) == 64 + 2 * 8);
    CHECK(msg_ring_required_size(5, 4) == 64 + 4 * 16);   /* 4+5=9 -> 16 */
    CHECK(msg_ring_required_size(60, 8) == 64 + 8 * 64);
    /* inválidos */
    CHECK(msg_ring_required_size(0, 4) == 0);
    CHECK(msg_ring_required_size(8, 0) == 0);
    CHECK(msg_ring_required_size(8, 3) == 0);             /* no potencia de 2 */
    CHECK(msg_ring_required_size(8, (size_t)1 << 31) == 0);
    CHECK(msg_ring_required_size(SIZE_MAX, 2) == 0);
    CHECK(msg_ring_required_size((size_t)UINT32_MAX, 2) == 0);
}

static void test_create_invalid(void)
{
    size_t need = msg_ring_required_size(16, 4);
    CHECK(msg_ring_create(NULL, sizeof backing, 16, 4) == NULL);
    CHECK(msg_ring_create(backing + 1, sizeof backing - 1, 16, 4) == NULL);
    CHECK(msg_ring_create(backing, need - 1, 16, 4) == NULL);
    CHECK(msg_ring_create(backing, sizeof backing, 16, 3) == NULL);
    CHECK(msg_ring_create(backing, sizeof backing, 0, 4) == NULL);
    CHECK(msg_ring_create(backing, need, 16, 4) != NULL);
}

static void test_basic_fifo(void)
{
    msg_ring *r = msg_ring_create(backing, sizeof backing, 16, 4);
    CHECK(r != NULL);
    CHECK(msg_ring_capacity(r) == 4);
    CHECK(msg_ring_slot_size(r) == 16);
    CHECK(msg_ring_count(r) == 0);

    uint8_t out[16];
    size_t n = 99;
    CHECK(msg_ring_pop(r, out, sizeof out, &n) == MSG_RING_ERR_EMPTY);

    CHECK(msg_ring_push(r, "uno", 3) == MSG_RING_OK);
    CHECK(msg_ring_push(r, "dos!", 4) == MSG_RING_OK);
    CHECK(msg_ring_count(r) == 2);

    CHECK(msg_ring_pop(r, out, sizeof out, &n) == MSG_RING_OK);
    CHECK(n == 3 && memcmp(out, "uno", 3) == 0);
    CHECK(msg_ring_pop(r, out, sizeof out, &n) == MSG_RING_OK);
    CHECK(n == 4 && memcmp(out, "dos!", 4) == 0);
    CHECK(msg_ring_count(r) == 0);
    CHECK(msg_ring_dropped(r) == 0);
}

static void test_full_and_dropped(void)
{
    msg_ring *r = msg_ring_create(backing, sizeof backing, 8, 4);
    uint8_t v;
    for (v = 0; v < 4; v++) {
        CHECK(msg_ring_push(r, &v, 1) == MSG_RING_OK);
    }
    v = 99;
    CHECK(msg_ring_push(r, &v, 1) == MSG_RING_ERR_FULL);
    CHECK(msg_ring_push(r, &v, 1) == MSG_RING_ERR_FULL);
    CHECK(msg_ring_dropped(r) == 2);
    CHECK(msg_ring_count(r) == 4);

    /* los 4 originales siguen en orden; el 99 se descartó */
    uint8_t out[8];
    size_t n;
    for (v = 0; v < 4; v++) {
        CHECK(msg_ring_pop(r, out, sizeof out, &n) == MSG_RING_OK);
        CHECK(n == 1 && out[0] == v);
    }
    /* y vuelve a aceptar */
    CHECK(msg_ring_push(r, &v, 1) == MSG_RING_OK);
}

static void test_sizes_and_errors(void)
{
    msg_ring *r = msg_ring_create(backing, sizeof backing, 8, 2);
    uint8_t big[9] = {0};
    uint8_t out[8];
    size_t n = 0;

    CHECK(msg_ring_push(r, big, 9) == MSG_RING_ERR_TOO_BIG);
    CHECK(msg_ring_push(r, big, 8) == MSG_RING_OK);      /* exacto cabe */
    CHECK(msg_ring_push(r, NULL, 0) == MSG_RING_OK);     /* vacío válido */
    CHECK(msg_ring_push(r, NULL, 1) == MSG_RING_ERR_INVALID_ARG);
    CHECK(msg_ring_push(NULL, big, 1) == MSG_RING_ERR_INVALID_ARG);

    /* pop con buffer pequeño: error, NO consume, informa tamaño */
    CHECK(msg_ring_pop(r, out, 4, &n) == MSG_RING_ERR_BUF_SMALL);
    CHECK(n == 8);
    CHECK(msg_ring_count(r) == 2);
    CHECK(msg_ring_pop(r, out, 8, &n) == MSG_RING_OK && n == 8);
    CHECK(msg_ring_pop(r, out, 8, &n) == MSG_RING_OK && n == 0); /* el vacío */
    CHECK(msg_ring_pop(r, out, 8, NULL) == MSG_RING_ERR_INVALID_ARG);
    CHECK(msg_ring_pop(NULL, out, 8, &n) == MSG_RING_ERR_INVALID_ARG);

    CHECK(msg_ring_count(NULL) == 0);
    CHECK(msg_ring_dropped(NULL) == 0);
    CHECK(msg_ring_capacity(NULL) == 0);
    CHECK(msg_ring_slot_size(NULL) == 0);
}

static void test_wraparound(void)
{
    /* Muchas más vueltas que ranuras: ejercita la máscara y el wrap de u32. */
    msg_ring *r = msg_ring_create(backing, sizeof backing, 8, 4);
    for (uint32_t i = 0; i < 100000; i++) {
        uint32_t out = 0;
        size_t n = 0;
        CHECK(msg_ring_push(r, &i, sizeof i) == MSG_RING_OK);
        CHECK(msg_ring_pop(r, &out, sizeof out, &n) == MSG_RING_OK);
        if (out != i || n != sizeof i) {
            failures++;
            printf("  FALLO wraparound i=%u out=%u\n", i, out);
            break;
        }
    }
}

/* ---- Estrés con 2 hilos: orden estricto, sin pérdidas ni duplicados ---- */
#define STRESS_N 2000000u
static msg_ring *g_ring;
static volatile int g_stress_ok = 1;

static void *producer(void *arg)
{
    (void)arg;
    for (uint32_t i = 0; i < STRESS_N; i++) {
        uint32_t msg[2] = { i, ~i };       /* payload verificable */
        while (msg_ring_push(g_ring, msg, sizeof msg) != MSG_RING_OK) {
            /* cola llena: reintentar (el contador dropped sube, es esperado) */
        }
    }
    return NULL;
}

static void *consumer(void *arg)
{
    (void)arg;
    for (uint32_t expect = 0; expect < STRESS_N;) {
        uint32_t msg[2];
        size_t n;
        int rc = msg_ring_pop(g_ring, msg, sizeof msg, &n);
        if (rc == MSG_RING_ERR_EMPTY) {
            continue;
        }
        if (rc != MSG_RING_OK || n != sizeof msg || msg[0] != expect ||
            msg[1] != ~expect) {
            g_stress_ok = 0;
            return NULL;
        }
        expect++;
    }
    return NULL;
}

static void test_two_thread_stress(void)
{
    /* cola pequeña (8) para forzar muchísimas colisiones llena/vacía */
    g_ring = msg_ring_create(backing, sizeof backing, 8, 8);
    pthread_t p, c;
    CHECK(pthread_create(&c, NULL, consumer, NULL) == 0);
    CHECK(pthread_create(&p, NULL, producer, NULL) == 0);
    pthread_join(p, NULL);
    pthread_join(c, NULL);
    CHECK(g_stress_ok);
    CHECK(msg_ring_count(g_ring) == 0);
}

int main(void)
{
    printf("== parity_test msg-ring [impl=%s] ==\n", IMPL_NAME);
    test_required_size();
    test_create_invalid();
    test_basic_fifo();
    test_full_and_dropped();
    test_sizes_and_errors();
    test_wraparound();
    test_two_thread_stress();
    if (failures) {
        printf("FALLARON %d comprobaciones [impl=%s]\n", failures, IMPL_NAME);
        return 1;
    }
    printf("OK: todos los casos pasaron [impl=%s]\n", IMPL_NAME);
    return 0;
}
