/**
 * ui.c — Dibujado de la UI declarativa con vitaGL (ver ui.h y ADR 0007).
 *
 * Historia: el backend original era vita2d (ADR 0005). El ADR 0007 lo
 * sustituye por vitaGL porque vitaGL no puede soltar el GPU una vez
 * inicializado y el modo VIZ 3D lo necesita — un solo dueño del GPU.
 * EL CONTRATO NO CAMBIA: mismo ui.h, mismo layout.json, mismo codegen.
 *
 * Cómo dibuja (API de los samples oficiales de vitaGL, pipeline fijo):
 *  - ui_init() hace vglInit() — ÚNICO punto de init del GPU de la app —
 *    y hornea la fuente bitmap (font8x8, dominio público, vendorizada en
 *    viz/font8x8_basic.h) en una textura-atlas de 128×64 (16×8 glifos).
 *  - Cada frame 2D: proyección ortográfica 960×544 con origen arriba a
 *    la izquierda (mismas coordenadas que el layout y el editor web).
 *  - panel: GL_QUADS de color + 4 quads de 2 px si hay borde.
 *  - label/valor: un quad texturizado por carácter (monoespaciada,
 *    8 px × factor 2 = 16 px por char a escala 1). La métrica difiere
 *    de la PGF de vita2d (~20 px proporcional): la preview del editor
 *    web sigue siendo una aproximación consciente, como siempre.
 *
 * VALIDAR EN HARDWARE: aquí solo hay GL; nada de esto corre en host.
 */
#include "ui.h"

#include <psp2/kernel/threadmgr.h>
#include <vitaGL.h>

#include <stdio.h>
#include <string.h>

#include "ui_layout.h"
#include "viz/font8x8_basic.h"

#define UI_BORDE_PX 2
/* Escala base del texto: 8 px del glifo × 1.5 = 12 px por carácter a
 * escala 1. Feedback de hardware (2026-07-10): con ×2 (16 px) la fuente
 * monoespaciada desbordaba los paneles pensados para la PGF proporcional
 * y los textos se solapaban. 12 px es el apaño acordado HASTA que exista
 * el sistema de UI no fijo (layout adaptativo + tipografía mejor) — ver
 * bitácora 2026-07-10. */
#define UI_FONT_PX 8
#define UI_FONT_FACTOR 1.5f

/* Atlas de fuente: 16 columnas × 8 filas de CELDAS de 10×10 con el
 * glifo 8×8 dentro (1 px de margen alrededor): el filtrado LINEAR
 * puede muestrear fuera del glifo sin sangrar el vecino. */
#define UI_CELDA_PX 10
#define UI_ATLAS_COLS 16
#define UI_ATLAS_ROWS 8
#define UI_ATLAS_W (UI_ATLAS_COLS * UI_CELDA_PX)
#define UI_ATLAS_H (UI_ATLAS_ROWS * UI_CELDA_PX)

static GLuint g_font_tex = 0;
static bool g_listo = false;

/* Colores del layout: empaquetado RGBA8 heredado de vita2d
 * (r | g<<8 | b<<16 | a<<24; lo genera gen-ui-header.mjs). */
static void color_gl(uint32_t c)
{
    glColor4ub((GLubyte)(c & 0xff), (GLubyte)((c >> 8) & 0xff),
               (GLubyte)((c >> 16) & 0xff), (GLubyte)((c >> 24) & 0xff));
}

bool ui_init(void)
{
    /* ÚNICO init del GPU de toda la app (ADR 0007). 8 MB de pool legacy
     * como los samples de vitaGL; no hay shutdown posible. */
    vglInit(0x800000);
    vglWaitVblankStart(GL_TRUE);

    /* Hornear el atlas: bit x de font8x8_basic[c][y] = píxel (x,y),
     * centrado en su celda de 10×10 (offset +1). Blanco con alfa (el
     * color real lo pone GL_MODULATE al dibujar). */
    static uint8_t atlas[UI_ATLAS_W * UI_ATLAS_H * 4];
    memset(atlas, 0, sizeof atlas);
    for (int c = 0; c < 128; c++) {
        const int gx = (c % UI_ATLAS_COLS) * UI_CELDA_PX + 1;
        const int gy = (c / UI_ATLAS_COLS) * UI_CELDA_PX + 1;
        for (int y = 0; y < 8; y++) {
            const uint8_t fila = (uint8_t)font8x8_basic[c][y];
            for (int x = 0; x < 8; x++) {
                if (fila & (1u << x)) {
                    uint8_t *px =
                        &atlas[((gy + y) * UI_ATLAS_W + gx + x) * 4];
                    px[0] = px[1] = px[2] = px[3] = 0xff;
                }
            }
        }
    }
    glGenTextures(1, &g_font_tex);
    glBindTexture(GL_TEXTURE_2D, g_font_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, UI_ATLAS_W, UI_ATLAS_H, 0,
                 GL_RGBA, GL_UNSIGNED_BYTE, atlas);
    /* LINEAR: suaviza el look pixelart al escalar ×1.5 (feedback de
     * hardware); el margen de 1 px de las celdas evita el sangrado. */
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    g_listo = true;
    return true;
}

/* Proyección 2D del frame: píxeles de pantalla, (0,0) arriba-izquierda
 * (top=0, bottom=544 en glOrtho invierte la Y como espera el layout). */
static void modo_2d(void)
{
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0.0, (double)UI_PANTALLA_W, (double)UI_PANTALLA_H, 0.0, -1.0, 1.0);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
}

static void quad(float x, float y, float w, float h)
{
    glBegin(GL_QUADS);
    glVertex2f(x, y);
    glVertex2f(x + w, y);
    glVertex2f(x + w, y + h);
    glVertex2f(x, y + h);
    glEnd();
}

/* Resuelve el texto de un widget: fijo (label) o desde ui_state (valor).
 * `buf` respalda los bindings que formatean números. */
static const char *texto_widget(const ui_widget *w, const ui_state *st,
                                char *buf, size_t cap)
{
    switch (w->binding) {
    case UI_B_ESTADO_CONEXION:
        return st->conectado ? "CONECTADO" : "SIN CONEXION";
    case UI_B_CONTADOR_PUBLICADOS:
        snprintf(buf, cap, "%lu", (unsigned long)st->contador);
        return buf;
    case UI_B_ULTIMO_PC_HELLO:
        return st->ultimo_pc_hello[0] ? st->ultimo_pc_hello : "(nada todavia)";
    case UI_B_AGENTE:
        return st->agente;
    case UI_B_VEL_LINEAL:
        snprintf(buf, cap, "%.1f m/s", (double)st->vel_lineal);
        return buf;
    case UI_B_VEL_LATERAL:
        snprintf(buf, cap, "%.1f m/s", (double)st->vel_lateral);
        return buf;
    case UI_B_CMD_VEL:
        snprintf(buf, cap, "x%+.2f y%+.2f rz%+.2f", (double)st->lin_x,
                 (double)st->lin_y, (double)st->ang_z);
        return buf;
    case UI_B_CONTADOR_CMD:
        snprintf(buf, cap, "%lu", (unsigned long)st->contador_cmd);
        return buf;
    case UI_B_NONE:
    default:
        return w->texto;
    }
}

static void dibujar_panel(const ui_widget *w)
{
    glDisable(GL_TEXTURE_2D);
    color_gl(w->color);
    quad((float)w->x, (float)w->y, (float)w->w, (float)w->h);
    if (w->borde) {
        color_gl(w->borde);
        quad((float)w->x, (float)w->y, (float)w->w, UI_BORDE_PX);
        quad((float)w->x, (float)(w->y + w->h - UI_BORDE_PX), (float)w->w,
             UI_BORDE_PX);
        quad((float)w->x, (float)w->y, UI_BORDE_PX, (float)w->h);
        quad((float)(w->x + w->w - UI_BORDE_PX), (float)w->y, UI_BORDE_PX,
             (float)w->h);
    }
}

/* Texto monoespaciado: un quad texturizado por carácter, avanzando el
 * ancho completo del glifo. Caracteres fuera de ASCII 0-127 se saltan. */
static void dibujar_texto_xy(float x, float y, uint32_t color, float escala,
                             const char *texto)
{
    const float px = UI_FONT_PX * UI_FONT_FACTOR * escala; /* lado en pantalla */
    /* UV del glifo 8×8 DENTRO de su celda de 10×10 (margen de 1 px). */
    const float du = (float)UI_FONT_PX / UI_ATLAS_W;
    const float dv = (float)UI_FONT_PX / UI_ATLAS_H;

    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, g_font_tex);
    color_gl(color);
    glBegin(GL_QUADS);
    float cx = x;
    for (const char *p = texto; *p; p++) {
        const unsigned char c = (unsigned char)*p;
        if (c >= 128) { cx += px; continue; }
        const float u =
            (float)((c % UI_ATLAS_COLS) * UI_CELDA_PX + 1) / UI_ATLAS_W;
        const float v =
            (float)((c / UI_ATLAS_COLS) * UI_CELDA_PX + 1) / UI_ATLAS_H;
        glTexCoord2f(u, v);           glVertex2f(cx, y);
        glTexCoord2f(u + du, v);      glVertex2f(cx + px, y);
        glTexCoord2f(u + du, v + dv); glVertex2f(cx + px, y + px);
        glTexCoord2f(u, v + dv);      glVertex2f(cx, y + px);
        cx += px;
    }
    glEnd();
    glDisable(GL_TEXTURE_2D);
}

static void dibujar_texto(const ui_widget *w, const char *texto)
{
    /* (x, y) del layout es la esquina superior izquierda del texto —
     * con quads se respeta directo, sin compensar línea base. */
    dibujar_texto_xy((float)w->x, (float)w->y, w->color, w->escala, texto);
}

void ui_draw(const ui_state *st)
{
    if (!g_listo) return;
    char buf[40]; /* respaldo de los bindings que formatean (cmd_vel es el
                   * más largo: "x+0.00 y+0.00 rz+0.00" = 21 chars) */

    glClearColor((float)(UI_FONDO & 0xff) / 255.0f,
                 (float)((UI_FONDO >> 8) & 0xff) / 255.0f,
                 (float)((UI_FONDO >> 16) & 0xff) / 255.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    modo_2d();
    for (size_t i = 0; i < UI_NUM_WIDGETS; i++) {
        const ui_widget *w = &UI_WIDGETS[i];
        if (w->tipo == UI_W_PANEL) {
            dibujar_panel(w);
        } else {
            dibujar_texto(w, texto_widget(w, st, buf, sizeof buf));
        }
    }
    vglSwapBuffers(GL_FALSE);
}

void ui_draw_fatal(const char *msg, int segundos)
{
    if (!g_listo) return;
    /* Un frame estático basta: la pantalla conserva el último swap. */
    glClearColor(0.05f, 0.05f, 0.09f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    modo_2d();
    glDisable(GL_TEXTURE_2D);
    color_gl(0xff1c1c3a);
    quad(16.0f, 16.0f, (float)(UI_PANTALLA_W - 32), 96.0f);
    dibujar_texto_xy(32.0f, 32.0f, 0xff5c5cf6, 1.2f, "ERROR FATAL");
    dibujar_texto_xy(32.0f, 72.0f, 0xffe8e8e2, 1.0f, msg);
    vglSwapBuffers(GL_FALSE);
    sceKernelDelayThread((SceUInt)segundos * 1000 * 1000);
}

void ui_shutdown(void)
{
    /* vitaGL no tiene cierre (ADR 0007): solo se liberan los recursos
     * propios; el GPU muere con el proceso. */
    if (g_font_tex) {
        glDeleteTextures(1, &g_font_tex);
        g_font_tex = 0;
    }
    g_listo = false;
}
