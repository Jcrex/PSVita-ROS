# ADR 0007: convivencia vita2d ↔ vitaGL — Opción 2 (todo vitaGL)

- **Estado:** Aceptado
- **Fecha:** 2026-07-10

## Contexto

El mini-rviz (ADR 0006, `docs/11-diseno-mini-rviz.md`) necesita vitaGL
para la escena 3D, pero la app ya dibuja su UI declarativa con vita2d
(ADR 0005). Ambas bibliotecas inicializan el GPU (SceGxm) y el plan
(`docs/10` §B2) preveía decidir la convivencia con un experimento en
hardware entre dos opciones:

- **Opción 1:** modos excluyentes — `ui_shutdown()` (vita2d) antes de
  `viz_init()` (vitaGL) al entrar al modo 3D, y viceversa al salir.
- **Opción 2:** todo vitaGL — reescribir el backend de dibujo de `ui.c`
  sobre vitaGL; la UI declarativa (layout.json/codegen) no cambia.

## Evidencia (estática — hizo innecesario el experimento en hardware)

El experimento habría probado una API que **no existe**. Verificado el
2026-07-10 sobre la vitaGL instalada por vdpm y su código fuente
(clon de `Rinnegatamante/vitaGL` en `auditoria/`):

1. **vitaGL no tiene función de cierre.** El header
   (`$VITASDK/arm-vita-eabi/include/vitaGL.h`) no expone ningún
   `vglEnd`/`vglShutdown`/`vglTerminate`. Lo único con nombre de cierre
   es `eglTerminate`, y su implementación real (`source/egl.c:345`) es
   un no-op: `EGL_RET(EGL_TRUE)` — no libera nada.
2. **Los símbolos lo confirman a nivel binario:**
   `arm-vita-eabi-nm libvitaGL.a` no contiene NINGUNA referencia a
   `sceGxmTerminate` (ni a `sceGxmInitialize`: vitaGL inicializa por la
   variante `sceGxmVshInitialize`, `source/gxm.c:387`). En cambio
   `libvita2d.a` referencia `sceGxmInitialize` **y** `sceGxmTerminate`:
   vita2d sí sabe cerrar el GPU; vitaGL no.
3. Consecuencia mecánica: la secuencia de la Opción 1 funciona UNA sola
   vez y en un solo sentido (vita2d → `vita2d_fini()` → `vglInit()`).
   La vuelta (VIZ → TELEOP) exigiría que vitaGL soltara SceGxm, y no
   puede; el re-`vita2d_init()` chocaría con un GXM ya inicializado.
   Un "modo conmutables" con vita2d es **imposible a nivel de API**,
   no un fallo que el hardware pudiera desmentir.

## Decisión

**Opción 2: vitaGL es el único dueño del GPU durante toda la vida de la
app.** En concreto:

- `vglInit()` una vez al arrancar; no hay shutdown de GPU (el proceso
  muere con él, como en todo el homebrew que usa vitaGL).
- `ui.c` se reescribe como **backend vitaGL**: paneles = quads de
  color, texto = fuente bitmap propia (atlas 8×8 embebido como array C,
  escalado ×2) dibujada como quads texturizados. **El contrato no
  cambia**: mismo `ui.h`, mismo `layout.json`, mismo codegen
  `gen-ui-header.mjs`, mismos bindings. La regla de los 5 sitios sigue
  intacta.
- vita2d y `ScePgf` salen del enlace (`CMakeLists.txt`).
- El modo TELEOP y el modo VIZ son solo estados del bucle: mismo
  contexto GL, distinto contenido (2D ortográfico vs 3D perspectiva).
  SELECT conmuta sin tocar el GPU — el riesgo de crash por re-init
  desaparece por construcción.

## Consecuencias

**Positivas:** un solo dueño del GPU (cero incógnitas de convivencia);
la conmutación de modos es instantánea y segura; el 2D y el 3D pueden
incluso mezclarse en un mismo frame (etiquetas sobre la escena, útil
para E5); una dependencia gráfica menos.

**Negativas / coste:**

- Reescribir el dibujo de `ui.c` (~130 líneas) sobre vitaGL, incluida
  una fuente propia — se pierde la PGF de Sony. La métrica del texto
  cambia (8×8 escalado vs PGF ~20 px): la preview del editor web sigue
  siendo una aproximación consciente (como hasta ahora, ADR 0005) y se
  ajusta su constante de altura.
- `vita2d_load_PNG_file` ya no está para la UI v2 (Etapa C): las
  imágenes se cargarán con libpng directo (ya instalada en B1) a
  texturas GL — mismo trabajo, distinta API.
- ADR 0005 queda enmendado en el "cómo" (el backend ya no es vita2d)
  pero intacto en el "qué" (UI declarativa, codegen, excepción a la
  regla dual para el código de dibujo).

**Riesgo residual (validar en hardware en B3):** que `vglInit` +
nuestra pila XRCE/UDP convivan en RAM/hilos en la app real. Es el
primer punto de la verificación de la Etapa B3 (escena mínima + teleop
en regresión).

## Alternativas consideradas

**Opción 1 — modos excluyentes (descartada):** imposible a nivel de
API, ver Evidencia. Ni siquiera merece PoC en hardware: no hay función
que probar.

**Variante "una sola dirección" (descartada):** arrancar en vita2d y
saltar a vitaGL para siempre en el primer SELECT. Deja al usuario sin
teleop visual tras entrar una vez al 3D, o exige duplicar la UI en los
dos backends — peor que la Opción 2 en todos los ejes.

**3D a pelo con SceGxm compartiendo el contexto de vita2d
(descartada):** exigiría escribir shaders Cg y toda la tubería de
matrices/culling a mano dentro del contexto de vita2d — semanas de
trabajo para reinventar mal lo que vitaGL ya da.
