/**
 * viz.h — Escena 3D del mini-rviz (Etapa B3: grid + ejes + cubo).
 *
 * SOLO VITA (vitaGL) — VALIDAR EN HARDWARE. La matemática testeable en
 * host vive en camera.{h,c}; aquí solo hay llamadas GL.
 *
 * ADR 0007: el GPU lo inicializa ui_init() (vglInit, único dueño);
 * viz_init() solo prepara estado de escena. viz_draw() dibuja UN frame
 * completo (clear + 3D + swap), simétrico a ui_draw() del modo TELEOP.
 */
#ifndef VITA_VIZ_H
#define VITA_VIZ_H

#include <stdbool.h>

#include "camera.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Prepara la escena (nada de GPU todavía). Requiere ui_init() previo. */
bool viz_init(void);

/** Frame completo del modo VIZ: grid 10×10 m + ejes XYZ (RGB) + cubo. */
void viz_draw(const viz_camera *cam);

void viz_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif /* VITA_VIZ_H */
