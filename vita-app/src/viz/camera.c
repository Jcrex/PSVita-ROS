/**
 * camera.c — Cámara orbital del mini-rviz (contrato en camera.h).
 *
 * Sin headers de la Vita: solo math.h. Batería host en
 * vita-app/tests/camera_test.c (scripts/check-viz-host.sh).
 * Cuando exista modules/viz-math (Etapa D1) estas cuentas migran allí.
 */
#include "camera.h"

#include <math.h>

/* M_PI no es C99 estándar (es extensión POSIX): fallback portable. */
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

void viz_camera_init(viz_camera *c)
{
    c->yaw = 0.8f;    /* ~45°: se ven los tres ejes a la vez */
    c->pitch = 0.5f;  /* ~30° de elevación                   */
    c->dist = 6.0f;
    c->target[0] = 0.0f;
    c->target[1] = 0.0f;
    c->target[2] = 0.0f;
}

void viz_camera_orbit(viz_camera *c, float dyaw, float dpitch)
{
    c->yaw += dyaw;
    /* Mantener yaw acotado evita perder precisión float en sesiones
     * largas; la dirección no cambia (periodo 2π). */
    if (c->yaw > (float)M_PI * 2.0f) c->yaw -= (float)M_PI * 2.0f;
    if (c->yaw < -(float)M_PI * 2.0f) c->yaw += (float)M_PI * 2.0f;

    c->pitch += dpitch;
    if (c->pitch > VIZ_CAM_PITCH_MAX) c->pitch = VIZ_CAM_PITCH_MAX;
    if (c->pitch < -VIZ_CAM_PITCH_MAX) c->pitch = -VIZ_CAM_PITCH_MAX;
}

void viz_camera_zoom(viz_camera *c, float factor)
{
    c->dist *= factor;
    if (c->dist < VIZ_CAM_DIST_MIN) c->dist = VIZ_CAM_DIST_MIN;
    if (c->dist > VIZ_CAM_DIST_MAX) c->dist = VIZ_CAM_DIST_MAX;
}

void viz_camera_eye(const viz_camera *c, float eye[3])
{
    const float cp = cosf(c->pitch);
    eye[0] = c->target[0] + c->dist * cp * cosf(c->yaw);
    eye[1] = c->target[1] + c->dist * cp * sinf(c->yaw);
    eye[2] = c->target[2] + c->dist * sinf(c->pitch);
}
