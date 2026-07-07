/**
 * ui.c — Dibujado de la UI declarativa con vita2d (ver ui.h y ADR 0005).
 *
 * Recorre UI_WIDGETS (generado en ui_layout.h) cada frame:
 *  - panel: rectángulo relleno + borde opcional (4 rects de 2 px: vita2d
 *    no tiene rectángulo "solo contorno").
 *  - label/valor: texto PGF. (x, y) del layout es la esquina superior
 *    izquierda: vita2d_pgf_draw_text espera la línea base, así que se
 *    compensa con vita2d_pgf_text_height. Es la misma aproximación que
 *    hace la preview del editor web — coherentes entre sí, no exactas.
 *
 * VALIDAR EN EL PC: requiere libvita2d del VitaSDK (vdpm vita2d si falta).
 */
#include "ui.h"

#include <psp2/kernel/threadmgr.h>
#include <vita2d.h>

#include <stdio.h>

#include "ui_layout.h"

#define UI_BORDE_PX 2

static vita2d_pgf *g_font = NULL;

bool ui_init(void)
{
    vita2d_init();
    vita2d_set_clear_color(UI_FONDO);
    g_font = vita2d_load_default_pgf();
    return g_font != NULL;
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
    case UI_B_NONE:
    default:
        return w->texto;
    }
}

static void dibujar_panel(const ui_widget *w)
{
    vita2d_draw_rectangle(w->x, w->y, w->w, w->h, w->color);
    if (w->borde) {
        vita2d_draw_rectangle(w->x, w->y, w->w, UI_BORDE_PX, w->borde);
        vita2d_draw_rectangle(w->x, w->y + w->h - UI_BORDE_PX, w->w, UI_BORDE_PX, w->borde);
        vita2d_draw_rectangle(w->x, w->y, UI_BORDE_PX, w->h, w->borde);
        vita2d_draw_rectangle(w->x + w->w - UI_BORDE_PX, w->y, UI_BORDE_PX, w->h, w->borde);
    }
}

static void dibujar_texto(const ui_widget *w, const char *texto)
{
    int alto = vita2d_pgf_text_height(g_font, w->escala, texto);
    vita2d_pgf_draw_text(g_font, w->x, w->y + alto, w->color, w->escala, texto);
}

void ui_draw(const ui_state *st)
{
    if (!g_font) return;
    char buf[16];

    vita2d_start_drawing();
    vita2d_clear_screen();
    for (size_t i = 0; i < UI_NUM_WIDGETS; i++) {
        const ui_widget *w = &UI_WIDGETS[i];
        if (w->tipo == UI_W_PANEL) {
            dibujar_panel(w);
        } else {
            dibujar_texto(w, texto_widget(w, st, buf, sizeof buf));
        }
    }
    vita2d_end_drawing();
    vita2d_swap_buffers();
}

void ui_draw_fatal(const char *msg, int segundos)
{
    if (!g_font) return;
    /* Un frame estático basta: la pantalla conserva el último swap. */
    vita2d_start_drawing();
    vita2d_clear_screen();
    vita2d_draw_rectangle(16, 16, UI_PANTALLA_W - 32, 96, 0xff1c1c3a);
    vita2d_pgf_draw_text(g_font, 32, 56, 0xff5c5cf6, 1.2f, "ERROR FATAL");
    vita2d_pgf_draw_text(g_font, 32, 92, 0xffe8e8e2, 1.0f, msg);
    vita2d_end_drawing();
    vita2d_swap_buffers();
    sceKernelDelayThread((SceUInt)segundos * 1000 * 1000);
}

void ui_shutdown(void)
{
    /* Mismo orden que los samples de vita2d: fini y después liberar fuente. */
    vita2d_fini();
    if (g_font) {
        vita2d_free_pgf(g_font);
        g_font = NULL;
    }
}
