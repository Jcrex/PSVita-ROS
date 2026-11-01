---
title: "Informe 01a — Limpieza de scripts e infraestructura"
description: "Qué sobra, qué está desactualizado y qué parece viejo pero sigue vivo en tools/, docker/, vita-app/, web/, mcp/ y skills/."
fecha: 2026-11-01
---

# Informe 01a — Limpieza de scripts e infraestructura

**Resumen:** casi nada está muerto. Hay 3 ficheros basura, 7 desactualizados y un bloque grande
(la app de la Fase 1, `vita-app/`) que es histórico pero **Godot 4 todavía usa piezas suyas**.
Detalle y evidencia: `docs/ia/auditoria/01a-limpieza-tools-infra.md`.

## Candidatos

| Ruta | Acción | Por qué |
|---|---|---|
| `web/localhost:4321` | BORRAR | Fichero vacío subido por accidente |
| `mcp/.gitkeep`, `skills/.gitkeep` | BORRAR | Restos del esqueleto; las carpetas ya tienen contenido |
| `tools/vita-doctor.sh` | ACTUALIZAR | Busca el cliente XRCE en `third_party/install/`, que no existe (es `xrce-vita*`): siempre da «falta» |
| `tools/netlog-listen.sh` | ACTUALIZAR | No filtra la basura binaria del enchufe Kasa en el puerto 9999 |
| `skills/vita-build-package` | ACTUALIZAR | Enseña `cargo-vita`, que el repo no usa; no explica el flujo Godot 4 |
| `skills/vita-dual-module` | ACTUALIZAR | Pide `staticlib` en el módulo; la regla es `rlib` |
| `skills/vita-deploy-logs` | ACTUALIZAR | Se contradice («validado» y «sin validar»); solo cubre logs de la Fase 1 |
| `README.md` | ACTUALIZAR | Dice «ros2_vita sin compilar», «3 módulos», falta `docker/` |
| `CLAUDE.md` (líneas 19 y 25) | ACTUALIZAR | El agente ya no va en la laptop con `robotnik_dev`, sino en la estación `docker/` |
| `vita-app/rust-modules/`, `vita-app/scripts/build-xrce-client-vita.sh` | CONSERVAR (mover luego) | Los usan `tools/build-rust-pic.sh` y `godot/ros2_vita/SCsub` |
| Resto de `vita-app/` | ARCHIVAR (fase 2) | App Fase 1 sustituida por Godot 4 |
| Taller web (`web/src/pages/taller`, `api/taller`, `lib/taller*.ts`, `lib/ui-layout.ts`) | ACTUALIZAR o ARCHIVAR | Solo compila y despliega la app Fase 1 |
| `tools/hwprobe/` | CONSERVAR | Sin ejecutar todavía; cierra dudas de `docs/14` §9 |
| `tools/env-devpc.fish`, `tools/vita-stack.sh`, `docker/` | CONSERVAR | Parecen viejos o duplicados, pero se usan |

## Plan

1. **Fase 1 (segura):** borrar los 3 ficheros y hacer las 7 actualizaciones. Añadir a la web una
   colección para la carpeta nueva `docs/informes/`.
2. **Fase 2 (decides tú):** sacar de `vita-app/` lo que usa Godot 4 (el script XRCE a `tools/` y
   `rust-modules/` a la raíz) y luego hacer `git mv vita-app archivo/vita-app`.
   Carpeta propuesta: `archivo/` con la ruta original dentro.
3. Al archivar, cambiar `web/Dockerfile` (líneas 29 y 55), `web/src/content.config.ts` (línea 54)
   y el menú de la web (`Base.astro:21`).

```bash
git grep -n 'vita-app/rust-modules'        # quién depende del crate paraguas
git log -1 --format=%cs -- vita-app/src     # última vez que se tocó
```

## Comprueba que lo has entendido

1. ¿Por qué no se puede hacer `git mv vita-app archivo/` directamente? Nombra dos ficheros de Godot 4
   que se romperían.
2. ¿Qué diferencia hay entre ARCHIVAR y BORRAR, y por qué `web/localhost:4321` va a BORRAR?
3. `tools/vita-doctor.sh` dice que falta el cliente XRCE aunque esté compilado. ¿Qué ruta mira y
   cuál debería mirar?
