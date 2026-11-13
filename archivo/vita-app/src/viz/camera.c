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

/* Auxiliares locales (migran a modules/viz-math en la Etapa D1). */
static void v3_normalize(float v[3])
{
    const float n = sqrtf(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (n > 0.0f) {
        v[0] /= n;
        v[1] /= n;
        v[2] /= n;
    }
}

static void v3_cross(float out[3], const float a[3], const float b[3])
{
    out[0] = a[1] * b[2] - a[2] * b[1];
    out[1] = a[2] * b[0] - a[0] * b[2];
    out[2] = a[0] * b[1] - a[1] * b[0];
}

static float v3_dot(const float a[3], const float b[3])
{
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

void viz_camera_view_matrix(const viz_camera *c, float m[16])
{
    float eye[3];
    viz_camera_eye(c, eye);

    /* f = dirección de vista; s = lateral; u = up de cámara. TODOS
     * normalizados antes de tocar la matriz (el bug de vitaGL era
     * exactamente no hacer esto con s — ver camera.h). El pitch
     * clampeado lejos del polo garantiza |f×up| > 0. */
    float f[3] = {c->target[0] - eye[0], c->target[1] - eye[1],
                  c->target[2] - eye[2]};
    v3_normalize(f);
    const float up[3] = {0.0f, 0.0f, 1.0f};
    float s[3];
    v3_cross(s, f, up);
    v3_normalize(s);
    float u[3];
    v3_cross(u, s, f); /* s y f unitarios y perpendiculares => u unitario */

    /* Column-major (OpenGL): fila X=s, fila Y=u, fila Z=-f, y la
     * traslación lleva el ojo al origen. */
    m[0] = s[0]; m[4] = s[1]; m[8] = s[2];  m[12] = -v3_dot(s, eye);
    m[1] = u[0]; m[5] = u[1]; m[9] = u[2];  m[13] = -v3_dot(u, eye);
    m[2] = -f[0]; m[6] = -f[1]; m[10] = -f[2]; m[14] = v3_dot(f, eye);
    m[3] = 0.0f; m[7] = 0.0f; m[11] = 0.0f; m[15] = 1.0f;
}
