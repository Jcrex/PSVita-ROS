/**
 * tf_tree.h — Contrato C-ABI del módulo dual `tf-tree`.
 *
 * ESTE HEADER ES LA VERDAD DEL MÓDULO (docs/03-estrategia-dual-rust-cpp.md).
 *
 * Qué es: el árbol de transformadas (TF) que necesita el mini-rviz: guarda
 * el ÚLTIMO valor recibido de cada frame y resuelve cadenas padre→hijo.
 *
 * Simplificaciones respecto a tf2 real (documentadas a propósito):
 *  - SIN historial temporal: solo el último valor por frame; no interpola
 *    ni extrapola y no mira timestamps. `lookup` devuelve "ahora".
 *  - Hasta TF_TREE_MAX_FRAMES (32) frames, tabla estática, sin malloc.
 *  - /tf y /tf_static se tratan igual (ambos llaman a update).
 *  - Un nombre de frame admite una barra inicial ("/odom" == "odom"),
 *    como tf2. Longitud 1..63 caracteres.
 *
 * Convención: update(parent, child, t, q) guarda la pose del hijo EN el
 * padre, o sea la transformación que lleva coordenadas del hijo a las del
 * padre (p_padre = R·p_hijo + t), igual que geometry_msgs/TransformStamped.
 * lookup(target, source) devuelve M tal que  p_target = M · p_source
 * (igual que tf2 lookupTransform(target, source)). M es mat4 column-major
 * de viz-math.
 *
 * Dependencias: viz-math (matemática) y msg-cdr (solo los tipos de entrada).
 */
#ifndef VITA_TF_TREE_H
#define VITA_TF_TREE_H

#include <stddef.h>
#include <stdint.h>

#include "msg_cdr.h"
#include "viz_math.h"

#ifdef __cplusplus
extern "C" {
#endif

#define TF_TREE_MAX_FRAMES 32
#define TF_TREE_NAME_MAX   64 /* incluye el NUL */

typedef enum {
    TF_TREE_OK               =  0,
    TF_TREE_ERR_INVALID_ARG  = -1, /* puntero nulo, nombre vacío o demasiado largo */
    TF_TREE_ERR_FULL         = -2, /* ya hay 32 frames y haría falta uno nuevo     */
    TF_TREE_ERR_CYCLE        = -3, /* el padre sería descendiente del hijo         */
    TF_TREE_ERR_UNKNOWN_FRAME = -4,/* lookup: frame inexistente                     */
    TF_TREE_ERR_NO_PATH      = -5, /* lookup: frames en árboles distintos           */
} tf_tree_status;

typedef struct tf_tree tf_tree; /* handle opaco */

/** Bytes de respaldo necesarios (constante). */
size_t tf_tree_required_size(void);

/** Inicializa en `backing` (alineado a 8). NULL si backing es NULL, está mal
 *  alineado o `backing_len` es insuficiente. Árbol vacío. */
tf_tree *tf_tree_create(void *backing, size_t backing_len);

/** Vacía el árbol (frames y contador de rechazos). */
void tf_tree_clear(tf_tree *tree);

/** Inserta/actualiza `child` con padre `parent` y la pose (t, q). `q` se
 *  normaliza al guardar (norma ~0 → identidad). Puede cambiar el padre de un
 *  hijo existente. Errores: INVALID_ARG, FULL (no se modifica nada), CYCLE
 *  (incluye parent == child; no se modifica nada). */
int tf_tree_update(tf_tree *tree, const char *parent, const char *child,
                   const vizm_vec3 *t, const vizm_quat *q);

/** Aplica todos los transforms de un TFMessage ya decodificado. Devuelve cuántos
 *  se aplicaron (>= 0); los rechazados (FULL/CYCLE/nombre inválido) suman al
 *  contador de tf_tree_rejected(). Argumentos nulos → TF_TREE_ERR_INVALID_ARG. */
int tf_tree_apply_message(tf_tree *tree, const msg_cdr_tf_message *msg);

/** M tal que p_target = M · p_source. Mismo frame → identidad. */
int tf_tree_lookup(const tf_tree *tree, const char *target, const char *source,
                   vizm_mat4 *out);

size_t   tf_tree_frame_count(const tf_tree *tree);
uint32_t tf_tree_rejected(const tf_tree *tree);

#ifdef __cplusplus
}
#endif

#endif /* VITA_TF_TREE_H */
