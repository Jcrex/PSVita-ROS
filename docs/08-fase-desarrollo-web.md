# 08 — Fase de desarrollo: la web como panel de control del proyecto

**Fecha de inicio:** 2026-07-06
**Estado:** En curso — **primer hito alcanzado el 2026-07-06** (los cuatro
puntos del criterio de abajo, más el compilador base y el debug en host,
operativos y verificados; detalle en `docs/06-bitacora-estado.md`). Queda
dentro de la fase: capa remota del compilador y debug en hardware real.
**Para qué sirve este documento:** declarar formalmente que arranca una
fase de desarrollo activa sobre `web/`, con alcance concreto y criterio de
cierre — no solo una lista de deseos (eso ya está en
`docs/07-requisitos-web-ide.md`), sino el compromiso de empezar a
construirlo ahora.

---

## Decisión y motivo

Con el Objetivo 1 cerrado (`docs/06-bitacora-estado.md`) y el Objetivo 2
repasado de nuevo (control de robot: sticks/botones/táctil →
`geometry_msgs/Twist`), el usuario decidió que, **antes** de entrar al
diseño detallado del Objetivo 2, tiene más prioridad desarrollar la web
como herramienta de trabajo del propio proyecto (dashboard ROS2, visor
3D/URDF/SDF, comparador C++/Rust, base del compilador, tutorial del SDK —
ver `docs/07`).

**Esto es una fase paralela a los objetivos numerados, no un objetivo
nuevo que reemplace al 2.** La regla de `docs/00-vision-y-objetivos.md`
("no se diseña en detalle el objetivo N+1 hasta cerrar el N") sigue
aplicando **al propio robot/consola**: el Objetivo 2 sigue sin diseño
detallado y sigue siendo el siguiente objetivo numerado en la secuencia.
Lo que cambia es que el *tooling* del proyecto (la web) no compite por el
mismo orden — es infraestructura de apoyo, y `docs/07` ya dejó documentado
qué partes de ella no dependen de ningún objetivo sin cerrar. Esta fase de
desarrollo se limita exactamente a esas partes.

---

## Alcance de esta fase

Tomado directamente de la tabla de `docs/07-requisitos-web-ide.md`
("Resumen de dependencias y orden sugerido"), los seis frentes que **sí**
se pueden construir ya:

| Frente | Requisito de origen | Qué implica arrancar |
|---|---|---|
| Comparador C++ ↔ Rust | `docs/07` §4 | Nueva colección/vista en `web/` que lea `modules/*/impl-c/` y `modules/*/impl-rust/` en split view |
| Tutorial del SDK de VitaSDK | `docs/07` §7 | Contenido nuevo en `docs/guias-vita/` (o serie corta tipo `docs/rust/`) explicando toolchain/cmake/empaquetado paso a paso |
| Dashboard ROS2 editable | `docs/07` §1 | Backend con acceso real a ROS2 (o al MCP existente) + stream en vivo (WebSocket/SSE) + persistencia de layout en SQLite |
| Debug de módulos duales en host | `docs/07` §6 (parte host) | UI web sobre gdb/lldb sobre los módulos duales, sin tocar la Vita |
| Visor 3D/URDF/SDF standalone | `docs/07` §3 (adelantado) | Visor con three.js (o similar) cargando URDF/SDF/mallas, sin integración en la Vita todavía |
| Base del compilador web | `docs/07` §5, Opción 1 | Backend que invoque el toolchain local (`source tools/env-devpc.fish` + `cmake --build`) desde un endpoint, en el propio PC |

Explícitamente **fuera de alcance** de esta fase (siguen bloqueados según
`docs/07`): la integración de assets 3D/URDF/SDF *dentro* de la app de la
Vita (necesita el Objetivo 3/4) y el debug en hardware real (necesita
investigación propia).

> Actualización 2026-07-07: el editor de diseño/UI de la app, que estaba en
> esta lista, se desbloqueó dándole primero UI a la app (declarativa, vita2d
> — ADR 0005) y entró en la fase como `/taller/ui` (docs/07 §2).

---

## Contexto de máquina

Esta fase se desarrolla con la sesión de trabajo corriendo en el **PC de
desarrollo** (`cachyos-x8664`, `192.168.1.65`, `toolchains/vitasdk/`
presente) — no en la laptop. Es relevante para la "base del compilador
web": al tener el toolchain VitaSDK en el mismo host, ese frente puede
construirse como invocación local desde el inicio (ver `docs/07` §5).

---

## Cómo se cierra (o se marca "en curso" de forma honesta)

Esta fase no tiene un criterio binario único como la Fase 1 (incógnita
dura resuelta / no resuelta) porque son seis frentes independientes. Se
considera que la fase tiene un primer hito sólido cuando estén operativos
en la web real (no solo maquetados):

1. Comparador C++/Rust navegable con al menos los 3 módulos duales.
2. Tutorial del SDK de VitaSDK publicado en `/guias` o `/docs`.
3. Visor 3D/URDF/SDF cargando al menos un modelo de prueba.
4. Dashboard con al menos un widget en vivo (logs o topics) conectado a
   datos reales, no mockeados.

El compilador base y el debug en host pueden llegar después dentro de la
misma fase — no bloquean el primer hito.

**Actualizar al avanzar:** cada vez que uno de los seis frentes pase de
"pendiente" a "en curso" o "hecho", reflejarlo en
`docs/06-bitacora-estado.md` y en `web/src/data/fases.ts` (nueva entrada
`fase-web`), igual que el resto de hitos del proyecto.
