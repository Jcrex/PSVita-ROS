---
title: "Auditoría 01b — limpieza de módulos, Godot y docs"
description: "Qué sobra, qué está viejo y qué se queda en modules/, godot/ y docs/."
fecha: 2026-11-01
---

# Auditoría 01b — limpieza de módulos, Godot y docs

Solo lectura: no se ha movido nada. Detalle con `archivo:línea` en
`docs/ia/auditoria/01b-limpieza-modulos-godot-docs.md`.

## Resumen

- **Los 8 módulos se quedan.** `msg-cdr` y `tf-tree` aún no los usa nadie, pero están en los tests y
  en el crate Rust, y tienen destino (mini-rviz, TF).
- **G4 y G5 se quedan** como pruebas de regresión: G4 prueba el motor sin red; G5, la red mínima.
- **Godot 3.5** (`godot/godot35/`) se puede archivar al final, pero obliga a cambiar ~12 rutas.

## Candidatos

| Ruta | Acción | Motivo |
|---|---|---|
| `docs/superpowers/` | ARCHIVAR | Planes de junio–julio ya cumplidos |
| `docs/superpowers/plans/2026-07-12-tutorial…` | mover a `docs/ia/` | Guion de las lecciones 02–06 (sin escribir) |
| `docs/09-guia-pruebas-stack.md` | ACTUALIZAR + renombrar a `23-` | Número 09 repetido; habla de `rmf_unified`, no de `docker/` |
| `docs/19` §3 y §8 | ACTUALIZAR | Tareas hechas marcadas ⏳; cita `xrce_core.c`, que no existe |
| `docs/adr/0008` línea 3 | ACTUALIZAR | Dice «sin validar»; G1–G6 están verdes |
| `docs/10`, `docs/11` línea 3 | ACTUALIZAR | «En curso» desde julio: está en pausa |
| `docs/tutorial/00` | ACTUALIZAR | Lista lecciones 02–06 que no existen |
| `docs/rust/00` líneas 58–62 | ACTUALIZAR | Habla de 3 módulos; son 8 y falta `build-rust-pic.sh` |
| `docs/06` | ACTUALIZAR | Cabecera enorme; el «resumen de 1 minuto» es de junio |
| Comentarios «validar…» en `g4/g5/g6`, `ros2_vita`, READMEs de módulos | ACTUALIZAR | Ya se validó en hardware |
| `godot/g{4,5,6,7}/ros/schema.rsch` | ACTUALIZAR | 4 copias idénticas: anotar cómo se regeneran |
| `godot/godot35/` + `docs/20`, `21` | ARCHIVAR (opcional) | Histórico 3.5 |
| `godot35/imagenes/rover-iberus.jpeg.import`, `godot35/UI/UIIcons_2.zip` | BORRAR | Huérfano y sin uso (confirma el zip) |

## ⚠️ Antes del commit de G7a

`godot/g7-imu/.godot/` **no está ignorado**: añade `.godot/` a `.gitignore` o subirás la caché del
editor. Los `*.gd.uid` sí se suben.

## Carpeta de archivados

`archivo/` en la raíz, con la ruta original (`archivo/docs/superpowers/…`). La web no la lee: hay que
añadir una colección «Archivo» en `web/src/content.config.ts` y `COPY archivo/` en `web/Dockerfile`.
Lo mismo para `docs/informes/`.

## Orden (un commit por paso)

1. Commit de G7a (con `.godot/` ignorado).
2. Web: colecciones `archivo` e `informes`.
3. `git mv docs/superpowers archivo/docs/superpowers` (antes, sacar el plan del tutorial).
4. `git mv docs/09-guia-pruebas-stack.md docs/23-guia-pruebas-stack.md`.
5. Ediciones «ACTUALIZAR».
6. `git rm` de los dos ficheros de godot35.
7. (Opcional) `git mv godot/godot35 archivo/godot/godot35`.

## Comprueba que lo has entendido

1. ¿Por qué conviene guardar `g4-smoke` aunque `g6-hmi` haga mucho más?
2. ¿Qué pasaría en la web si mueves un doc a `archivo/` sin tocar `content.config.ts`?
3. ¿Por qué hay que ignorar `.godot/` y en cambio subir los `*.gd.uid`?
