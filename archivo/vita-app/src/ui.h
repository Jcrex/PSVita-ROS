/**
 * ui.h — Dibujado de la UI declarativa con vitaGL (SOLO Vita, SOLO C).
 *
 * ADR 0005: el renderizado es código de app, no módulo dual — no hay rama
 * host ni paridad Rust. Lo verificable en laptop es el layout generado
 * (scripts/check-ui-layout.sh); este archivo se valida en el PC/hardware.
 * ADR 0007: el backend pasó de vita2d a vitaGL (un solo dueño del GPU
 * para convivir con el modo VIZ 3D). ui_init() es el ÚNICO vglInit().
 */
#ifndef VITA_UI_H
#define VITA_UI_H

#include <stdbool.h>

#include "ui_types.h"

/** Inicializa vitaGL (único init del GPU) + la fuente bitmap embebida. */
bool ui_init(void);

/** Dibuja un frame completo: fondo + UI_WIDGETS (ui_layout.h) con `st`. */
void ui_draw(const ui_state *st);

/**
 * Pantalla de error fatal: fondo + `msg`, durante `segundos`. Para que los
 * fallos de arranque se vean en la consola y no solo en el netlog.
 * No-op si ui_init no tuvo éxito.
 */
void ui_draw_fatal(const char *msg, int segundos);

void ui_shutdown(void);

/* --- Primitivas para pantallas fuera del layout declarativo (p. ej.
 * la pantalla de configuración de IP, config_ui.c). Un frame se
 * compone como: ui_frame_begin() + rects/textos + ui_frame_end(). --- */

#include <stdint.h>

/** Limpia la pantalla (fondo del layout) y deja la proyección 2D. */
void ui_frame_begin(void);

/** Presenta el frame (swap). */
void ui_frame_end(void);

/** Rectángulo relleno; color RGBA8 empaquetado (r|g<<8|b<<16|a<<24). */
void ui_rect(float x, float y, float w, float h, uint32_t color);

/** Texto con la fuente bitmap; (x,y) = esquina superior izquierda. */
void ui_texto(float x, float y, uint32_t color, float escala,
              const char *txt);

#endif /* VITA_UI_H */
