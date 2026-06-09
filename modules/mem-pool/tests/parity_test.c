/**
 * parity_test.c — Batería de paridad del módulo `mem-pool`.
 *
 * Este MISMO archivo se compila dos veces: una enlazado contra impl-c y
 * otra contra impl-rust (staticlib). Si algún caso difiere entre ambas,
 * el respaldo C/C++ ya no es equivalente y eso es un fallo del proyecto.
 *
 * Se ejecuta en host (laptop/PC) con gcc; no usa nada de VitaSDK.
 */
#include "mem_pool.h"

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

/* Buffer de respaldo alineado a 8, como exige el contrato. */
static uint8_t backing[4096] __attribute__((aligned(8)));

static void test_required_size(void)
{
    /* bloque de 1 byte se redondea a 8; cabecera fija de 64 */
    CHECK(mem_pool_required_size(1, 1) == 64 + 8);
    CHECK(mem_pool_required_size(8, 4) == 64 + 32);
    CHECK(mem_pool_required_size(12, 2) == 64 + 32);  /* 12 -> 16 */
    /* parámetros inválidos */
    CHECK(mem_pool_required_size(0, 10) == 0);
    CHECK(mem_pool_required_size(10, 0) == 0);
    /* desbordamiento de size_t */
    CHECK(mem_pool_required_size(SIZE_MAX, 2) == 0);
    CHECK(mem_pool_required_size(8, SIZE_MAX) == 0);
}

static void test_create_invalid(void)
{
    CHECK(mem_pool_create(NULL, sizeof backing, 16, 4) == NULL);
    CHECK(mem_pool_create(backing, sizeof backing, 0, 4) == NULL);
    CHECK(mem_pool_create(backing, sizeof backing, 16, 0) == NULL);
    /* respaldo demasiado pequeño */
    CHECK(mem_pool_create(backing, 64, 16, 4) == NULL);
    /* respaldo desalineado */
    CHECK(mem_pool_create(backing + 1, sizeof backing - 1, 16, 4) == NULL);
}

static void test_alloc_free_cycle(void)
{
    mem_pool *pool = mem_pool_create(backing, sizeof backing, 16, 4);
    CHECK(pool != NULL);
    CHECK(mem_pool_block_size(pool) == 16);
    CHECK(mem_pool_blocks_free(pool) == 4);

    void *blocks[4];
    for (int i = 0; i < 4; i++) {
        blocks[i] = mem_pool_alloc(pool);
        CHECK(blocks[i] != NULL);
        /* todos los bloques alineados a 8 */
        CHECK(((uintptr_t)blocks[i] & 7) == 0);
    }
    CHECK(mem_pool_blocks_free(pool) == 0);
    /* agotado: alloc devuelve NULL */
    CHECK(mem_pool_alloc(pool) == NULL);

    /* los 4 punteros son distintos y no se solapan */
    for (int i = 0; i < 4; i++) {
        for (int j = i + 1; j < 4; j++) {
            CHECK(blocks[i] != blocks[j]);
        }
        memset(blocks[i], i + 1, 16); /* escribir no debe romper nada */
    }

    /* liberar y volver a agotar */
    for (int i = 0; i < 4; i++) {
        CHECK(mem_pool_free(pool, blocks[i]) == MEM_POOL_OK);
    }
    CHECK(mem_pool_blocks_free(pool) == 4);
}

static void test_alloc_order_parity(void)
{
    /* El primer alloc tras crear devuelve el bloque de dirección más baja:
     * forma parte del contrato observable (paridad del orden de la free-list). */
    mem_pool *pool = mem_pool_create(backing, sizeof backing, 32, 3);
    CHECK(pool != NULL);
    uint8_t *first = mem_pool_alloc(pool);
    uint8_t *second = mem_pool_alloc(pool);
    CHECK(first != NULL && second != NULL);
    CHECK(second == first + 32);
}

static void test_free_errors(void)
{
    mem_pool *pool = mem_pool_create(backing, sizeof backing, 16, 2);
    CHECK(pool != NULL);
    void *blk = mem_pool_alloc(pool);
    CHECK(blk != NULL);

    CHECK(mem_pool_free(NULL, blk) == MEM_POOL_ERR_INVALID_ARG);
    CHECK(mem_pool_free(pool, NULL) == MEM_POOL_ERR_INVALID_ARG);
    /* puntero fuera del pool */
    static uint8_t fuera[16] __attribute__((aligned(8)));
    CHECK(mem_pool_free(pool, fuera) == MEM_POOL_ERR_BAD_PTR);
    /* puntero dentro del pool pero al interior de un bloque */
    CHECK(mem_pool_free(pool, (uint8_t *)blk + 4) == MEM_POOL_ERR_BAD_PTR);
    /* doble free */
    CHECK(mem_pool_free(pool, blk) == MEM_POOL_OK);
    CHECK(mem_pool_free(pool, blk) == MEM_POOL_ERR_BAD_PTR);
}

static void test_null_pool_queries(void)
{
    CHECK(mem_pool_blocks_free(NULL) == 0);
    CHECK(mem_pool_block_size(NULL) == 0);
    CHECK(mem_pool_alloc(NULL) == NULL);
}

int main(void)
{
    printf("== parity_test mem-pool [impl=%s] ==\n", IMPL_NAME);
    test_required_size();
    test_create_invalid();
    test_alloc_free_cycle();
    test_alloc_order_parity();
    test_free_errors();
    test_null_pool_queries();

    if (failures == 0) {
        printf("OK: todos los casos pasaron [impl=%s]\n", IMPL_NAME);
        return 0;
    }
    printf("FALLOS: %d [impl=%s]\n", failures, IMPL_NAME);
    return 1;
}
