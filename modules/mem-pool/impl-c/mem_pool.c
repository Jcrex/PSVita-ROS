/**
 * mem_pool.c — Implementación C del módulo dual `mem-pool`.
 *
 * Respaldo permanente de impl-rust/ (regla del proyecto: C/C++ nunca queda
 * desactualizado respecto a Rust). Sin dependencias de plataforma: compila
 * igual en host (tests de paridad) y bajo VitaSDK/newlib.
 */
#include "mem_pool.h"

#include <stdint.h>

/* La cabecera de control ocupa los primeros bytes del backing. Se reservan
 * 64 bytes (más que sizeof(struct) en cualquier plataforma de 32/64 bits)
 * para que mem_pool_required_size() sea idéntico entre implementaciones. */
#define POOL_HEADER_BYTES 64u
#define POOL_ALIGN 8u

struct mem_pool {
    uint8_t *blocks_start;  /* inicio del área de bloques                 */
    size_t   eff_block_size;/* tamaño de bloque redondeado a POOL_ALIGN   */
    size_t   block_count;   /* bloques totales                            */
    size_t   blocks_free;   /* bloques libres ahora                       */
    void    *free_head;     /* cabeza de la free-list intrusiva           */
};

static size_t round_up_align(size_t n)
{
    return (n + (POOL_ALIGN - 1)) & ~(size_t)(POOL_ALIGN - 1);
}

static size_t effective_block_size(size_t block_size)
{
    /* Mínimo 8 bytes: un bloque libre almacena el puntero al siguiente.
     * Si el redondeo a 8 desbordara size_t, devolvemos 0 (= inválido). */
    if (block_size > SIZE_MAX - (POOL_ALIGN - 1)) {
        return 0;
    }
    size_t eff = block_size < POOL_ALIGN ? POOL_ALIGN : block_size;
    return round_up_align(eff);
}

size_t mem_pool_required_size(size_t block_size, size_t block_count)
{
    if (block_size == 0 || block_count == 0) {
        return 0;
    }
    size_t eff = effective_block_size(block_size);
    if (eff == 0) {
        return 0;
    }
    if (block_count > (SIZE_MAX - POOL_HEADER_BYTES) / eff) {
        return 0; /* desbordaría size_t */
    }
    return POOL_HEADER_BYTES + eff * block_count;
}

mem_pool *mem_pool_create(void *backing, size_t backing_len,
                          size_t block_size, size_t block_count)
{
    if (backing == NULL || block_size == 0 || block_count == 0) {
        return NULL;
    }
    if (((uintptr_t)backing & (POOL_ALIGN - 1)) != 0) {
        return NULL; /* el respaldo debe venir alineado a 8 */
    }
    size_t required = mem_pool_required_size(block_size, block_count);
    if (required == 0 || backing_len < required) {
        return NULL;
    }

    mem_pool *pool = (mem_pool *)backing;
    pool->blocks_start   = (uint8_t *)backing + POOL_HEADER_BYTES;
    pool->eff_block_size = effective_block_size(block_size);
    pool->block_count    = block_count;
    pool->blocks_free    = block_count;

    /* Encadenar todos los bloques en la free-list, en orden de dirección. */
    pool->free_head = NULL;
    for (size_t i = block_count; i > 0; i--) {
        uint8_t *blk = pool->blocks_start + (i - 1) * pool->eff_block_size;
        *(void **)blk = pool->free_head;
        pool->free_head = blk;
    }
    return pool;
}

void *mem_pool_alloc(mem_pool *pool)
{
    if (pool == NULL || pool->free_head == NULL) {
        return NULL;
    }
    void *blk = pool->free_head;
    pool->free_head = *(void **)blk; /* avanzar la cabeza de la free-list */
    pool->blocks_free--;
    return blk;
}

mem_pool_status mem_pool_free(mem_pool *pool, void *block)
{
    if (pool == NULL || block == NULL) {
        return MEM_POOL_ERR_INVALID_ARG;
    }

    uint8_t *blk = (uint8_t *)block;
    uint8_t *end = pool->blocks_start + pool->block_count * pool->eff_block_size;
    if (blk < pool->blocks_start || blk >= end) {
        return MEM_POOL_ERR_BAD_PTR; /* no pertenece al pool */
    }
    if ((size_t)(blk - pool->blocks_start) % pool->eff_block_size != 0) {
        return MEM_POOL_ERR_BAD_PTR; /* no apunta al inicio de un bloque */
    }
    /* Detección de doble free: recorrer la free-list. O(n), aceptable para
     * los pools pequeños de micro-ROS y vale el coste por seguridad. */
    for (void *cur = pool->free_head; cur != NULL; cur = *(void **)cur) {
        if (cur == block) {
            return MEM_POOL_ERR_BAD_PTR;
        }
    }

    *(void **)blk = pool->free_head;
    pool->free_head = blk;
    pool->blocks_free++;
    return MEM_POOL_OK;
}

size_t mem_pool_blocks_free(const mem_pool *pool)
{
    return pool == NULL ? 0 : pool->blocks_free;
}

size_t mem_pool_block_size(const mem_pool *pool)
{
    return pool == NULL ? 0 : pool->eff_block_size;
}
