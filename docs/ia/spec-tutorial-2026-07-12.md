# Diseño — Tutorial práctico C/Rust sobre el código real del proyecto

- **Fecha:** 2026-07-12
- **Branch:** `tutorial-vita` (todo el aprendizaje vive aquí; no se toca `main`)
- **Ubicación del material:** `docs/tutorial/`
- **Estado:** aprobado por el usuario, pendiente de plan de implementación

## Objetivo

Que el usuario (Jcrex) sea capaz de **leer, modificar y compilar por su cuenta**
el código C y Rust del proyecto PS Vita ↔ ROS2, sin depender del asistente.
No es un curso general de C/Rust: es un **recorrido guiado del código real del
repo** con retos de modificación sobre ese mismo código.

## Perfil del alumno (calibración)

- Sabe programar (lógica, funciones en algún lenguaje).
- **Nuevo para él:** punteros y memoria en C, structs de bajo nivel, y **todo
  Rust** (ownership, `Result`, `unsafe`, FFI).
- Es principiante en Rust (ya registrado en la memoria del proyecto).

Consecuencia: se explica despacio punteros/memoria y cada construcción nueva de
Rust; no se explica desde cero qué es una función o un condicional.

## Formato de cada lección (invariante)

Toda lección sigue el mismo ritmo, elegido por el usuario:

1. **Leemos** el archivo real del repo (`impl-c/*.c`, `impl-rust/src/lib.rs`,
   `vita-app/src/*.c`, headers…).
2. **Explicamos** los conceptos nuevos de C y Rust que aparecen ahí,
   comparándolos entre sí y con lenguajes de alto nivel.
3. **Retos**: modificaciones sobre ese código real, de menor a mayor
   dificultad.
4. **Verificación**: cómo comprobar que el reto quedó bien.

## Estructura de carpetas

```
docs/tutorial/
  00-guia-del-tutorial.md            # mapa, cómo compilar (host/PC), cómo verificar,
                                     # el patrón dual (header = verdad del módulo)
  01-c-fundamentos-con-mem-pool.md
  02-rust-fundamentos-con-mem-pool.md
  03-net-udp-sockets-y-sdk.md
  04-microros-transport-integracion.md
  05-app-vita-el-sdk-y-main.md
  06-compilar-y-empaquetar-vpk.md
  soluciones/                        # una solución por lección (retos resueltos)
```

Orden pedagógico: **mem-pool → net-udp → microros-transport → app Vita →
compilar/empaquetar**. mem-pool primero por ser el módulo más autocontenido
(sin red, sin SDK), ideal para introducir punteros, memoria y el patrón dual.
Se hace **C antes que Rust** sobre el mismo módulo: primero se domina el
concepto de bajo nivel en C y luego se ve cómo Rust lo expresa de forma segura.

## Las dos vías de compilación y verificación

Cada reto se etiqueta con dónde se compila, para que el usuario aprenda el
ciclo real, no solo teoría:

- 🐳 **Host (docker)** — código de los módulos (C y Rust). Corre en cualquier
  máquina vía `tools/run-parity-tests.sh [módulo]` (usa docker `rust:1-slim`
  para Rust). Verificación inmediata con los tests de paridad.
- 🎮 **PC/Vita** — código específico de la Vita (SDK, `main.c`, `.vpk`). Solo
  compila en el PC CachyOS (`192.168.1.65`) con VitaSDK. **El usuario ejecuta
  estos retos por su cuenta** (su flujo `git pull` + compilar, o SSH interactivo
  que él inicia). El tutorial provee los comandos exactos y marca el código
  "validar en el PC / hardware" según la convención del proyecto.

> Nota: el asistente no tiene acceso SSH no interactivo al PC (solo autentica
> por clave/contraseña interactiva). Por decisión explícita del usuario —que
> quiere aprender a compilar por su cuenta— **las compilaciones PC/Vita las
> hace siempre el usuario**. No se configura acceso automático.

## Cobertura (alcance)

**Dentro:** los tres módulos duales (mem-pool, net-udp, microros-transport) en
C y Rust, y la app Vita (`vita-app/src/`: `main.c`, glue uxr, netlog, teleop,
UI/viz, llamadas al SDK, FFI Rust→C vía el crate umbrella
`vita-app/rust-modules/`, CMake/VitaSDK y empaquetado `.vpk`).

**Fuera:** servidor MCP (Python) y web (Astro/TS). No forman parte de este
tutorial de C/Rust.

## Publicación en la web

Como manda la regla del proyecto ("toda la documentación se publica en la web"):

- Añadir una colección `tutorial` en `web/src/content.config.ts` (glob sobre
  `docs/tutorial/**/*.md`).
- Añadir su sección en la navegación de la web.
- Añadir la línea `COPY` de `docs/tutorial` en `web/Dockerfile`.

Cada lección aparece en la web tras un rebuild. La colección y la sección se
crean una sola vez (en la fase de estructura); las lecciones posteriores no
requieren cambios de infraestructura web.

## Soluciones a los retos

Cada reto tiene su solución en `docs/tutorial/soluciones/` (y/o en bloques
`<details>` plegables que la web renderiza), para que el usuario intente
primero y compare después.

## Relación con material existente

- `docs/rust/` (serie de referencia "construcción a construcción") **se
  mantiene**. Este tutorial es complementario y práctico; enlazará a
  `docs/rust/` cuando convenga profundizar en una construcción concreta, en
  vez de duplicar.
- **No se toca** la bitácora de `main` (`docs/06-bitacora-estado.md`) ni
  `web/src/data/fases.ts`: al ser branch aparte de aprendizaje, el progreso se
  registra dentro de `docs/tutorial/` (p. ej. en `00-guia-del-tutorial.md`).

## Método de entrega (importante)

**No se escriben las 6 lecciones de golpe.** El plan de implementación fasea:

1. **Fase 0 — Andamiaje:** branch (hecho), `00-guia-del-tutorial.md`,
   integración web (colección + sección + Dockerfile), carpeta `soluciones/`.
2. **Fase 1 — Lección 01 (plantilla):** `01-c-fundamentos-con-mem-pool.md`
   completa, que fija el estilo y el ritmo del resto.
3. **Fases siguientes — una lección a la vez:** 02 → 06, iterando con el
   usuario, a su ritmo de aprendizaje.

## Criterios de éxito

- El usuario puede explicar, para mem-pool, qué hace cada función en C y su
  equivalente en Rust, y por qué el `unsafe` es necesario.
- El usuario completa al menos un reto 🐳 host verificándolo él mismo con
  `tools/run-parity-tests.sh`.
- El usuario compila la app Vita en el PC por su cuenta siguiendo la lección 06.
- El material queda publicado y navegable en la web.
