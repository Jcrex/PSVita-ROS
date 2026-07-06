# 07 — Requisitos: la web como IDE/panel de control del proyecto

**Fecha de creación:** 2026-07-06
**Estado:** Recopilación de requerimientos — visión a largo plazo, sin diseño
detallado ni compromiso de calendario.
**Para qué sirve este documento:** capturar, en un solo lugar, todo lo que
el usuario quiere que la web (`web/`) llegue a ser: no solo un sitio de
presentación y guías, sino un panel de control ROS2, un editor/compilador
de la app de la Vita y un espacio de aprendizaje C++↔Rust con tutoriales
del SDK. Sirve de punto de partida para diseñar cada pieza cuando le toque
el turno, **no** es una spec lista para implementar.

---

## Cómo leer este documento

Varios de los requisitos de abajo dependen de objetivos del proyecto que
**todavía no están validados** (ver `docs/00-vision-y-objetivos.md`, regla
"proyecto secuencial por objetivos": no se diseña en detalle el objetivo
N+1 hasta cerrar el N). A fecha de esta bitácora, el proyecto cerró la
Fase 1 / Objetivo 1 (topics ROS2) y no ha empezado el Objetivo 2 (control
con sticks/botones/táctil). Por eso este documento:

- Anota **todos** los requerimientos tal como se pidieron, sin recortarlos.
- Señala explícitamente, por sección, **qué objetivo del proyecto lo
  desbloquea** y si choca con alguna restricción transversal ya acordada
  (`docs/00-vision-y-objetivos.md`, `CLAUDE.md`).
- Deja preguntas abiertas donde la implementación depende de una decisión
  de arquitectura que aún no se ha tomado, en vez de inventarla aquí.

**Actualización 2026-07-06 — decisión explícita del usuario:** aunque el
Objetivo 2 aún no ha empezado, el usuario quiere **empezar ya a preparar
la infraestructura web** que hará falta para el Objetivo 3/4 (rviz2 en la
Vita + visualización de robots/mapas). Esto no es adelantar el *diseño
detallado* del Objetivo 3/4 en sí (esa incógnita sigue abierta y depende
de `docs/04-investigacion-portabilidad-rviz2.md`), sino construir de una
vez las piezas de la web que son útiles independientemente de en qué
objetivo estemos: el visor 3D/URDF/SDF standalone (§3) y la base del
pipeline de compilación (§5). Las secciones §3 y §5 se actualizaron para
reflejar que este trabajo entra en alcance activo ya, no a futuro.

Además, **esta sesión de trabajo corre en el PC de desarrollo**
(`cachyos-x8664`, `192.168.1.65`), no en la laptop — confirmado por
`hostname`/IP y por la presencia de `toolchains/{vitasdk,rustup,cargo,cmake}/`
en el repo. Esto es relevante sobre todo para §5 (compilador web): el
host donde se está preparando la web **ya tiene VitaSDK instalado**, así
que la parte más difícil de la Opción 1 de aquella sección (disparar un
build remoto desde otra máquina) deja de aplicar mientras el trabajo se
haga desde aquí. La tabla de roles de máquinas de `CLAUDE.md` no cambia
como descripción general del proyecto (la laptop sigue siendo el taller
portátil que no instala nada); lo que cambia es que, en este momento
puntual, el trabajo de preparar la web ocurre en la máquina que sí tiene
el toolchain.

---

## 1. Dashboard ROS2 (logs, datos, topics) — editable

**Qué se pide:** una sección de la web donde se puedan leer en vivo:
- Los logs de la app de la Vita (hoy viajan por UDP a `tools/netlog-listen.sh`,
  ver `vita-app/src/netlog.c`).
- Los datos/mensajes de los topics ROS2 activos.
- La lista de topics, nodos y tipos del grafo (ya existe introspección
  equivalente en `mcp/ros2-introspection/`, pero solo para Claude Code, no
  para la web).

Y que el dashboard sea **editable**: el usuario debe poder configurar qué
paneles/widgets ve, qué topics sigue, cómo se organiza la vista (layout
tipo Grafana/RViz "panels").

**Requisitos concretos:**
- Widget de logs en vivo (stream, no polling manual) con filtro por
  severidad/origen (Vita vs. agente vs. ROS2).
- Widget de topics: lista + tipo + frecuencia + último valor (similar a
  `ros2 topic list` + `ros2 topic echo` combinados).
- Widget de "salud de sesión XRCE": conectado/desconectado, IP de la Vita,
  IP del agente, timestamp del último mensaje.
- Edición del dashboard: añadir/quitar/mover widgets, guardar el layout
  (persistencia — la web ya usa SQLite vía `better-sqlite3`, patrón
  reutilizable del checklist de `/api/checklist`).
- Decidir mecanismo de transporte en vivo hacia el navegador: WebSocket o
  SSE desde el backend Astro (el backend sí puede tener acceso a ROS2/red
  local si corre en la laptop, que es donde vive el agente micro-ROS).

**Objetivo del proyecto que lo desbloquea:** ninguno estrictamente — es
observabilidad transversal, útil desde ya para depurar la Fase 1 y crece
naturalmente hacia el Objetivo 2 (telemetría de control) y el 4
(visualización tipo RViz). De hecho `web/README.md` ya menciona esto como
paso futuro ("telemetría en vivo del grafo ROS2").
**Dependencia técnica:** el backend que sirva este dashboard necesita
conectividad real a ROS2 (rclpy o similar) o hablar con el MCP existente
— hoy la web no tiene esa integración, habría que construirla.

---

## 2. Editor de la app de la Vita (diseño, funcionalidad, frontend) y VPK

**Qué se pide:** poder editar desde la web:
- El **diseño** de la app de la Vita (UI que se dibuja en pantalla).
- Las **funcionalidades** (qué hace la app: topics que publica/suscribe,
  comportamiento).
- El **frontend general** de la app (layout, controles en pantalla).
- Y que todo eso se traduzca en un nuevo `.vpk` instalable.

**Requisitos concretos:**
- Editor de código o editor visual (a decidir) para `vita-app/src/`.
- Vista previa de cómo quedaría el diseño (aunque la emulación en
  navegador ya se evaluó y **se descartó por inviable** — ver
  `web/README.md`, sección "Decisión: previsualización/emulación en la
  web" — Vita3K no tiene port WebAssembly). Cualquier "preview" tendría
  que ser una aproximación 2D del layout, no una emulación real.
- Guardar variantes/versiones de la app (parecido a un historial de
  builds).

**Objetivo del proyecto que lo desbloquea:** Objetivo 2 (control con
sticks/botones/táctil) en adelante — hoy la app de la Vita
(`vita-ros2-hello`) no tiene UI dibujada, es intencionalmente una prueba de
conectividad sin gráficos (pantalla negra esperada, ver
`docs/06-bitacora-estado.md`). Diseñar un editor de UI antes de tener una
UI que editar es diseño prematuro según la regla secuencial del proyecto.
**Pregunta abierta:** ¿"editar el frontend" significa un editor de código
(con syntax highlighting, tipo Monaco) sobre los `.c`/`.rs` de
`vita-app/src/`, o un editor visual de más alto nivel (arrastrar
botones/paneles)? Son proyectos de tamaño muy distinto.

---

## 3. Modelos 3D, URDF y SDF: visualizar e integrar en las apps de la Vita

**Qué se pide:** que la web permita visualizar modelos 3D, archivos URDF y
SDF, y que esos assets se puedan integrar en las apps que corren en la
Vita.

**Requisitos concretos:**
- Visor 3D en la web (por ejemplo three.js) que cargue URDF/SDF y mallas
  (`.stl`/`.dae`/`.obj`) — esto es tooling estándar en el ecosistema ROS2
  (equivalente web de RViz para modelos de robot).
- Un pipeline que tome esos assets y los empaque/convierta para que la app
  de la Vita los pueda cargar y renderizar en su propia pantalla.

**Objetivo del proyecto que lo desbloquea:** este es, literalmente, el
**Objetivo 3 y 4** del proyecto ("compilar rviz2 en la consola",
"visualizar robots, mapas y topics en rviz2 como en un PC") — el propio
`docs/00-vision-y-objetivos.md` los describe como "incógnitas documentadas,
no diseñadas aún". `docs/04-investigacion-portabilidad-rviz2.md` ya tiene
una investigación de viabilidad a nivel de hipótesis — sigue siendo el
punto de partida obligado antes de comprometerse al *diseño detallado* de
cómo la Vita renderiza esto en su propia pantalla (esa parte sigue sin
empezar el Objetivo 2 y no se adelanta aquí).

**Decisión 2026-07-06 (preparación anticipada, activa ya):** la parte de
"visor 3D/URDF/SDF en la web" (sin tocar la Vita) **sí entra en alcance
ahora**, por decisión explícita del usuario, aunque el Objetivo 2 no haya
empezado. Es una pieza independiente de la Vita: un visor con three.js (o
similar) que cargue URDF/SDF y mallas, corriendo enteramente en la web.
Sirve de por sí (visualizar el robot que eventualmente se controlará en el
Objetivo 2) y adelanta trabajo reutilizable para cuando toque el Objetivo
3/4 (el formato de los assets, el parser de URDF/SDF y la UI del visor no
cambian por dónde se renderice después). Lo que **no** se adelanta es la
integración en la Vita (empaquetar esos assets para que la app homebrew
los cargue y dibuje en su propia pantalla) — eso sigue bloqueado por la
incógnita de portabilidad de `docs/04`.

---

## 4. Sección comparativa C++ ↔ Rust (para estudiar)

**Qué se pide:** una sección de la web para comparar código C++ y Rust
lado a lado, como ayuda de aprendizaje.

**Requisitos concretos:**
- Vista lado a lado (split view) de un mismo módulo en su versión C y su
  versión Rust.
- El material ya existe en gran parte: cada módulo dual
  (`modules/{mem-pool,net-udp,microros-transport}/`) tiene `impl-c/` e
  `impl-rust/` detrás del mismo header — son comparables por construcción.
  `docs/rust/` ya es una serie de aprendizaje ligada a este código real
  (`CLAUDE.md`: "todo constructo nuevo de Rust debe explicarse en
  comentarios y/o esta serie").
- Requisito de UI: resaltado de sintaxis para ambos lenguajes, idealmente
  con líneas equivalentes alineadas o al menos referenciadas.

**Objetivo del proyecto que lo desbloquea:** ninguno — es una herramienta
de aprendizaje transversal, alineada con el Objetivo 6 (toolkit /
estandarizar el desarrollo) y con la preferencia ya registrada del usuario
de ser principiante en Rust y querer todo documentado (ver memoria
`preferencias-usuario.md`). Se puede construir ya, leyendo directamente
`modules/*/impl-c/` y `modules/*/impl-rust/` con globs (mismo patrón que
usa `content.config.ts` para las guías).

---

## 5. Compilador integrado + envío del binario a la Vita

**Qué se pide:** que desde la web se puedan compilar los programas de la
Vita y enviarlos directamente a la consola.

**Esto tiene que respetar una restricción transversal ya acordada**
(`docs/00-vision-y-objetivos.md`, "La laptop no instala nada": *"El equipo
portátil utilizado como taller de preparación produce únicamente
artefactos de texto (...). Toda compilación, instalación y ejecución ocurre
en el PC de desarrollo (CachyOS)"*) y con `CLAUDE.md` ("No project
toolchains are installed on the laptop (...) Vita compilation only happens
on the PC"). La regla en sí no cambia: la laptop nunca tendrá VitaSDK. Lo
que sí cambia con la aclaración del usuario (2026-07-06) es **dónde se está
preparando la web ahora mismo**: esta sesión corre en el propio PC de
desarrollo (`cachyos-x8664`, `192.168.1.65`), que ya tiene
`toolchains/vitasdk/`, `toolchains/rustup/`, `cargo-vita` y cmake portable
instalados (ver `docs/06-bitacora-estado.md`). Eso simplifica el problema:

**Opciones de arquitectura, actualizadas:**
1. **(Ahora, mientras se trabaja desde el PC) El backend de la web invoca
   el toolchain local directamente** — sin SSH ni runner remoto: el mismo
   host que sirve la web ejecuta `source tools/env-devpc.fish` +
   `cmake --build` + empaquetado `.vpk`, exactamente el flujo manual de
   `docs/06` pero disparado por un endpoint en vez de una terminal. Es la
   opción más simple y la que tiene sentido preparar primero, dado que el
   trabajo de la web ya se está haciendo aquí.
2. **(Cuando la web vuelva a servirse desde la laptop o un servidor
   externo)** el backend necesitará disparar un build remoto en el PC (SSH,
   un runner/agente que escuche jobs, o un CI self-hosted en el PC) y
   traerse el artefacto de vuelta. Mantiene la regla "toda compilación
   ocurre en el PC"; es la misma idea que la Opción 1 original de este
   documento, ahora marcada como el caso "web remota" en vez del caso
   general.
3. **Contenedor de compilación con el toolchain VitaSDK** en otro host
   (técnicamente viable, VitaSDK no depende de hardware especial) — esto
   sí reinterpretaría la regla actual (instalar el toolchain fuera del
   PC), se descarta salvo que el usuario lo pida explícitamente.
4. **Solo los módulos dual C/Rust** (que ya compilan/testean también en
   host vía Docker, `tools/run-parity-tests.sh`) se compilan/verifican
   desde la web; el empaquetado final del `.vpk` sigue siendo manual. Sigue
   siendo válido como primer paso incremental, compatible con la Opción 1.

**Implicación práctica:** como el trabajo de preparación de la web se está
haciendo ahora en el PC, tiene sentido diseñar primero el endpoint/servicio
de build asumiendo *ejecución local* (Opción 1) y dejar la Opción 2
(remota) como una capa de transporte que se añade después sin rediseñar el
core — el propio `cmake --build` no cambia, solo cómo se invoca.

**Envío a la Vita:** hoy es manual — USB o FTP vía VitaShell (ver
`docs/guias-vita/vitashell.md`). Automatizarlo por red (FTP scripted a la
IP de la Vita) es factible una vez exista el binario; la parte dura es de
dónde sale el binario (arriba).

**Objetivo del proyecto que lo desbloquea:** Objetivo 6 (toolkit /
estandarizar el desarrollo) es el que más naturalmente incluye esto —
busca que "otro desarrollador pueda replicar el entorno y comenzar su
propio proyecto ROS2 en PS Vita partiendo de esta base"; un compilador web
sería la culminación de eso, pero requiere que los objetivos 2-5 ya hayan
generado suficiente código de app real para que compilar-desde-la-web
aporte valor frente a hacerlo en el PC directamente.
**Pregunta abierta:** ¿la intención es reemplazar el flujo manual del PC
para ti mismo (uso personal, un solo desarrollador), o que un tercero use
la web para compilar sin tener PC con VitaSDK? La respuesta cambia mucho
el diseño (opción 1 vs. 2 de arriba).

---

## 6. Sistema de depuración integrado

**Qué se pide:** un sistema de depuración de código integrado en la web.

**Requisitos concretos (a definir cuando le toque el turno):**
- Depuración de los módulos duales en host (gdb/lldb ya disponible vía
  Docker `rust:1-slim` / gcc local para C) expuesta con una UI web —
  esto es lo más alcanzable a corto plazo, no depende de la Vita.
- Depuración de la app **en la Vita real** es un problema mucho más duro:
  la Vita no es Linux (newlib, `sceKernel*`), no hay gdbserver estándar
  para VitaSDK sin tooling adicional (existe algo de soporte con
  `vita-parse-core`/`psp2gdb` en la escena homebrew, no evaluado aún en
  este proyecto). Hoy la única "depuración" real en hardware es el netlog
  UDP (`vita-app/src/netlog.c`) — logs de texto, no breakpoints.

**Objetivo del proyecto que lo desbloquea:** transversal, pero la parte
"depurar en la Vita real" depende de investigar herramientas del
ecosistema VitaSDK que este proyecto todavía no ha evaluado — sería un
ADR propio antes de comprometerse a una solución.

---

## 7. Guía tutorial del SDK de la Vita (para desarrollo en consola)

**Qué se pide:** una guía/tutorial de cómo funciona todo el SDK de la Vita
para el desarrollo en la consola, con tutoriales.

**Requisitos concretos:**
- Explicar VitaSDK de punta a punta: toolchain, `cmake`, `vita-elf-create`,
  `vita-make-fself`, `vita-mksfoex`, `vita-pack-vpk`, estructura de un
  `.vpk`, `param.sfo`.
- Tutoriales prácticos, no solo referencia — "cómo hacer X paso a paso".
- Parcialmente ya existe: `docs/05-setup-entorno-cachyos.md` (setup del
  entorno), `docs/guias-vita/` (7 guías de instalación/uso en la consola,
  ya publicadas en `/guias` de la web con checklist interactivo), y los
  ADRs relevantes (`docs/adr/0001-vitasdk-toolchain-base.md`,
  `0004-empaquetado-vpk-cmake.md`).
- Lo que falta es una guía "cómo se compila y empaqueta una app VitaSDK
  desde cero, explicando cada herramienta", más orientada a enseñar el SDK
  en sí que a instalar/configurar el homebrew ya construido (que es lo que
  cubren las guías actuales).

**Objetivo del proyecto que lo desbloquea:** Objetivo 6 (toolkit /
documentación para que un tercero replique el proyecto) — es, de los siete
requisitos de este documento, el más alineado con el estado actual del
proyecto y el que menos depende de objetivos futuros. Se puede escribir ya
como `docs/guias-vita/vitasdk-toolchain.md` (o una serie corta, siguiendo
el patrón de `docs/rust/00-02`) sin bloquear con nada.

---

## Resumen de dependencias y orden sugerido (no vinculante)

| # | Requisito | Bloqueado por objetivo del proyecto | Se puede empezar ya |
|---|---|---|---|
| 4 | Comparador C++/Rust | Ninguno | **Sí** |
| 7 | Tutorial del SDK de Vita | Ninguno | **Sí** |
| 1 | Dashboard ROS2 editable | Ninguno (crece con Obj. 2/4) | Sí, con trabajo de backend nuevo |
| 6 (parte host) | Debug de módulos duales en host | Ninguno | Sí, con trabajo de backend nuevo |
| 2 | Editor de diseño/UI de la app | Objetivo 2 | No — no hay UI que editar todavía |
| 5 | Compilador web → `.vpk` → Vita | Objetivo 6 | **Sí (Opción 1)** — el propio host de trabajo ya tiene VitaSDK |
| 3 | Visor URDF/SDF/3D standalone | Objetivo 3/4 (rviz2), preparación adelantada por decisión explícita | **Sí** — sin tocar la Vita |
| 3 (integración en la Vita) | Cargar assets URDF/SDF/3D en la app real | Objetivo 3/4 (rviz2) | No — depende de la incógnita de `docs/04` |
| 6 (parte Vita) | Debug en hardware real | Investigación propia (ADR pendiente) | No sin investigar antes |

Este documento no obliga a seguir este orden — es la lectura del propio
orden secuencial que el proyecto ya se impuso en
`docs/00-vision-y-objetivos.md`, aplicada a estos siete requisitos
concretos, con el ajuste explícito de 2026-07-06: el visor 3D/URDF/SDF
standalone y la base del compilador web entran en alcance activo ya,
mientras que el diseño detallado del Objetivo 2 (control) y de la
integración Vita del Objetivo 3/4 (rviz2) siguen sin empezar.
