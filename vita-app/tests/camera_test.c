/**
 * camera_test.c — Batería HOST de la cámara orbital del mini-rviz
 * (src/viz/camera.c, lógica pura). La corre scripts/check-viz-host.sh
 * con el gcc del host: lo que pasa aquí es exactamente lo que corre en
 * la consola; viz.c solo convierte eye/target en gluLookAt.
 *
 * Valores esperados calculados a mano con la fórmula del header:
 *   eye = target + dist·(cos(pitch)cos(yaw), cos(pitch)sin(yaw), sin(pitch))
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "viz/camera.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static int g_checks = 0;
static int g_fallos = 0;

#define TOL 1e-5f

static void check_f(const char *que, float got, float want)
{
    g_checks++;
    if (fabsf(got - want) > TOL) {
        g_fallos++;
        printf("FALLO %s: got=%f want=%f\n", que, (double)got, (double)want);
    }
}

static void check(const char *que, int cond)
{
    g_checks++;
    if (!cond) {
        g_fallos++;
        printf("FALLO %s\n", que);
    }
}

int main(void)
{
    viz_camera c;

    /* init: pose isométrica documentada y target en el origen */
    viz_camera_init(&c);
    check("init: dist 6", c.dist == 6.0f);
    check("init: target origen",
          c.target[0] == 0.0f && c.target[1] == 0.0f && c.target[2] == 0.0f);

    /* eye con ángulos triviales: yaw=0, pitch=0, dist=5 => (5,0,0) */
    c.yaw = 0.0f; c.pitch = 0.0f; c.dist = 5.0f;
    float eye[3];
    viz_camera_eye(&c, eye);
    check_f("eye(yaw0,pitch0).x", eye[0], 5.0f);
    check_f("eye(yaw0,pitch0).y", eye[1], 0.0f);
    check_f("eye(yaw0,pitch0).z", eye[2], 0.0f);

    /* yaw=90 grados => (0,5,0) (Z-up, giro antihorario visto desde +Z) */
    c.yaw = (float)M_PI / 2.0f;
    viz_camera_eye(&c, eye);
    check_f("eye(yaw90).x", eye[0], 0.0f);
    check_f("eye(yaw90).y", eye[1], 5.0f);
    check_f("eye(yaw90).z", eye[2], 0.0f);

    /* pitch clampeado: subir 10 rad no pasa del tope (nunca en el polo) */
    viz_camera_orbit(&c, 0.0f, 10.0f);
    check_f("orbit: pitch clamp alto", c.pitch, VIZ_CAM_PITCH_MAX);
    viz_camera_orbit(&c, 0.0f, -20.0f);
    check_f("orbit: pitch clamp bajo", c.pitch, -VIZ_CAM_PITCH_MAX);

    /* el target se respeta como offset */
    c.yaw = 0.0f; c.pitch = 0.0f; c.dist = 2.0f;
    c.target[0] = 1.0f; c.target[1] = -2.0f; c.target[2] = 0.5f;
    viz_camera_eye(&c, eye);
    check_f("eye(target).x", eye[0], 3.0f);
    check_f("eye(target).y", eye[1], -2.0f);
    check_f("eye(target).z", eye[2], 0.5f);

    /* zoom con clamps por los dos extremos */
    c.dist = 1.0f;
    viz_camera_zoom(&c, 0.1f);
    check_f("zoom: clamp min", c.dist, VIZ_CAM_DIST_MIN);
    viz_camera_zoom(&c, 1000.0f);
    check_f("zoom: clamp max", c.dist, VIZ_CAM_DIST_MAX);

    /* yaw envuelve sin clamp (dar 3 vueltas no explota) */
    c.yaw = 0.0f;
    for (int i = 0; i < 100; i++) viz_camera_orbit(&c, 0.2f, 0.0f);
    check("orbit: yaw acotado tras 100 pasos",
          c.yaw <= (float)M_PI * 2.0f && c.yaw >= -(float)M_PI * 2.0f);

    /* --- viz_camera_view_matrix --- */

    /* Caso trivial: ojo en (5,0,0) mirando al origen => el origen del
     * mundo queda 5 unidades DELANTE de la cámara: (0,0,-5) en vista. */
    c.yaw = 0.0f; c.pitch = 0.0f; c.dist = 5.0f;
    c.target[0] = c.target[1] = c.target[2] = 0.0f;
    float m[16];
    viz_camera_view_matrix(&c, m);
    /* transformar el origen = columna de traslación */
    check_f("vista: origen.x", m[12], 0.0f);
    check_f("vista: origen.y", m[13], 0.0f);
    check_f("vista: origen.z", m[14], -5.0f);

    /* REGRESIÓN del bug de gluLookAt de vitaGL (distorsión mirando
     * arriba, visto en hardware 2026-07-10): con pitch extremo la base
     * de rotación DEBE seguir siendo ortonormal (filas unitarias y
     * perpendiculares). vitaGL metía s=f×up sin normalizar y aquí
     * |s| caía a ~0.04 => imagen aplastada. */
    c.pitch = VIZ_CAM_PITCH_MAX;
    viz_camera_view_matrix(&c, m);
    const float *fx = &m[0]; /* filas en column-major: (m[0],m[4],m[8]) */
    float fila_s[3] = {m[0], m[4], m[8]};
    float fila_u[3] = {m[1], m[5], m[9]};
    float fila_f[3] = {m[2], m[6], m[10]};
    (void)fx;
    check_f("vista pitch max: |s|",
            sqrtf(fila_s[0] * fila_s[0] + fila_s[1] * fila_s[1] +
                  fila_s[2] * fila_s[2]), 1.0f);
    check_f("vista pitch max: |u|",
            sqrtf(fila_u[0] * fila_u[0] + fila_u[1] * fila_u[1] +
                  fila_u[2] * fila_u[2]), 1.0f);
    check_f("vista pitch max: |f|",
            sqrtf(fila_f[0] * fila_f[0] + fila_f[1] * fila_f[1] +
                  fila_f[2] * fila_f[2]), 1.0f);
    check_f("vista pitch max: s.u",
            fila_s[0] * fila_u[0] + fila_s[1] * fila_u[1] +
            fila_s[2] * fila_u[2], 0.0f);
    check_f("vista pitch max: s.f",
            fila_s[0] * fila_f[0] + fila_s[1] * fila_f[1] +
            fila_s[2] * fila_f[2], 0.0f);
    check_f("vista pitch max: u.f",
            fila_u[0] * fila_f[0] + fila_u[1] * fila_f[1] +
            fila_u[2] * fila_f[2], 0.0f);

    /* La distancia al target se conserva con cualquier pitch: el target
     * transformado debe quedar en (0,0,-dist). */
    check_f("vista pitch max: target delante",
            m[2] * c.target[0] + m[6] * c.target[1] + m[10] * c.target[2] +
                m[14], -c.dist);

    printf("%d/%d checks de camara OK\n", g_checks - g_fallos, g_checks);
    return g_fallos ? EXIT_FAILURE : EXIT_SUCCESS;
}
