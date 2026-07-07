/**
 * ui.h — Dibujado de la UI declarativa con vita2d (SOLO Vita, SOLO C).
 *
 * ADR 0005: el renderizado es código de app, no módulo dual — no hay rama
 * host ni paridad Rust. Lo verificable en laptop es el layout generado
 * (scripts/check-ui-layout.sh); este archivo se valida en el PC/hardware.
 */
#ifndef VITA_UI_H
#define VITA_UI_H

#include <stdbool.h>

#include "ui_types.h"

/** Inicializa vita2d + fuente PGF del sistema. false si la fuente no carga. */
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

#endif /* VITA_UI_H */
