# `archivo/` — material archivado

Lo que ya no se usa pero conviene conservar como historia del proyecto.

**Regla:** cada cosa se guarda con **su ruta original** debajo de `archivo/`
(p. ej. `docs/superpowers/` → `archivo/docs/superpowers/`). Así se sabe de
dónde venía. Las rutas relativas de dentro pueden quedar rotas: es un archivo,
no código vivo.

| Qué | Archivado | Motivo |
|---|---|---|
| `docs/superpowers/` (planes y especificaciones de junio–julio 2026) | 2026-11-01 | Planes ya ejecutados; no tenían colección en la web |
| `auditoria/log-*.txt` (3 logs de las compilaciones de prueba de rviz2) | 2026-11-13 | Evidencia del ADR 0006 y del doc 04. Copiados textualmente (con las rutas locales de su fecha); los clones (`ogre`, `vitaGL`, `rcutils`, sin versionar) pasaron a `toolchains/auditoria-rviz2/` (ADR 0014) |
| `docs/10-plan-objetivos-3-4.md` | 2026-11-13 | Superado por ADR 0008 §5 (enm. 2026-11-11) y ADR 0013 / doc 36 (ADR 0014) |
| `docs/11-diseno-mini-rviz.md` | 2026-11-13 | Superado por ADR 0013: el visor se hace en Godot, no con vitaGL (ADR 0014) |
| `docs/16-paginas-pendientes-de-leer.md` | 2026-11-13 | Superado: lista de lectura para Godot 3.5; rclgd ya leído en doc 17 (ADR 0014) |
| `docs/19-plan-multiagente-migracion-godot4.md` | 2026-11-13 | Plan ejecutado (G1–G7 verdes); el método vigente es `docs/ia/workshops/README.md` (ADR 0014) |
| `docs/ia/guion-guia-tutorial-original.md` | 2026-11-13 | Superado por `docs/tutorial/00` + `07` (ADR 0014) |
| `docs/ia/prompt-siguiente-sesion.md` | 2026-11-13 | Prompt del 2026-11-13 ya consumido (ADR 0014) |

**Traslados dentro de `docs/` (no archivados, 2026-11-13, ADR 0014):** `docs/ia/{guion-*,plan-tutorial-*,spec-tutorial-*}.md`
→ `docs/ia/tutorial/`; `docs/ia/revision-kimi/g1-sensores-*-2026-11-13.log` → `docs/ia/medidas/`; las sesiones antiguas
de `docs/06-bitacora-estado.md` → `docs/bitacora/`; la §4 del doc 36 → `docs/36a-catalogo-displays.md`.

El lote 2b de la auditoría (`vita-app/`, `godot/godot35/` y `docs/20`–`21`) lo decide el ADR 0014 y lo ejecuta el
paso O2c de la Fase O (`docs/ia/organizacion/decision-fable.md` §2 y §7).
