/**
 * viz.c — Escena 3D mínima del mini-rviz con vitaGL (contrato en viz.h).
 *
 * SOLO VITA — VALIDAR EN HARDWARE. API copiada de los samples oficiales
 * de vitaGL (auditoria/vitaGL/samples/rotating_cube), no inventada:
 * pipeline fijo GL 1.x (glMatrixMode/gluPerspective/gluLookAt +
 * glBegin/glEnd) que vitaGL implementa sobre SceGxm.
 *
 * Convención de ejes REP 103 (como rviz): Z arriba. Grid en el plano
 * XY (Z=0), ejes X rojo / Y verde / Z azul, cubo de referencia de
 * 0.5 m apoyado en el origen.
 */
#include "viz.h"

#include <vitaGL.h>

#define VIZ_GRID_MITAD 5    /* grid de 10×10 m con paso de 1 m */
#define VIZ_CUBO_LADO 0.5f

bool viz_init(void)
{
    /* El GPU ya es de ui_init() (ADR 0007). Nada que preparar en la
     * escena mínima; el hueco existe para cargar el VBM en E2. */
    return true;
}

static void dibujar_grid(void)
{
    glLineWidth(1.0f);
    glColor4ub(70, 70, 90, 255);
    glBegin(GL_LINES);
    for (int i = -VIZ_GRID_MITAD; i <= VIZ_GRID_MITAD; i++) {
        /* Líneas paralelas al eje Y y al eje X, en Z=0. */
        glVertex3f((float)i, (float)-VIZ_GRID_MITAD, 0.0f);
        glVertex3f((float)i, (float)VIZ_GRID_MITAD, 0.0f);
        glVertex3f((float)-VIZ_GRID_MITAD, (float)i, 0.0f);
        glVertex3f((float)VIZ_GRID_MITAD, (float)i, 0.0f);
    }
    glEnd();
}

static void dibujar_ejes(void)
{
    glLineWidth(3.0f);
    glBegin(GL_LINES);
    glColor4ub(230, 60, 60, 255); /* X rojo */
    glVertex3f(0.0f, 0.0f, 0.0f);
    glVertex3f(1.0f, 0.0f, 0.0f);
    glColor4ub(60, 200, 60, 255); /* Y verde */
    glVertex3f(0.0f, 0.0f, 0.0f);
    glVertex3f(0.0f, 1.0f, 0.0f);
    glColor4ub(70, 110, 240, 255); /* Z azul */
    glVertex3f(0.0f, 0.0f, 0.0f);
    glVertex3f(0.0f, 0.0f, 1.0f);
    glEnd();
}

/* Cubo por caras con GL_QUADS (mismo estilo que el sample de vitaGL,
 * que usa client arrays; aquí immediate mode: 6 caras × 4 vértices). */
static void dibujar_cubo(void)
{
    const float h = VIZ_CUBO_LADO * 0.5f; /* medio lado */
    const float z0 = 0.0f, z1 = VIZ_CUBO_LADO; /* apoyado en Z=0 */

    glBegin(GL_QUADS);
    glColor4ub(240, 170, 60, 255);
    /* Tapa (Z=z1) y base (Z=z0) */
    glVertex3f(-h, -h, z1); glVertex3f(h, -h, z1);
    glVertex3f(h, h, z1);   glVertex3f(-h, h, z1);
    glColor4ub(180, 120, 40, 255);
    glVertex3f(-h, -h, z0); glVertex3f(h, -h, z0);
    glVertex3f(h, h, z0);   glVertex3f(-h, h, z0);
    /* Cuatro laterales */
    glColor4ub(210, 145, 50, 255);
    glVertex3f(-h, -h, z0); glVertex3f(h, -h, z0);
    glVertex3f(h, -h, z1);  glVertex3f(-h, -h, z1);
    glVertex3f(-h, h, z0);  glVertex3f(h, h, z0);
    glVertex3f(h, h, z1);   glVertex3f(-h, h, z1);
    glColor4ub(200, 135, 45, 255);
    glVertex3f(-h, -h, z0); glVertex3f(-h, h, z0);
    glVertex3f(-h, h, z1);  glVertex3f(-h, -h, z1);
    glVertex3f(h, -h, z0);  glVertex3f(h, h, z0);
    glVertex3f(h, h, z1);   glVertex3f(h, -h, z1);
    glEnd();
}

void viz_draw(const viz_camera *cam)
{
    glClearColor(0.06f, 0.06f, 0.10f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);
    glDisable(GL_TEXTURE_2D);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(45.0f, 960.0f / 544.0f, 0.1f, 100.0f);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    float eye[3];
    viz_camera_eye(cam, eye);
    /* up = +Z (REP 103); pitch clampeado en camera.c lejos del polo. */
    gluLookAt(eye[0], eye[1], eye[2],
              cam->target[0], cam->target[1], cam->target[2],
              0.0f, 0.0f, 1.0f);

    dibujar_grid();
    dibujar_ejes();
    dibujar_cubo();

    vglSwapBuffers(GL_FALSE);
}

void viz_shutdown(void)
{
    /* Nada: el GPU no se puede cerrar (ADR 0007) y la escena mínima no
     * reserva recursos. E2 liberará aquí el modelo VBM. */
}
