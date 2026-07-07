/**
 * teleop.h — Objetivo 2: mapeo mandos de la Vita -> geometry_msgs/Twist.
 *
 * LÓGICA PURA, SIN HEADERS DE LA VITA: compila en host y se testea con
 * scripts/check-teleop.sh (misma filosofía que los módulos duales: lo que
 * se puede verificar en la laptop, se verifica). main.c solo traduce
 * SceCtrlData -> teleop_entrada y llama a teleop_update() cada vuelta.
 *
 * Mapeo completo y convención de ejes (REP 103): ver
 * docs/09-objetivo2-control-robot.md. Resumen:
 *   stick izq  = linear.x (adelante/atras) + angular.z (giro proporcional)
 *   stick der  = linear.y (lateral); su eje vertical AJUSTA vel_lateral
 *   cruceta    = linear.x / linear.y digitales (prioridad sobre sticks)
 *   L / R      = angular.z fijo +-0.5 (prioridad sobre el stick)
 *   triangulo  = vel_lineal += 0.5 (flanco)   cruz = vel_lineal -= 0.5
 *                (suelo 0.0 = stop total de sticks izq + cruceta)
 */
#ifndef VITA_TELEOP_H
#define VITA_TELEOP_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Parámetros del mapeo (docs/09, tabla "Mapeo de mandos"). */
#define TELEOP_VEL_INICIAL 0.5   /* escala inicial de linear.x / cruceta   */
#define TELEOP_VEL_PASO 0.5      /* paso de triangulo/cruz                 */
#define TELEOP_VEL_MAX 2.0       /* tope de vel_lineal y vel_lateral       */
#define TELEOP_GIRO_LR 0.5       /* angular.z fijo de L/R (rad/s)          */
#define TELEOP_LATERAL_INICIAL 0.5
#define TELEOP_LATERAL_RAMPA 0.5 /* delta de vel_lateral por segundo a tope */
#define TELEOP_STICK_CENTRO 128  /* sceCtrl: sticks 0..255                 */
#define TELEOP_STICK_MUERTA 30   /* zona muerta cruda alrededor del centro */

/* Foto de los mandos en un instante (main.c la rellena desde SceCtrlData). */
typedef struct {
    uint8_t lx, ly;   /* stick izquierdo crudo (0..255, centro ~128)  */
    uint8_t rx, ry;   /* stick derecho crudo                          */
    bool arriba, abajo, izquierda, derecha; /* cruceta                */
    bool l, r;        /* gatillos L / R                               */
    bool cruz;        /* boton X (flanco lo detecta teleop_update)    */
    bool triangulo;   /* boton triangulo (flanco idem)                */
} teleop_entrada;

/* geometry_msgs/Twist: 6 doubles (el orden de serialización CDR es
 * linear.x,y,z y luego angular.x,y,z — exactamente este struct). */
typedef struct {
    double lin_x, lin_y, lin_z;
    double ang_x, ang_y, ang_z;
} teleop_twist;

/* Estado persistente entre vueltas del bucle (escalas + flancos). */
typedef struct {
    double vel_lineal;  /* escala de stick izq + cruceta [0, VEL_MAX]   */
    double vel_lateral; /* escala del stick derecho      [0, VEL_MAX]   */
    bool prev_cruz, prev_triangulo; /* para detectar flancos de subida  */
} teleop_estado;

/** Deja las escalas en sus valores iniciales y limpia los flancos. */
void teleop_init(teleop_estado *st);

/**
 * Una vuelta del teleop: aplica flancos de cruz/triangulo, la rampa del
 * stick derecho vertical (dt_s en segundos) y calcula el Twist según la
 * tabla de docs/09. `out` sale siempre completo (ejes no usados a 0).
 */
void teleop_update(teleop_estado *st, const teleop_entrada *in, double dt_s,
                   teleop_twist *out);

/**
 * Normaliza un eje crudo de stick (0..255) a [-1, +1] con zona muerta
 * TELEOP_STICK_MUERTA reescalada (0 en el borde de la zona, ±1 en el
 * extremo, sin salto). Expuesta para poder testearla directamente.
 */
double teleop_normalizar_eje(uint8_t crudo);

#ifdef __cplusplus
}
#endif

#endif /* VITA_TELEOP_H */
