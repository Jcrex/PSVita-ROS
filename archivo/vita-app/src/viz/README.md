# src/viz/ — el mini-rviz dentro de la app

Escena 3D de los Objetivos 3/4 (diseño en `docs/11-diseno-mini-rviz.md`,
decisión de motor en ADR 0006, convivencia GPU en ADR 0007).

## Qué se valida dónde (regla del repo)

| Archivo | Qué es | Verificación |
|---|---|---|
| `camera.{h,c}` | Cámara orbital (Z-up, REP 103), lógica pura sin headers Vita | **HOST**: `scripts/check-viz-host.sh` (tests/camera_test.c) |
| `viz.{h,c}` | Escena vitaGL: grid 10×10 m + ejes RGB + cubo; un frame completo por llamada | **HARDWARE** (solo Vita) |
| `font8x8_basic.h` | Fuente bitmap 8×8, dominio público, vendorizada de dhepper/font8x8 | — (dato, no código) |

`ui.c` (en `src/`) también dibuja con vitaGL desde el ADR 0007 — mismo
estatus "validar en hardware"; su parte verificable en laptop sigue
siendo el layout generado (`scripts/check-ui-layout.sh`).

## Reglas heredadas que este código respeta

- El GPU se inicializa UNA vez (`vglInit` dentro de `ui_init()`) y no se
  cierra jamás: vitaGL no tiene shutdown (evidencia en ADR 0007).
- Los modos TELEOP/VIZ son estados del bucle de `main.c` (SELECT
  conmuta); cada modo dibuja su frame completo (clear + contenido +
  `vglSwapBuffers`).
- API GL solo del pipeline fijo que usan los samples oficiales de
  vitaGL (`auditoria/vitaGL/samples/`) — si necesitas una función nueva,
  comprueba ANTES que existe en `$VITASDK/arm-vita-eabi/include/vitaGL.h`.
- Próximas piezas (no escritas aún): `vbm.{h,c}` (loader del modelo,
  compilable en host, Etapa E1) y `draw_prims.{h,c}` si el render de
  primitivas crece (Etapa E2).
