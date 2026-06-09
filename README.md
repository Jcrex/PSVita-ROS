# PS Vita ↔ ROS2

Convertir una **PS Vita 1000** en un nodo real del ecosistema **ROS2 Jazzy**:
publica y recibe topics vía micro-ROS (XRCE-DDS) sobre WiFi/UDP, con cada
módulo de bajo nivel implementado **dos veces** (Rust y C/C++) tras un mismo
header C. Proyecto experimental de largo plazo con vocación de publicarse.

**Estado:** Fase 0 (fundación) completa · **Fase 1 con todo el código escrito
y verificado en host** — pendiente de cross-compilar en el PC y validar en
hardware. Detalle vivo en [`docs/06-bitacora-estado.md`](docs/06-bitacora-estado.md).

---

## Máquinas

| Rol | Equipo | IP | Función |
|---|---|---|---|
| **Taller** | Laptop (este repo) | 192.168.1.108 | Código portable, docs, web, MCP, tests host. También correrá el **agente micro-ROS** (está en la red WiFi de la Vita y tiene ROS2 Jazzy en docker). |
| **Desarrollo** | PC CachyOS | 192.168.1.65 | VitaSDK: cross-compilación y empaquetado `.vpk`. |
| **Objetivo** | PS Vita 1000 | — | ARM Cortex-A9 ×4 32-bit, 512 MB RAM. Homebrew vía VitaSDK. |

**Regla de frontera (versión actual):** en la laptop se escribe y verifica
todo lo que se pueda verificar en host (módulos con tests de paridad, MCP,
web, docs); **ninguna toolchain del proyecto se instala en la laptop**
(Rust corre vía docker). La compilación para la Vita ocurre en el PC.

---

## Mapa del repo

```
PSVita-ROS/
├── docs/                  # 00-06 + ADRs + rust/ (aprendizaje) + guias-vita/
├── modules/               # los 3 módulos duales de la Fase 1
│   ├── mem-pool/          #   asignador de bloques fijos sin malloc
│   ├── net-udp/           #   sockets UDP: sceNet (Vita) / POSIX (host)
│   └── microros-transport/#   los 4 callbacks XRCE (la incógnita dura)
├── vita-app/              # app "Vita ROS2 Hello" (.vpk, se compila en el PC)
├── mcp/ros2-introspection/# servidor MCP: el grafo ROS2 visible para Claude
├── skills/                # 3 skills de Claude Code para el PC
├── tools/                 # run-parity-tests.sh (host) y sync legado
└── web/                   # sitio Astro+SQLite+Docker (guías y progreso)
```

Cada módulo y la app tienen su propio `README.md` con API, diseño y estado.

---

## Verificación rápida (laptop)

```bash
tools/run-parity-tests.sh        # paridad C/Rust de los 3 módulos (docker para Rust)
cd mcp/ros2-introspection && .venv/bin/python -m pytest tests/ -q
cd web && docker compose up -d --build   # la web en localhost:4321
```

## Compilar para la Vita (PC)

```bash
cd vita-app
./scripts/build-xrce-client-vita.sh   # una vez: micro-XRCE para armv7/newlib
cmake -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake \
      -DVITA_IMPL=c -B build && cmake --build build   # -> .vpk
```

`-DVITA_IMPL=rust` genera la variante con los módulos en Rust (ADR 0003).

---

## Documentación

| Doc | Contenido |
|---|---|
| `docs/00-vision-y-objetivos.md` | Los 6 objetivos y las restricciones |
| `docs/01` … `docs/05` | Hardware, arquitectura micro-ROS, estrategia dual, investigación rviz2, setup del PC |
| `docs/06-bitacora-estado.md` | **Dónde estamos y próximos pasos exactos** |
| `docs/adr/0001-0004` | Decisiones de arquitectura registradas |
| `docs/rust/00-02` | Aprendizaje de Rust ligado al código del repo |
| `docs/guias-vita/` | Instalar el homebrew de la consola (también en la web) |

## Transferencia laptop ↔ PC

Por **git**: `https://github.com/Jcrex/PSVita-ROS.git` (`git push` aquí,
`git pull` en el PC).
