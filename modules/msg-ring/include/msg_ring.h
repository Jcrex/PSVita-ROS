/**
 * msg_ring.h — Contrato C-ABI del módulo dual `msg-ring`.
 *
 * ESTE HEADER ES LA VERDAD DEL MÓDULO (docs/03-estrategia-dual-rust-cpp.md).
 *
 * Qué es: una cola circular SPSC (un productor, un consumidor) SIN BLOQUEOS
 * de mensajes de tamaño variable acotado. Pensada para pasar mensajes ROS2
 * del hilo de red (el que ejecuta `uxr_run_session_*`) al hilo de dibujo /
 * al hilo principal de Godot, sin mutex y sin malloc (ADR 0008, docs/13 §4).
 *
 * Diseño:
 *  - El llamador aporta el buffer de respaldo (como mem-pool): sin malloc.
 *  - `slot_count` debe ser potencia de 2 (índice = contador & máscara).
 *  - Cada ranura guarda 4 bytes de longitud + hasta `slot_size` bytes útiles,
 *    redondeada a 8 bytes. Un mensaje = una ranura (sin fragmentar).
 *  - Los contadores `head` (consumidor) y `tail` (productor) son u32 que
 *    crecen sin parar y dan la vuelta solos; ocupación = tail - head.
 *  - Orden de memoria: el productor publica con `release` y el consumidor
 *    lee con `acquire` (necesario en la ARM Cortex-A9 de la Vita, que
 *    reordena escrituras; en x86 no se notaría).
 *  - Si la cola está llena, el mensaje NUEVO se descarta (se cuenta en
 *    `dropped`): en visualización es mejor perder uno viejo-nuevo que
 *    bloquear la red. Política documentada, no accidental.
 *
 * Contrato de hilos: UN solo hilo llama a push y UN solo hilo llama a pop.
 * `count` y `dropped` pueden leerse desde cualquiera (valor aproximado).
 */
#ifndef VITA_MSG_RING_H
#define VITA_MSG_RING_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MSG_RING_OK              =  0,
    MSG_RING_ERR_INVALID_ARG = -1, /* puntero nulo o parámetro fuera de rango */
    MSG_RING_ERR_FULL        = -2, /* cola llena: mensaje descartado (dropped++) */
    MSG_RING_ERR_EMPTY       = -3, /* nada que leer */
    MSG_RING_ERR_TOO_BIG     = -4, /* push: len > slot_size */
    MSG_RING_ERR_BUF_SMALL   = -5, /* pop: out_cap < tamaño del mensaje (NO se consume) */
} msg_ring_status;

typedef struct msg_ring msg_ring; /* handle opaco */

/**
 * Bytes de respaldo para `slot_count` ranuras de `slot_size` bytes útiles.
 * = 64 (cabecera) + slot_count * redondeo8(4 + slot_size).
 * Devuelve 0 si slot_size == 0, slot_count == 0, slot_count no es potencia
 * de 2, slot_count > 2^30, o el cálculo desborda size_t.
 */
size_t msg_ring_required_size(size_t slot_size, size_t slot_count);

/**
 * Inicializa una cola dentro de `backing`. NULL si: backing NULL,
 * backing sin alinear a 8, parámetros inválidos (ver required_size) o
 * backing_len insuficiente.
 */
msg_ring *msg_ring_create(void *backing, size_t backing_len,
                          size_t slot_size, size_t slot_count);

/** Productor: copia `len` bytes. OK, ERR_FULL, ERR_TOO_BIG o ERR_INVALID_ARG
 *  (ring NULL, o data NULL con len > 0). len == 0 es válido (mensaje vacío). */
int msg_ring_push(msg_ring *ring, const void *data, size_t len);

/** Consumidor: copia el mensaje más antiguo a `out` y escribe su longitud
 *  en `*out_len`. OK, ERR_EMPTY, ERR_BUF_SMALL (el mensaje sigue en la cola
 *  y `*out_len` recibe el tamaño necesario) o ERR_INVALID_ARG. */
int msg_ring_pop(msg_ring *ring, void *out, size_t out_cap, size_t *out_len);

/** Mensajes en cola ahora mismo (aproximado si hay otro hilo activo). */
size_t msg_ring_count(const msg_ring *ring);

/** Mensajes descartados por cola llena desde la creación (sin reset). */
uint32_t msg_ring_dropped(const msg_ring *ring);

/** Capacidad en ranuras y tamaño útil por ranura (0 si ring NULL). */
size_t msg_ring_capacity(const msg_ring *ring);
size_t msg_ring_slot_size(const msg_ring *ring);

#ifdef __cplusplus
}
#endif

#endif /* VITA_MSG_RING_H */
