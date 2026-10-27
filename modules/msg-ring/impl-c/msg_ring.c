/**
 * msg_ring.c — Implementación C11 del contrato include/msg_ring.h.
 *
 * Usa <stdatomic.h> (VitaSDK = gcc 15 lo soporta; en la Cortex-A9 genera
 * las barreras dmb necesarias para acquire/release).
 */
#include "msg_ring.h"

#include <stdatomic.h>
#include <string.h>

#define RING_HEADER_BYTES 64u
#define RING_ALIGN 8u
#define RING_MAX_SLOTS (1u << 30)

/* Cabecera: los offsets/semántica deben coincidir con impl-rust. */
struct msg_ring {
    uint32_t slot_size;          /* bytes útiles por ranura               */
    uint32_t slot_count;         /* potencia de 2                         */
    uint32_t stride;             /* bytes por ranura (4 + slot_size → x8) */
    _Atomic uint32_t head;       /* siguiente a leer  (lo escribe el consumidor) */
    _Atomic uint32_t tail;       /* siguiente a escribir (lo escribe el productor) */
    _Atomic uint32_t dropped;    /* descartes por cola llena              */
};

_Static_assert(sizeof(struct msg_ring) <= RING_HEADER_BYTES,
               "la cabecera debe caber en 64 bytes");

static size_t stride_for(size_t slot_size)
{
    /* 4 bytes de longitud + payload, redondeado a 8. 0 si desborda. */
    if (slot_size > (size_t)UINT32_MAX - 4u - (RING_ALIGN - 1u)) {
        return 0;
    }
    return (4u + slot_size + (RING_ALIGN - 1u)) & ~(size_t)(RING_ALIGN - 1u);
}

static uint8_t *slot_ptr(const msg_ring *r, uint32_t index)
{
    uint8_t *base = (uint8_t *)r + RING_HEADER_BYTES;
    return base + (size_t)(index & (r->slot_count - 1u)) * r->stride;
}

size_t msg_ring_required_size(size_t slot_size, size_t slot_count)
{
    if (slot_size == 0 || slot_count == 0 || slot_count > RING_MAX_SLOTS ||
        (slot_count & (slot_count - 1u)) != 0) {
        return 0;
    }
    size_t stride = stride_for(slot_size);
    if (stride == 0 || stride > (SIZE_MAX - RING_HEADER_BYTES) / slot_count) {
        return 0;
    }
    return RING_HEADER_BYTES + stride * slot_count;
}

msg_ring *msg_ring_create(void *backing, size_t backing_len,
                          size_t slot_size, size_t slot_count)
{
    if (backing == NULL || ((uintptr_t)backing & (RING_ALIGN - 1u)) != 0) {
        return NULL;
    }
    size_t required = msg_ring_required_size(slot_size, slot_count);
    if (required == 0 || backing_len < required) {
        return NULL;
    }
    msg_ring *r = (msg_ring *)backing;
    r->slot_size = (uint32_t)slot_size;
    r->slot_count = (uint32_t)slot_count;
    r->stride = (uint32_t)stride_for(slot_size);
    atomic_init(&r->head, 0u);
    atomic_init(&r->tail, 0u);
    atomic_init(&r->dropped, 0u);
    return r;
}

int msg_ring_push(msg_ring *ring, const void *data, size_t len)
{
    if (ring == NULL || (data == NULL && len > 0)) {
        return MSG_RING_ERR_INVALID_ARG;
    }
    if (len > ring->slot_size) {
        return MSG_RING_ERR_TOO_BIG;
    }
    /* Solo el productor escribe `tail`: lectura relaxed. `head` lo escribe
     * el consumidor: acquire para ver que la ranura ya fue liberada. */
    uint32_t tail = atomic_load_explicit(&ring->tail, memory_order_relaxed);
    uint32_t head = atomic_load_explicit(&ring->head, memory_order_acquire);
    if ((uint32_t)(tail - head) >= ring->slot_count) {
        atomic_fetch_add_explicit(&ring->dropped, 1u, memory_order_relaxed);
        return MSG_RING_ERR_FULL;
    }
    uint8_t *slot = slot_ptr(ring, tail);
    uint32_t len32 = (uint32_t)len;
    memcpy(slot, &len32, sizeof len32);
    if (len > 0) {
        memcpy(slot + 4, data, len);
    }
    /* release: el contenido de la ranura es visible ANTES que el nuevo tail */
    atomic_store_explicit(&ring->tail, tail + 1u, memory_order_release);
    return MSG_RING_OK;
}

int msg_ring_pop(msg_ring *ring, void *out, size_t out_cap, size_t *out_len)
{
    if (ring == NULL || out_len == NULL || (out == NULL && out_cap > 0)) {
        return MSG_RING_ERR_INVALID_ARG;
    }
    uint32_t head = atomic_load_explicit(&ring->head, memory_order_relaxed);
    uint32_t tail = atomic_load_explicit(&ring->tail, memory_order_acquire);
    if (head == tail) {
        return MSG_RING_ERR_EMPTY;
    }
    const uint8_t *slot = slot_ptr(ring, head);
    uint32_t len32;
    memcpy(&len32, slot, sizeof len32);
    *out_len = len32;
    if (len32 > out_cap) {
        return MSG_RING_ERR_BUF_SMALL; /* no se consume */
    }
    if (len32 > 0) {
        memcpy(out, slot + 4, len32);
    }
    atomic_store_explicit(&ring->head, head + 1u, memory_order_release);
    return MSG_RING_OK;
}

size_t msg_ring_count(const msg_ring *ring)
{
    if (ring == NULL) {
        return 0;
    }
    uint32_t head = atomic_load_explicit(&((msg_ring *)ring)->head, memory_order_acquire);
    uint32_t tail = atomic_load_explicit(&((msg_ring *)ring)->tail, memory_order_acquire);
    return (uint32_t)(tail - head);
}

uint32_t msg_ring_dropped(const msg_ring *ring)
{
    if (ring == NULL) {
        return 0;
    }
    return atomic_load_explicit(&((msg_ring *)ring)->dropped, memory_order_relaxed);
}

size_t msg_ring_capacity(const msg_ring *ring)
{
    return ring == NULL ? 0 : ring->slot_count;
}

size_t msg_ring_slot_size(const msg_ring *ring)
{
    return ring == NULL ? 0 : ring->slot_size;
}
