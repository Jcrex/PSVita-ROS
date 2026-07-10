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

    printf("%d/%d checks de camara OK\n", g_checks - g_fallos, g_checks);
    return g_fallos ? EXIT_FAILURE : EXIT_SUCCESS;
}
