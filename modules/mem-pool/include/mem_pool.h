/**
 * mem_pool.h — Contrato C-ABI del módulo dual `mem-pool`.
 *
 * ESTE HEADER ES LA VERDAD DEL MÓDULO (ver docs/03-estrategia-dual-rust-cpp.md).
 * Las dos implementaciones (impl-c/ e impl-rust/) cumplen exactamente esta
 * interfaz y deben pasar la misma batería de tests de paridad.
 *
 * Qué es: un asignador de memoria por pools de bloques de tamaño fijo.
 * micro-ROS lo usará para sus asignaciones internas, evitando la
 * fragmentación del heap y los fallos tardíos de malloc() en sesiones
 * largas (la app de la Vita corre indefinidamente como nodo ROS2).
 *
 * Diseño:
 *  - El llamador aporta el buffer de respaldo (`backing`); el pool NO llama
 *    a malloc. Esto permite ubicarlo en memoria estática de la app Vita.
 *  - La estructura de control vive al inicio del propio buffer de respaldo.
 *  - Los bloques libres se encadenan en una free-list intrusiva: cada bloque
 *    libre guarda en sus primeros bytes el puntero al siguiente libre.
 *  - Alineación garantizada de los bloques: 8 bytes.
 */
#ifndef VITA_MEM_POOL_H
#define VITA_MEM_POOL_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Códigos de estado. 0 = éxito, negativos = error (convención del proyecto). */
typedef enum {
    MEM_POOL_OK              = 0,
    MEM_POOL_ERR_INVALID_ARG = -1, /* puntero nulo o parámetro fuera de rango  */
    MEM_POOL_ERR_BAD_PTR     = -2, /* bloque ajeno al pool, desalineado o ya libre */
} mem_pool_status;

/* Handle opaco: el layout interno es asunto de cada implementación. */
typedef struct mem_pool mem_pool;

/**
 * Bytes de respaldo necesarios para un pool de `block_count` bloques de
 * `block_size` bytes. Devuelve 0 si algún parámetro es 0 o si el cálculo
 * desbordaría size_t.
 *
 * Nota de paridad: ambas implementaciones devuelven EXACTAMENTE el mismo
 * valor: cabecera de control de 64 bytes + bloques redondeados a 8 bytes
 * (mínimo 8, para alojar el puntero de la free-list).
 */
size_t mem_pool_required_size(size_t block_size, size_t block_count);

/**
 * Inicializa un pool dentro de `backing` (de `backing_len` bytes).
 * Devuelve el handle (que apunta dentro de `backing`) o NULL si:
 *  - backing es NULL, block_size == 0 o block_count == 0
 *  - backing_len < mem_pool_required_size(block_size, block_count)
 *  - backing no está alineado a 8 bytes
 */
mem_pool *mem_pool_create(void *backing, size_t backing_len,
                          size_t block_size, size_t block_count);

/**
 * Toma un bloque del pool. Devuelve NULL si el pool es NULL o está agotado.
 * El contenido del bloque es indeterminado (no se limpia).
 */
void *mem_pool_alloc(mem_pool *pool);

/**
 * Devuelve un bloque al pool.
 *  - MEM_POOL_ERR_INVALID_ARG si pool o block son NULL.
 *  - MEM_POOL_ERR_BAD_PTR si block no pertenece al rango del pool, no está
 *    alineado al inicio de un bloque, o ya estaba libre (doble free).
 */
mem_pool_status mem_pool_free(mem_pool *pool, void *block);

/** Bloques libres ahora mismo. 0 si pool es NULL. */
size_t mem_pool_blocks_free(const mem_pool *pool);

/** Tamaño efectivo de bloque (redondeado a 8). 0 si pool es NULL. */
size_t mem_pool_block_size(const mem_pool *pool);

#ifdef __cplusplus
}
#endif

#endif /* VITA_MEM_POOL_H */
