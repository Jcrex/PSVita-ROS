# `archivo/` — material archivado

Lo que ya no se usa pero conviene conservar como historia del proyecto.

**Regla:** cada cosa se guarda con **su ruta original** debajo de `archivo/`
(p. ej. `docs/superpowers/` → `archivo/docs/superpowers/`). Así se sabe de
dónde venía. Las rutas relativas de dentro pueden quedar rotas: es un archivo,
no código vivo.

| Qué | Archivado | Motivo |
|---|---|---|
| `docs/superpowers/` (planes y especificaciones de junio–julio 2026) | 2026-11-01 | Planes ya ejecutados; no tenían colección en la web |

**Pendiente de decisión del usuario** (lote 2b de
`docs/ia/auditoria/README.md`): `vita-app/` (con el taller web) y
`godot/godot35/` (con `docs/20`–`21`). Antes hay que sacar lo que aún usan
otras partes (`vita-app/rust-modules`, el script del cliente XRCE,
`src/netlog.c`) y reescribir sus rutas.
