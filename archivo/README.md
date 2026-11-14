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
| `godot/godot35/` (app teleop Godot 3.5 + módulo `microros`) | 2026-11-13 | Godot 3.5 descartado por ADR 0008 (rclgd exige Godot 4). Viajó entera con `git mv`, incluidos sus ficheros sin versionar; se borraron `.import/` y `build/` (69 MB regenerables) y se conservan `versiones/` (3 `.vpk` validados en hardware, sin versionar) (ADR 0014) |
| `docs/20-godot35-migracion-historico.md`, `docs/21-godot35-plan-implementacion-historico.md` | 2026-11-13 | Diseño y plan de Godot 3.5; archivados con `godot35/` (ADR 0014) |
| `vita-app/` (app C de la Fase 1: teleop vita2d, mini-rviz vitaGL, CMake) | 2026-11-13 | Histórica desde ADR 0008 §5 (enm. 2026-11-11); ADR 0011 descarta su vitaGL. Antes se extrajeron sus piezas vivas (abajo). Se borraron `build-c/`, `build-rust/` y los `.o` sueltos (regenerables) (ADR 0014) |

**Traslados dentro de `docs/` (no archivados, 2026-11-13, ADR 0014):** `docs/ia/{guion-*,plan-tutorial-*,spec-tutorial-*}.md`
→ `docs/ia/tutorial/`; `docs/ia/revision-kimi/g1-sensores-*-2026-11-13.log` → `docs/ia/medidas/`; las sesiones antiguas
de `docs/06-bitacora-estado.md` → `docs/bitacora/`; la §4 del doc 36 → `docs/36a-catalogo-displays.md`.

**Piezas vivas extraídas de `vita-app/` antes de archivarla (2026-11-13, ADR 0014 §2.2):**

| Antes | Ahora |
|---|---|
| `vita-app/rust-modules/` (crate paraguas `vita_modules_rust`) | `modules/paraguas-rust/` (`git mv`; rutas del `Cargo.toml` `../../modules/X` → `../X`) |
| `vita-app/scripts/build-xrce-client-vita.sh` | `tools/build-xrce-client-vita.sh` (instala en `toolchains/xrce/`) |
| `vita-app/third_party/xrce-vita{,-pic,-host}` y `_build/` (sin versionar) | `toolchains/xrce/` (sin versionar; `mv`, sin recompilar; se borraron los `_build/build-*` porque su `CMakeCache.txt` guardaba la ruta antigua: se regeneran solos) |
| `vita-app/src/netlog.{c,h}` | **copia** en `tools/hwprobe/src/` (el original sigue en `archivo/vita-app/src/`) |

`archivo/godot/godot35/` y `archivo/vita-app/` conservan su posición relativa, así que sus referencias mutuas siguen
valiendo.

### Cómo recompilar la app de la Fase 1

No compila en `archivo/vita-app/`: su CMake usa `../modules`, `third_party/xrce-vita` y `rust-modules/`. Lo más
simple es un árbol aparte en el último commit que la tenía en su sitio:

```bash
git worktree add ../psvita-fase1 30b6585     # o cualquier commit anterior a O2c
cd ../psvita-fase1/vita-app && ./scripts/build-xrce-client-vita.sh
cmake -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake -DVITA_IMPL=c -B build && cmake --build build
```

Alternativa en el árbol actual: `git mv archivo/vita-app vita-app`, `XRCE_PREFIX=…/toolchains/xrce/xrce-vita` (es
variable de caché de CMake: `-DXRCE_PREFIX=$PWD/../toolchains/xrce/xrce-vita`, tras `tools/build-xrce-client-vita.sh`)
y, para `-DVITA_IMPL=rust`, cambiar `RUST_DIR` del `CMakeLists.txt` a `../modules/paraguas-rust`. Sin probar.
