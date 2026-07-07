/**
 * teleop.c — implementación del mapeo mandos -> Twist (ver teleop.h y
 * docs/09-objetivo2-control-robot.md). Pura: sin sceCtrl, sin red, sin
 * estado global — todo entra y sale por parámetros, testeable en host.
 *
 * Convención cruda de sceCtrl para los sticks: 0..255 por eje, centro
 * ~128; en X, 0 = izquierda; en Y, 0 = ARRIBA (como en la PSP). REP 103
 * pide x adelante, y izquierda, angular.z positivo = giro antihorario
 * (izquierda) — de ahí los signos negativos al convertir.
 */
#include "teleop.h"

void teleop_init(teleop_estado *st)
{
    st->vel_lineal = TELEOP_VEL_INICIAL;
    st->vel_lateral = TELEOP_LATERAL_INICIAL;
    st->prev_cruz = false;
    st->prev_triangulo = false;
}

double teleop_normalizar_eje(uint8_t crudo)
{
    /* Desplazamiento respecto al centro, en [-128, +127]. */
    int d = (int)crudo - TELEOP_STICK_CENTRO;
    if (d > -TELEOP_STICK_MUERTA && d < TELEOP_STICK_MUERTA) {
        return 0.0;
    }
    /* Reescalar para que el borde de la zona muerta sea 0 y el extremo
     * del recorrido sea exactamente +-1 (sin salto al salir de la zona). */
    if (d >= 0) {
        return (double)(d - (TELEOP_STICK_MUERTA - 1)) /
               (double)(127 - (TELEOP_STICK_MUERTA - 1));
    }
    return (double)(d + (TELEOP_STICK_MUERTA - 1)) /
           (double)(128 - (TELEOP_STICK_MUERTA - 1));
}

static double clamp(double v, double lo, double hi)
{
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

void teleop_update(teleop_estado *st, const teleop_entrada *in, double dt_s,
                   teleop_twist *out)
{
    /* --- Flancos de subida: triangulo sube la escala, cruz la baja.
     * El suelo 0.0 es el stop pedido: con la escala a 0, ni el stick
     * izquierdo ni la cruceta producen movimiento. --- */
    if (in->triangulo && !st->prev_triangulo) {
        st->vel_lineal = clamp(st->vel_lineal + TELEOP_VEL_PASO, 0.0,
                               TELEOP_VEL_MAX);
    }
    if (in->cruz && !st->prev_cruz) {
        st->vel_lineal = clamp(st->vel_lineal - TELEOP_VEL_PASO, 0.0,
                               TELEOP_VEL_MAX);
    }
    st->prev_triangulo = in->triangulo;
    st->prev_cruz = in->cruz;

    /* --- Stick derecho vertical: rampa continua de vel_lateral
     * (arriba aumenta; a deflexión máxima cambia RAMPA por segundo). --- */
    double ry = teleop_normalizar_eje(in->ry); /* +1 = abajo del todo */
    st->vel_lateral = clamp(st->vel_lateral - ry * TELEOP_LATERAL_RAMPA * dt_s,
                            0.0, TELEOP_VEL_MAX);

    /* --- Twist. Digital manda sobre analógico, eje a eje (docs/09). --- */
    out->lin_x = out->lin_y = out->lin_z = 0.0;
    out->ang_x = out->ang_y = out->ang_z = 0.0;

    /* linear.x: cruceta arriba/abajo, si no el stick izquierdo vertical. */
    if (in->arriba || in->abajo) {
        if (in->arriba && !in->abajo) out->lin_x = st->vel_lineal;
        if (in->abajo && !in->arriba) out->lin_x = -st->vel_lineal;
    } else {
        out->lin_x = -teleop_normalizar_eje(in->ly) * st->vel_lineal;
    }

    /* linear.y: cruceta izq/der (escala lineal), si no el stick derecho
     * horizontal (escala lateral). Izquierda = y positivo (REP 103). */
    if (in->izquierda || in->derecha) {
        if (in->izquierda && !in->derecha) out->lin_y = st->vel_lineal;
        if (in->derecha && !in->izquierda) out->lin_y = -st->vel_lineal;
    } else {
        out->lin_y = -teleop_normalizar_eje(in->rx) * st->vel_lateral;
    }

    /* angular.z: L/R fijos a +-TELEOP_GIRO_LR (los dos a la vez se anulan),
     * si no el stick izquierdo horizontal proporcional a vel_lineal. */
    if (in->l || in->r) {
        if (in->l && !in->r) out->ang_z = TELEOP_GIRO_LR;
        if (in->r && !in->l) out->ang_z = -TELEOP_GIRO_LR;
    } else {
        out->ang_z = -teleop_normalizar_eje(in->lx) * st->vel_lineal;
    }
}
