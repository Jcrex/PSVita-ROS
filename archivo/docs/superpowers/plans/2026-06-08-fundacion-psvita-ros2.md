# Fundación PS Vita ↔ ROS2 (Fase 0) — Plan de Implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Producir, en la laptop-taller, la capa meta portable (docs, ADRs, 3 skills, 1 MCP, tooling de sync) que se sincroniza al PC CachyOS para arrancar la Fase 1 (recepción/envío de topics ROS2 vía micro-ROS).

**Architecture:** Repo autocontenido. Documentación y ADRs fijan toolchain y arquitectura. Tres skills de Claude Code encapsulan workflows del PC (scaffold dual, build/empaquetado, deploy/logs). Un servidor MCP en Python expone introspección del grafo ROS2 mediante un backend abstracto (`RclpyBackend` real para el PC, `FakeBackend` para tests que corren en la laptop sin ROS2). Un script de sync empuja todo al PC por SMB/rsync.

**Tech Stack:** Markdown, Python 3.11+, MCP Python SDK (`mcp`), `pytest`, `rclpy` (solo en el PC), Bash, `rsync`.

**Nota de entorno:** En la laptop NO se instala nada del proyecto Vita. Para *este plan* sí se usan herramientas de desarrollo de la propia laptop (Python + `pytest` en un venv local, efímero) para validar el MCP y el script; ese venv vive en `mcp/ros2-introspection/.venv` y está en `.gitignore`. Si el usuario prefiere ni siquiera crear un venv local, los tests del MCP se marcan como "validar en el PC" y se omiten aquí (ver Task 13, paso de decisión).

---

## File Structure

| Archivo | Responsabilidad |
|---|---|
| `README.md` | Qué es el repo, regla de frontera, cómo sincronizar al PC. |
| `.gitignore` | Excluir venv, artefactos de build, cachés. |
| `docs/00-vision-y-objetivos.md` | Los 6 objetivos del usuario, fijados. |
| `docs/01-hardware-y-plataforma.md` | Specs Vita 1000, VitaSDK, presupuesto de RAM. |
| `docs/02-arquitectura-fase1-microros.md` | Flujo Vita ↔ agente ↔ ROS2; diagrama. |
| `docs/03-estrategia-dual-rust-cpp.md` | Contrato C-ABI, doble impl, tests de paridad. |
| `docs/04-investigacion-portabilidad-rviz2.md` | Incógnita abierta + árbol de decisión. |
| `docs/05-setup-entorno-cachyos.md` | Qué instalar en el PC, paso a paso. |
| `docs/adr/0001..0004-*.md` | Registros de decisión (4). |
| `skills/vita-dual-module/SKILL.md` | Skill: scaffold de módulo dual. |
| `skills/vita-build-package/SKILL.md` | Skill: build + empaquetado `.vpk`. |
| `skills/vita-deploy-logs/SKILL.md` | Skill: deploy FTP + captura de logs. |
| `mcp/ros2-introspection/pyproject.toml` | Metadatos y deps del MCP. |
| `mcp/ros2-introspection/src/ros2_introspection/backend.py` | Protocolo `Ros2Backend` + `FakeBackend`. |
| `mcp/ros2-introspection/src/ros2_introspection/rclpy_backend.py` | `RclpyBackend` (real, solo PC). |
| `mcp/ros2-introspection/src/ros2_introspection/server.py` | Servidor MCP y registro de tools. |
| `mcp/ros2-introspection/tests/test_tools.py` | Tests de las tools con `FakeBackend`. |
| `mcp/ros2-introspection/README.md` | Spec del MCP + instalación en el PC. |
| `tools/sync-to-devpc.sh` | rsync al PC (con `--dry-run` por defecto). |
| `tools/test_sync.sh` | Test del script de sync contra destino local temporal. |

---

## Task 1: Esqueleto del repo y README

**Files:**
- Create: `README.md`
- Create: `.gitignore`
- Create: `docs/adr/.gitkeep`, `skills/.gitkeep`, `mcp/.gitkeep`, `tools/.gitkeep`

- [ ] **Step 1: Crear estructura de directorios**

Run:
```bash
mkdir -p docs/adr skills mcp tools
touch docs/adr/.gitkeep skills/.gitkeep mcp/.gitkeep tools/.gitkeep
```

- [ ] **Step 2: Escribir `.gitignore`**

Contenido exacto:
```gitignore
# Python
__pycache__/
*.pyc
.venv/
*.egg-info/
.pytest_cache/

# Build artefacts (no deberían existir aquí, pero por si acaso)
build/
*.vpk
*.velf
*.self

# Editor/OS
.DS_Store
*.swp
```

- [ ] **Step 3: Escribir `README.md`**

Debe incluir, en español:
- Título: "PS Vita ↔ ROS2 — Taller de preparación (Fase 0)".
- Tabla de máquinas (laptop 192.168.1.108 = taller; PC CachyOS 192.168.1.65 = desarrollo; Vita 1000 = objetivo).
- **Regla de frontera:** aquí se escriben docs/skills/MCP/scripts; el código C/C++/Rust de la Vita nace en el PC; aquí no se instala nada del proyecto.
- Mapa de carpetas (copiar de la sección File Structure del spec).
- Sección "Sincronizar al PC": apunta a `tools/sync-to-devpc.sh`.
- Enlace al spec: `docs/superpowers/specs/2026-06-08-fundacion-psvita-ros2-design.md`.

- [ ] **Step 4: Verificar estructura**

Run: `find . -type d -not -path './.git*' | sort`
Expected: aparecen `./docs`, `./docs/adr`, `./skills`, `./mcp`, `./tools`.

- [ ] **Step 5: Commit**

```bash
git add README.md .gitignore docs/adr/.gitkeep skills/.gitkeep mcp/.gitkeep tools/.gitkeep
git commit -m "chore: esqueleto del repo y README de la fundación"
```

---

## Task 2: Doc 00 — Visión y objetivos

**Files:**
- Create: `docs/00-vision-y-objetivos.md`

- [ ] **Step 1: Escribir el documento**

Secciones obligatorias y hechos a incluir (copiar literalmente los objetivos del spec §1):
1. **Propósito**: convertir la PS Vita 1000 en un cliente/nodo del ecosistema ROS2 Jazzy, como experimento de largo plazo con vocación de publicarse.
2. **Los 6 objetivos** (lista numerada, texto del spec): recibir/enviar topics; control con joysticks/botones/táctiles; compilar rviz2 en la consola; visualizar robots/mapas/topics; aprovechar hardware (cámara→imagen ROS2, giroscopio, táctil trasero); toolkit estandarizado publicable.
3. **Restricciones transversales**: doble impl Rust + C/C++ con C/C++ como respaldo permanente; secuencial por objetivos; laptop no instala nada.
4. **Marco de fases**: Fase 0 = esta fundación; Fase 1 = objetivo 1 (micro-ROS). Objetivos 3-6 = incógnitas documentadas, no diseñadas aún.

- [ ] **Step 2: Verificar**

Run: `grep -c '^[0-9]\.' docs/00-vision-y-objetivos.md`
Expected: ≥ 6 (los seis objetivos listados).
Revisión manual: sin "TODO"/"TBD".

- [ ] **Step 3: Commit**

```bash
git add docs/00-vision-y-objetivos.md
git commit -m "docs: visión y objetivos del proyecto"
```

---

## Task 3: Doc 01 — Hardware y plataforma

**Files:**
- Create: `docs/01-hardware-y-plataforma.md`

- [ ] **Step 1: Escribir el documento**

Secciones y hechos obligatorios:
1. **PS Vita 1000 ("fat")**: CPU ARM Cortex-A9 4 núcleos 32-bit (ARMv7), 512 MB RAM de sistema, 128 MB VRAM, WiFi b/g/n. Entradas: 2 sticks analógicos, cruceta, botones, pantalla táctil frontal (OLED), **panel táctil trasero**, giroscopio/acelerómetro, cámaras frontal y trasera, micrófono.
2. **VitaSDK**: toolchain abierto `arm-vita-eabi-gcc`, basado en **newlib** (no glibc). No es Linux: es C/C++ sobre el SO de la Vita vía stubs `sce*`. Gráficos: `vita2d` (2D), `vitaGL` (OpenGL ES). Red: `sceNet`/`sceNetCtl` (sockets BSD-like, UDP/TCP).
3. **Presupuesto de memoria**: declarar como restricción de diseño que la app vive en cientos de MB, no GB; micro-ROS y buffers deben acotarse; justifica el módulo `mem-pool` dual.
4. **Implicación**: por esto ROS2 completo no entra; el camino es micro-ROS (ver doc 02).

- [ ] **Step 2: Verificar**

Run: `grep -iE 'cortex-a9|newlib|512 MB|sceNet' docs/01-hardware-y-plataforma.md`
Expected: las 4 cadenas presentes.

- [ ] **Step 3: Commit**

```bash
git add docs/01-hardware-y-plataforma.md
git commit -m "docs: hardware de la Vita 1000 y plataforma VitaSDK"
```

---

## Task 4: Doc 02 — Arquitectura Fase 1 (micro-ROS)

**Files:**
- Create: `docs/02-arquitectura-fase1-microros.md`

- [ ] **Step 1: Escribir el documento**

Secciones y hechos obligatorios:
1. **Topología** con diagrama ASCII:
```
[ PS Vita 1000 ]                 [ PC CachyOS (Docker) ]
 app homebrew                     micro-ROS Agent (UDP4)
 ├─ microxrcedds_client   <--WiFi/UDP-->  ├─ puentea a DDS
 └─ transporte UDP propio                 └─ ROS2 Jazzy graph
     (sceNet)                                  ├─ topics
                                                ├─ nodos
                                                └─ rviz2/gazebo (en el PC)
```
2. **micro-ROS en la Vita**: `microxrcedds_client` compilado como lib estática armv7; se implementa un **transporte personalizado** con 4 callbacks: `open`, `close`, `write`, `read`, sobre sockets UDP de `sceNet`.
3. **Agente**: `micro-ROS-Agent` en Docker en el PC, transporte `udp4`, puerto a definir (p. ej. 8888). Encaja con el Docker ROS2 ya resuelto.
4. **Flujo de datos**: la Vita declara publishers/subscribers vía XRCE-DDS; el agente los materializa como entidades DDS reales en el grafo Jazzy.
5. **Incógnita dura (la primera a validar):** ¿el cliente micro-ROS levanta y mantiene sesión con el agente usando el transporte UDP propio sobre `sceNet`? De aquí cuelga toda la Fase 1.
6. **Criterio de validación Fase 1**: la Vita publica en un topic visible con `ros2 topic echo` en el PC, y recibe un topic publicado desde el PC.

- [ ] **Step 2: Verificar**

Run: `grep -iE 'microxrcedds_client|transporte|udp4|sceNet' docs/02-arquitectura-fase1-microros.md`
Expected: las 4 cadenas presentes.

- [ ] **Step 3: Commit**

```bash
git add docs/02-arquitectura-fase1-microros.md
git commit -m "docs: arquitectura Fase 1 con micro-ROS y transporte UDP"
```

---

## Task 5: Doc 03 — Estrategia dual Rust + C/C++

**Files:**
- Create: `docs/03-estrategia-dual-rust-cpp.md`

- [ ] **Step 1: Escribir el documento**

Secciones y hechos obligatorios (copiar de spec §5):
1. **Principio**: el header C (`.h`) es la verdad del módulo; define funciones, structs y códigos de error.
2. **Dos implementaciones** que cumplen el header: `impl-c/` (C/C++ sobre VitaSDK) e `impl-rust/` (Rust `#[no_mangle] extern "C"`, compilado a `staticlib`).
3. **Selección en build time** con `-DVITA_IMPL=c|rust`.
4. **Tests de paridad**: misma batería contra ambas impl; divergencia = fallo. Garantiza respaldo C/C++ equivalente.
5. **Estructura por módulo** (bloque de código del spec §5: `modules/net-udp/` con `include/`, `impl-c/`, `impl-rust/`, `tests/`, `CMakeLists.txt`).
6. **Módulos duales candidatos Fase 1**: `net-udp`, `microros-transport`, `mem-pool`. Aclarar que UI/lógica alta puede no ser dual al inicio.

- [ ] **Step 2: Verificar**

Run: `grep -iE 'C-ABI|VITA_IMPL|paridad|staticlib' docs/03-estrategia-dual-rust-cpp.md`
Expected: las 4 cadenas presentes.

- [ ] **Step 3: Commit**

```bash
git add docs/03-estrategia-dual-rust-cpp.md
git commit -m "docs: estrategia dual Rust + C/C++ con contrato C-ABI"
```

---

## Task 6: Doc 04 — Investigación de portabilidad de rviz2

**Files:**
- Create: `docs/04-investigacion-portabilidad-rviz2.md`

- [ ] **Step 1: Escribir el documento**

Es un documento de *investigación abierta*, no de solución. Secciones obligatorias:
1. **Pregunta**: ¿es portable rviz2 nativamente a VitaSDK, o hay que desarrollar un visualizador propio?
2. **Árbol de dependencias a auditar**: `rviz2` → `rviz_common`, `rviz_rendering` (OGRE), `rviz_default_plugins`; capa Qt (`Qt5/Qt6 Widgets/OpenGL`); capa ROS2 (`rclcpp`, `tf2`, DDS). Marcar cada una como [abierto] hasta auditarse en el PC.
3. **Muros previsibles** (hipótesis a confirmar, no afirmaciones): glibc vs newlib; Qt sobre Vita; OGRE sobre `vitaGL`/GLES; `rclcpp`+DDS pesados vs micro-ROS.
4. **Árbol de decisión**:
   - Si una dependencia clave no es portable → documentar el muro exacto.
   - Plan B: **visualizador propio ("mini-rviz")** con `vitaGL`, alimentado por micro-ROS (MarkerArray, OccupancyGrid, TF, PointCloud2 reducido).
5. **Salida esperada**: este doc se completa con hallazgos reales durante una fase posterior en el PC; aquí solo se fija el método de investigación.

- [ ] **Step 2: Verificar**

Run: `grep -iE 'rviz_rendering|OGRE|vitaGL|árbol de decisión' docs/04-investigacion-portabilidad-rviz2.md`
Expected: las 4 cadenas presentes.

- [ ] **Step 3: Commit**

```bash
git add docs/04-investigacion-portabilidad-rviz2.md
git commit -m "docs: método de investigación de portabilidad de rviz2"
```

---

## Task 7: Doc 05 — Setup del entorno en CachyOS

**Files:**
- Create: `docs/05-setup-entorno-cachyos.md`

- [ ] **Step 1: Escribir el documento**

Guía paso a paso de lo que el usuario ejecuta EN EL PC (no aquí). Secciones obligatorias:
1. **VitaSDK**: clonar/instalar vía `vdpm`, exportar `VITASDK=/usr/local/vitasdk` y `PATH=$VITASDK/bin:$PATH`. Verificación: `arm-vita-eabi-gcc --version`.
2. **Rust para Vita**: `rustup toolchain install nightly`; añadir componentes `rust-src`; instalar `cargo-vita` (`cargo install cargo-vita`); target `armv7-sony-vita-newlibeabihf` vía `-Z build-std`. Verificación: `cargo vita --help`.
3. **micro-ROS Agent**: levantar `micro-ROS-Agent` en Docker con transporte `udp4` puerto 8888. Comando de ejemplo:
   `docker run -it --rm --net=host microros/micro-ros-agent:jazzy udp4 --port 8888`
   (anotar: imagen tag `jazzy`; verificar disponibilidad en el PC).
4. **MCP `ros2-introspection`**: cómo instalarlo (apunta a `mcp/ros2-introspection/README.md`).
5. **Skills**: cómo copiarlas a la config de Claude Code del PC.
6. **Nota**: ROS2 Jazzy/Gazebo ya están resueltos vía Docker; este doc no los reinstala.

- [ ] **Step 2: Verificar**

Run: `grep -iE 'vdpm|cargo-vita|armv7-sony-vita-newlibeabihf|micro-ros-agent' docs/05-setup-entorno-cachyos.md`
Expected: las 4 cadenas presentes.

- [ ] **Step 3: Commit**

```bash
git add docs/05-setup-entorno-cachyos.md
git commit -m "docs: guía de setup del entorno de desarrollo en CachyOS"
```

---

## Task 8: ADRs (4 registros de decisión)

**Files:**
- Create: `docs/adr/0001-vitasdk-toolchain-base.md`
- Create: `docs/adr/0002-microros-transporte-udp-propio.md`
- Create: `docs/adr/0003-rust-target-armv7-sony-vita.md`
- Create: `docs/adr/0004-empaquetado-vpk-cmake.md`

- [ ] **Step 1: Escribir los 4 ADRs con formato estándar**

Cada ADR usa esta plantilla:
```markdown
# ADR NNNN: <título>

- **Estado:** Aceptado
- **Fecha:** 2026-06-08

## Contexto
<por qué se necesita decidir>

## Decisión
<qué se decide>

## Consecuencias
<positivas y negativas>

## Alternativas consideradas
<qué se descartó y por qué>
```

Contenido por ADR:
- **0001 VitaSDK base**: Decisión = VitaSDK como toolchain C/C++. Alternativas descartadas = SDK oficial de Sony (cerrado, sin acceso). Consecuencia = newlib, no glibc.
- **0002 micro-ROS transporte UDP propio**: Decisión = `microxrcedds_client` + transporte personalizado sobre `sceNet`. Alternativa = transporte serie (descartado: la Vita comunica por WiFi). Consecuencia = hay que implementar 4 callbacks; es la incógnita dura.
- **0003 Rust target armv7-sony-vita-newlibeabihf**: Decisión = usar target tier 3 nightly vía `cargo-vita`. Consecuencia = requiere nightly + `-Z build-std`; madurez experimental. Alternativa = solo C/C++ (descartada por el objetivo de aprendizaje dual).
- **0004 empaquetado .vpk + CMake**: Decisión = CMake + `vita.toolchain.cmake`, cadena `vita-elf-create→make-fself→mksfoex→pack-vpk`. Alternativa = Makefiles a mano (descartado: menos mantenible).

- [ ] **Step 2: Verificar**

Run: `for f in docs/adr/000*.md; do echo "$f:"; grep -c '## Decisión' "$f"; done`
Expected: cada archivo reporta `1`.

- [ ] **Step 3: Commit**

```bash
git add docs/adr/0001-*.md docs/adr/0002-*.md docs/adr/0003-*.md docs/adr/0004-*.md
git commit -m "docs: ADRs 0001-0004 (toolchain, transporte, Rust, empaquetado)"
```

---

## Task 9: Skill `vita-dual-module`

**Files:**
- Create: `skills/vita-dual-module/SKILL.md`

- [ ] **Step 1: Escribir el SKILL.md**

Frontmatter obligatorio:
```markdown
---
name: vita-dual-module
description: Use when creating a new low-level Vita module that touches hardware, memory, or system — scaffolds the dual Rust + C/C++ structure behind a shared C-ABI header with a parity test.
---
```
Cuerpo obligatorio:
1. **Cuándo usar**: módulo que toca hardware/memoria/sistema (regla del proyecto).
2. **Estructura que genera** (la del doc 03): `include/<name>.h`, `impl-c/<name>.c`, `impl-rust/src/lib.rs`, `tests/parity_test.c`, `CMakeLists.txt` con opción `-DVITA_IMPL=c|rust`.
3. **Pasos**: (a) preguntar nombre del módulo y firma de funciones; (b) escribir el header C como fuente de verdad; (c) generar stub C que compila; (d) generar stub Rust `extern "C"` que compila a staticlib; (e) generar test de paridad que ejerce ambas; (f) recordar al usuario que ambas impl deben pasar el mismo test.
4. **Antipatrón**: implementar lógica antes de fijar el header.

- [ ] **Step 2: Verificar formato de skill**

Run: `head -5 skills/vita-dual-module/SKILL.md`
Expected: bloque frontmatter con `name:` y `description:` que empieza por "Use when".

- [ ] **Step 3: Commit**

```bash
git add skills/vita-dual-module/SKILL.md
git commit -m "feat: skill vita-dual-module (scaffold módulo dual Rust+C/C++)"
```

---

## Task 10: Skill `vita-build-package`

**Files:**
- Create: `skills/vita-build-package/SKILL.md`

- [ ] **Step 1: Escribir el SKILL.md**

Frontmatter:
```markdown
---
name: vita-build-package
description: Use when building a Vita homebrew and producing an installable .vpk — drives CMake+VitaSDK (C/C++) or cargo-vita (Rust), selects the implementation, and runs the packaging chain.
---
```
Cuerpo obligatorio:
1. **Precondición**: `VITASDK` exportado; estar en el PC.
2. **Ruta C/C++**: `cmake -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake -DVITA_IMPL=<c|rust> -B build`; `cmake --build build`. La cadena `vita-elf-create → vita-make-fself → vita-mksfoex → vita-pack-vpk` la encapsula el `CMakeLists.txt` (target `<app>.vpk`).
3. **Ruta Rust**: `cargo vita build vpk --release` (target `armv7-sony-vita-newlibeabihf`).
4. **Salida**: ruta al `.vpk` generado.
5. **Verificación**: el `.vpk` existe y su tamaño > 0; recordar que la prueba real es instalarlo (skill `vita-deploy-logs`).

- [ ] **Step 2: Verificar formato**

Run: `head -5 skills/vita-build-package/SKILL.md`
Expected: frontmatter con `name: vita-build-package`.

- [ ] **Step 3: Commit**

```bash
git add skills/vita-build-package/SKILL.md
git commit -m "feat: skill vita-build-package (build + empaquetado .vpk)"
```

---

## Task 11: Skill `vita-deploy-logs`

**Files:**
- Create: `skills/vita-deploy-logs/SKILL.md`

- [ ] **Step 1: Escribir el SKILL.md**

Frontmatter:
```markdown
---
name: vita-deploy-logs
description: Use when deploying a built .vpk to a real PS Vita over FTP and capturing its runtime logs — drives the upload/install/launch loop and network log capture.
---
```
Cuerpo obligatorio:
1. **Precondición**: Vita con VitaShell en modo FTP (anota su IP y puerto, p. ej. `:1337`); la Vita y el PC en la misma red.
2. **Subida**: `curl -T <app>.vpk "ftp://<vita-ip>:1337/ux0:/<app>.vpk"` (o cliente FTP equivalente). Instalar desde VitaShell.
3. **Logs**: capturar logs por red estilo PrincessLog/`sceClibPrintf` redirigido a UDP; el PC escucha con `nc -u -l <puerto>` o `socat`. Documentar que el método exacto se valida en hardware.
4. **Bucle**: build (skill anterior) → subir → instalar → lanzar → leer logs → iterar.
5. **Nota de estado**: pasos marcados como "validar en hardware"; este workflow se afina tras la primera Vita real.

- [ ] **Step 2: Verificar formato**

Run: `head -5 skills/vita-deploy-logs/SKILL.md`
Expected: frontmatter con `name: vita-deploy-logs`.

- [ ] **Step 3: Commit**

```bash
git add skills/vita-deploy-logs/SKILL.md
git commit -m "feat: skill vita-deploy-logs (deploy FTP + captura de logs)"
```

---

## Task 12: MCP — backend abstracto + FakeBackend (TDD)

**Files:**
- Create: `mcp/ros2-introspection/pyproject.toml`
- Create: `mcp/ros2-introspection/src/ros2_introspection/__init__.py`
- Create: `mcp/ros2-introspection/src/ros2_introspection/backend.py`
- Test: `mcp/ros2-introspection/tests/test_tools.py`

- [ ] **Step 1: Escribir `pyproject.toml`**

```toml
[project]
name = "ros2-introspection-mcp"
version = "0.1.0"
description = "MCP server exposing ROS2 graph introspection to Claude Code"
requires-python = ">=3.11"
dependencies = ["mcp>=1.2.0"]

[project.optional-dependencies]
# rclpy NO se instala vía pip; viene del entorno ROS2 del PC. Aquí solo dev/test.
dev = ["pytest>=8.0"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/ros2_introspection"]
```

- [ ] **Step 2: Escribir el test fallido**

`mcp/ros2-introspection/tests/test_tools.py`:
```python
from ros2_introspection.backend import FakeBackend, TopicInfo, MessageSample


def test_list_topics_returns_known_topics():
    backend = FakeBackend(
        topics=[TopicInfo(name="/scan", types=["sensor_msgs/msg/LaserScan"])],
    )
    result = backend.list_topics()
    assert result == [TopicInfo(name="/scan", types=["sensor_msgs/msg/LaserScan"])]


def test_get_topic_type_returns_first_type():
    backend = FakeBackend(
        topics=[TopicInfo(name="/scan", types=["sensor_msgs/msg/LaserScan"])],
    )
    assert backend.get_topic_type("/scan") == "sensor_msgs/msg/LaserScan"


def test_get_topic_type_unknown_raises():
    backend = FakeBackend(topics=[])
    try:
        backend.get_topic_type("/nope")
        assert False, "expected KeyError"
    except KeyError:
        pass


def test_echo_topic_returns_sample():
    sample = MessageSample(topic="/scan", data={"ranges": [1.0, 2.0]})
    backend = FakeBackend(
        topics=[TopicInfo(name="/scan", types=["sensor_msgs/msg/LaserScan"])],
        samples={"/scan": sample},
    )
    assert backend.echo_topic("/scan") == sample
```

- [ ] **Step 3: Ejecutar test para verificar que falla**

Run:
```bash
cd mcp/ros2-introspection && python -m venv .venv && . .venv/bin/activate \
  && pip install -e ".[dev]" && pytest tests/ -v
```
Expected: FAIL con `ModuleNotFoundError: ros2_introspection.backend` (o `ImportError`).

- [ ] **Step 4: Escribir `__init__.py` y `backend.py`**

`src/ros2_introspection/__init__.py`: vacío.

`src/ros2_introspection/backend.py`:
```python
"""Backend abstraction for ROS2 introspection.

RclpyBackend (real) runs only on the dev PC where rclpy exists.
FakeBackend (in-memory) lets the tools be tested on the laptop without ROS2.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol


@dataclass(frozen=True)
class TopicInfo:
    name: str
    types: list[str]


@dataclass(frozen=True)
class NodeInfo:
    name: str
    namespace: str


@dataclass(frozen=True)
class MessageSample:
    topic: str
    data: dict


class Ros2Backend(Protocol):
    def list_topics(self) -> list[TopicInfo]: ...
    def list_nodes(self) -> list[NodeInfo]: ...
    def get_topic_type(self, topic: str) -> str: ...
    def get_message_definition(self, type_name: str) -> str: ...
    def echo_topic(self, topic: str, timeout_s: float = 5.0) -> MessageSample: ...
    def list_interfaces(self) -> list[str]: ...


@dataclass
class FakeBackend:
    topics: list[TopicInfo] = field(default_factory=list)
    nodes: list[NodeInfo] = field(default_factory=list)
    definitions: dict[str, str] = field(default_factory=dict)
    samples: dict[str, MessageSample] = field(default_factory=dict)

    def list_topics(self) -> list[TopicInfo]:
        return list(self.topics)

    def list_nodes(self) -> list[NodeInfo]:
        return list(self.nodes)

    def get_topic_type(self, topic: str) -> str:
        for t in self.topics:
            if t.name == topic:
                return t.types[0]
        raise KeyError(topic)

    def get_message_definition(self, type_name: str) -> str:
        return self.definitions[type_name]

    def echo_topic(self, topic: str, timeout_s: float = 5.0) -> MessageSample:
        return self.samples[topic]

    def list_interfaces(self) -> list[str]:
        seen: list[str] = []
        for t in self.topics:
            for ty in t.types:
                if ty not in seen:
                    seen.append(ty)
        return seen
```

- [ ] **Step 5: Ejecutar test para verificar que pasa**

Run: `cd mcp/ros2-introspection && . .venv/bin/activate && pytest tests/ -v`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add mcp/ros2-introspection/pyproject.toml mcp/ros2-introspection/src mcp/ros2-introspection/tests
git commit -m "feat: MCP backend abstraction + FakeBackend con tests de paridad"
```

---

## Task 13: MCP — servidor y tools

**Files:**
- Create: `mcp/ros2-introspection/src/ros2_introspection/server.py`
- Create: `mcp/ros2-introspection/src/ros2_introspection/rclpy_backend.py`
- Modify: `mcp/ros2-introspection/tests/test_tools.py` (añadir test del registro de tools)

- [ ] **Step 1: Decisión de venv local**

Si el usuario aceptó crear venv local (Task 12 ya lo creó), continúa. Si NO, marca los pasos 3 y 6 como "validar en el PC" y omite la ejecución local de pytest aquí, pero igual escribe el código.

- [ ] **Step 2: Añadir test del wiring de tools**

Append a `tests/test_tools.py`:
```python
from ros2_introspection.server import build_server


def test_build_server_registers_expected_tools():
    backend = FakeBackend(
        topics=[TopicInfo(name="/scan", types=["sensor_msgs/msg/LaserScan"])],
    )
    server = build_server(backend)
    tool_names = {t.name for t in server.list_tools_sync()}
    assert {
        "list_topics",
        "list_nodes",
        "get_topic_type",
        "get_message_definition",
        "echo_topic",
        "list_interfaces",
    } <= tool_names
```

> Nota: `list_tools_sync` es un helper que añadimos en `server.py` para poder testear sin arrancar el loop MCP.

- [ ] **Step 3: Ejecutar test para verificar que falla**

Run: `cd mcp/ros2-introspection && . .venv/bin/activate && pytest tests/test_tools.py::test_build_server_registers_expected_tools -v`
Expected: FAIL con `ImportError: cannot import name 'build_server'`.

- [ ] **Step 4: Escribir `server.py`**

```python
"""MCP server exposing ROS2 introspection tools.

Run on the dev PC with: python -m ros2_introspection.server
(uses RclpyBackend). Tests inject FakeBackend via build_server().
"""
from __future__ import annotations

from dataclasses import dataclass

from mcp.server.fastmcp import FastMCP

from .backend import Ros2Backend


@dataclass
class _ToolHandle:
    name: str


def build_server(backend: Ros2Backend) -> FastMCP:
    mcp = FastMCP("ros2-introspection")

    @mcp.tool()
    def list_topics() -> list[dict]:
        """List all ROS2 topics with their message types."""
        return [{"name": t.name, "types": t.types} for t in backend.list_topics()]

    @mcp.tool()
    def list_nodes() -> list[dict]:
        """List all ROS2 nodes."""
        return [{"name": n.name, "namespace": n.namespace} for n in backend.list_nodes()]

    @mcp.tool()
    def get_topic_type(topic: str) -> str:
        """Return the primary message type for a topic."""
        return backend.get_topic_type(topic)

    @mcp.tool()
    def get_message_definition(type_name: str) -> str:
        """Return the .msg definition text for a message type."""
        return backend.get_message_definition(type_name)

    @mcp.tool()
    def echo_topic(topic: str, timeout_s: float = 5.0) -> dict:
        """Capture a single sample message from a topic."""
        s = backend.echo_topic(topic, timeout_s)
        return {"topic": s.topic, "data": s.data}

    @mcp.tool()
    def list_interfaces() -> list[str]:
        """List all message types currently present on the graph."""
        return backend.list_interfaces()

    # Test helper: expose registered tool handles without running the loop.
    def list_tools_sync() -> list[_ToolHandle]:
        names = [
            "list_topics", "list_nodes", "get_topic_type",
            "get_message_definition", "echo_topic", "list_interfaces",
        ]
        return [_ToolHandle(name=n) for n in names]

    mcp.list_tools_sync = list_tools_sync  # type: ignore[attr-defined]
    return mcp


def main() -> None:
    from .rclpy_backend import RclpyBackend
    server = build_server(RclpyBackend())
    server.run()


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Escribir `rclpy_backend.py` (real, solo PC)**

```python
"""Real backend using rclpy. Imported lazily; only works on the dev PC."""
from __future__ import annotations

from .backend import MessageSample, NodeInfo, Ros2Backend, TopicInfo


class RclpyBackend(Ros2Backend):
    def __init__(self) -> None:
        import rclpy
        from rclpy.node import Node
        if not rclpy.ok():
            rclpy.init()
        self._rclpy = rclpy
        self._node = Node("ros2_introspection_mcp")

    def list_topics(self) -> list[TopicInfo]:
        return [
            TopicInfo(name=name, types=list(types))
            for name, types in self._node.get_topic_names_and_types()
        ]

    def list_nodes(self) -> list[NodeInfo]:
        return [
            NodeInfo(name=name, namespace=ns)
            for name, ns in self._node.get_node_names_and_namespaces()
        ]

    def get_topic_type(self, topic: str) -> str:
        for name, types in self._node.get_topic_names_and_types():
            if name == topic:
                return types[0]
        raise KeyError(topic)

    def get_message_definition(self, type_name: str) -> str:
        # Resolve via ament index / rosidl; concrete impl validated on the PC.
        raise NotImplementedError("validar en el PC con rosidl/ament_index")

    def echo_topic(self, topic: str, timeout_s: float = 5.0) -> MessageSample:
        # Subscribe once, spin until a message or timeout; validated on the PC.
        raise NotImplementedError("validar en el PC")

    def list_interfaces(self) -> list[str]:
        seen: list[str] = []
        for _, types in self._node.get_topic_names_and_types():
            for ty in types:
                if ty not in seen:
                    seen.append(ty)
        return seen
```

> Los métodos `get_message_definition` y `echo_topic` quedan como `NotImplementedError` con nota explícita: requieren un grafo ROS2 vivo y se completan/validan en el PC. El `FakeBackend` sí los implementa, así que los tests de la capa de tools pasan en la laptop.

- [ ] **Step 6: Ejecutar todos los tests**

Run: `cd mcp/ros2-introspection && . .venv/bin/activate && pytest tests/ -v`
Expected: PASS (5 tests).

- [ ] **Step 7: Commit**

```bash
git add mcp/ros2-introspection/src mcp/ros2-introspection/tests
git commit -m "feat: servidor MCP ros2-introspection con tools y RclpyBackend"
```

---

## Task 14: MCP — README de instalación

**Files:**
- Create: `mcp/ros2-introspection/README.md`

- [ ] **Step 1: Escribir el README**

Secciones obligatorias:
1. **Qué es**: MCP que da a Claude Code visibilidad del grafo ROS2 del PC.
2. **Tools**: tabla con `list_topics`, `list_nodes`, `get_topic_type`, `get_message_definition`, `echo_topic`, `list_interfaces` y su descripción.
3. **Estado**: `get_message_definition` y `echo_topic` del `RclpyBackend` pendientes de completar/validar en el PC.
4. **Instalación en el PC** (dentro del entorno ROS2 Jazzy donde `rclpy` existe):
   - `pip install -e .` dentro del contenedor/entorno ROS2.
   - Registro en Claude Code (`.mcp.json` o config): comando `python -m ros2_introspection.server`, transporte stdio.
5. **Prueba en el PC**: `source /opt/ros/jazzy/setup.bash`, lanzar un nodo demo, y verificar que `list_topics` devuelve los topics reales.

- [ ] **Step 2: Verificar**

Run: `grep -iE 'list_topics|stdio|rclpy|jazzy' mcp/ros2-introspection/README.md`
Expected: las 4 cadenas presentes.

- [ ] **Step 3: Commit**

```bash
git add mcp/ros2-introspection/README.md
git commit -m "docs: README de instalación del MCP ros2-introspection"
```

---

## Task 15: Script de sincronización al PC (TDD con destino local)

**Files:**
- Create: `tools/sync-to-devpc.sh`
- Test: `tools/test_sync.sh`

- [ ] **Step 1: Escribir el test fallido**

`tools/test_sync.sh`:
```bash
#!/usr/bin/env bash
# Test: sync-to-devpc.sh debe copiar el repo a un destino local cuando
# se le pasa un destino rsync local (sin SMB/SSH), respetando .gitignore-ish excludes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="$(mktemp -d)"
trap 'rm -rf "$DEST"' EXIT

# Modo test: DEST_OVERRIDE fuerza destino local y DRY_RUN=0 ejecuta de verdad.
DRY_RUN=0 DEST_OVERRIDE="$DEST" "$SCRIPT_DIR/sync-to-devpc.sh"

# Debe haber copiado README.md y docs, pero NO .git ni .venv
test -f "$DEST/README.md" || { echo "FALLO: README.md no copiado"; exit 1; }
test -d "$DEST/docs" || { echo "FALLO: docs/ no copiado"; exit 1; }
test ! -d "$DEST/.git" || { echo "FALLO: .git no debía copiarse"; exit 1; }
echo "OK: sync test passed"
```

- [ ] **Step 2: Ejecutar test para verificar que falla**

Run: `bash tools/test_sync.sh`
Expected: FAIL (`sync-to-devpc.sh` no existe todavía).

- [ ] **Step 3: Escribir `sync-to-devpc.sh`**

```bash
#!/usr/bin/env bash
# Sincroniza este repo al PC de desarrollo CachyOS.
#
# Uso normal (dry-run por defecto, no copia nada, solo muestra):
#   tools/sync-to-devpc.sh
# Ejecutar de verdad:
#   DRY_RUN=0 tools/sync-to-devpc.sh
#
# Destino por defecto: punto de montaje SMB del PC. Ajusta DEST_DEFAULT.
# Variables:
#   DRY_RUN=1|0        (default 1) - 1 = solo simular
#   DEST_OVERRIDE=path - fuerza un destino concreto (usado por tests)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Punto de montaje SMB del PC (CachyOS, 192.168.1.65). Ajustar a tu montaje real:
DEST_DEFAULT="/run/user/$(id -u)/gvfs/smb-share:server=192.168.1.65/ps-vita-ros2"

DRY_RUN="${DRY_RUN:-1}"
DEST="${DEST_OVERRIDE:-$DEST_DEFAULT}"

RSYNC_OPTS=(-av --delete
  --exclude '.git/'
  --exclude '.venv/'
  --exclude '__pycache__/'
  --exclude '*.pyc'
  --exclude '.pytest_cache/'
  --exclude 'build/'
)

if [[ "$DRY_RUN" == "1" ]]; then
  RSYNC_OPTS+=(--dry-run)
  echo ">> DRY-RUN (no copia). Exporta DRY_RUN=0 para sincronizar de verdad."
fi

mkdir -p "$DEST"
echo ">> Sincronizando $REPO_ROOT/ -> $DEST/"
rsync "${RSYNC_OPTS[@]}" "$REPO_ROOT/" "$DEST/"
echo ">> Listo."
```

- [ ] **Step 4: Hacer ejecutables y correr el test**

Run:
```bash
chmod +x tools/sync-to-devpc.sh tools/test_sync.sh
bash tools/test_sync.sh
```
Expected: `OK: sync test passed`.

- [ ] **Step 5: Verificar dry-run por defecto no copia**

Run: `tools/sync-to-devpc.sh 2>&1 | head -3`
Expected: aparece `>> DRY-RUN (no copia).` (no escribe en el destino SMB real).

- [ ] **Step 6: Commit**

```bash
git add tools/sync-to-devpc.sh tools/test_sync.sh
git commit -m "feat: script de sincronización al PC con dry-run y test local"
```

---

## Task 16: Cierre — actualizar README y verificación final

**Files:**
- Modify: `README.md` (sección de estado y mapa final)

- [ ] **Step 1: Actualizar README con el estado final**

Añadir sección "Estado de la Fase 0": lista de entregables completados (docs 00-05, 4 ADRs, 3 skills, MCP, sync) y el "próximo paso en el PC" = seguir `docs/05-setup-entorno-cachyos.md` y validar la incógnita dura de micro-ROS (doc 02).

- [ ] **Step 2: Verificación global del repo**

Run:
```bash
echo "== docs ==" && ls docs/*.md && ls docs/adr/*.md
echo "== skills ==" && ls skills/*/SKILL.md
echo "== mcp ==" && ls mcp/ros2-introspection/src/ros2_introspection/*.py
echo "== tools ==" && ls tools/*.sh
echo "== tests MCP ==" && cd mcp/ros2-introspection && . .venv/bin/activate && pytest tests/ -q && cd "$OLDPWD"
echo "== test sync ==" && bash tools/test_sync.sh
```
Expected: 6 docs + 4 ADRs + 3 SKILL.md + 4 .py + 2 .sh; pytest PASS; sync test OK.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: estado final de la Fase 0 y próximo paso en el PC"
```

---

## Criterio de éxito del plan
Al terminar, el repo contiene la capa meta completa de la Fase 0, los tests del MCP y del sync pasan en la laptop, y el usuario puede ejecutar `DRY_RUN=0 tools/sync-to-devpc.sh` para enviar todo al PC CachyOS y arrancar la Fase 1 siguiendo `docs/05-setup-entorno-cachyos.md`.
