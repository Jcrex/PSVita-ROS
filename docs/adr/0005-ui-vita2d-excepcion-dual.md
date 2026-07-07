# ADR 0005: UI de la app con vita2d + layout declarativo (excepción a la regla dual)

- **Estado:** Aceptado
- **Fecha:** 2026-07-07

## Contexto

Hasta este punto la app `vita-ros2-hello` no dibujaba nada (pantalla negra
intencional, Fase 1: solo conectividad). Para avanzar hacia el editor de la
app desde la web (`docs/07-requisitos-web-ide.md` §2) hace falta primero que
la app tenga una UI que editar.

La regla central del proyecto (`docs/03-estrategia-dual-rust-cpp.md`) exige
dos implementaciones equivalentes (Rust + C) para cada módulo de bajo nivel,
con tests de paridad ejecutables en host. Aplicada al renderizado había dos
caminos:

1. **Módulo dual `ui-fb` por software**: dibujar en un framebuffer RGBA en
   memoria (paridad píxel a píxel en host) y presentarlo con `sceDisplay` en
   la Vita. Máxima coherencia con la regla dual, pero sin GPU y con un coste
   de implementación alto (rasterizado de texto propio incluido).
2. **libvita2d del VitaSDK**: la biblioteca 2D estándar del homebrew (GPU
   vía SceGxm, fuente PGF del sistema). Solo existe para la Vita y solo en C:
   nada del dibujado es verificable en la laptop ni tiene paridad Rust.

## Decisión

Se usa **vita2d** (opción 2), por decisión explícita del usuario
(2026-07-07), con dos acotaciones que limitan el daño de la excepción:

- **El dibujado es código de app, no un módulo dual.** Vive en
  `vita-app/src/ui.c` (+`ui.h`) y no entra en `modules/`: la regla dual sigue
  intacta para todo lo que esté por debajo (red, transporte, memoria). No hay
  rama host ni paridad para `ui.c`; todo su comportamiento se valida en el PC
  y en hardware, y así queda marcado en código y README.
- **La UI es declarativa, y el dato SÍ es verificable en host.** La pantalla
  se describe en `vita-app/ui/layout.json` (paneles, textos, valores ligados
  a datos de la app). `scripts/gen-ui-header.mjs` lo convierte en
  `src/ui_layout.h` (array constante de `ui_widget`, tipos en
  `src/ui_types.h`, sin dependencias de la Vita) y
  `scripts/check-ui-layout.sh` verifica en la laptop que el header generado
  compila como C99 estricto. `ui.c` es un intérprete pequeño y estable de ese
  array; lo que cambia con cada rediseño es el JSON, no el C.

Ese JSON es además el contrato del editor web (`/taller/ui`): la web edita el
layout con una preview 2D aproximada (la emulación en navegador se descartó —
`web/README.md`), lo aplica al repo vía el taller y recompila el `.vpk` con
el flujo ya existente.

## Consecuencias

**Positivas:**

- GPU y fuente del sistema resueltas de serie; `ui.c` queda en ~150 líneas.
- El ciclo de edición de UI no toca C: editar JSON (web o a mano) →
  regenerar → recompilar. El editor web no necesita entender de vita2d.
- La app sigue compilando en ambas variantes (`VITA_IMPL=c|rust`): la UI es
  código de app compartido, independiente de qué implementación de los
  módulos duales se enlaza.

**Negativas / riesgos:**

- Primera pieza del proyecto sin paridad Rust ni verificación en host del
  comportamiento: un bug de dibujado solo se ve en hardware.
- Dependencia nueva del build del PC: libvita2d (incluida en VitaSDK; si
  falta, `vdpm vita2d`). El conjunto exacto de stubs a enlazar puede variar
  con la versión — queda "validar en el PC" en el CMakeLists.
- Si los Objetivos 3/4 (rviz2 en la Vita) exigieran otra pila gráfica, la UI
  declarativa migra (es JSON + un intérprete), pero `ui.c` se reescribe.
