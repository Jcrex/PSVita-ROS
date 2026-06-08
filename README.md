# PS Vita ↔ ROS2 — Taller de preparación (Fase 0)

Este repositorio es el **taller de preparación** del proyecto PS Vita ↔ ROS2. Aquí se produce la capa meta: documentación, skills de Claude Code, el servidor MCP y scripts de sincronización. El código C/C++/Rust que correrá en la Vita se desarrolla en el PC de desarrollo.

---

## Máquinas

| Rol | Equipo | IP | Función |
|---|---|---|---|
| **Taller** | Laptop (este repo) | 192.168.1.108 | Produce docs, skills, MCP y scripts. Sin instalaciones del proyecto. |
| **Desarrollo** | PC CachyOS | 192.168.1.65 | Desarrollo continuo. Toda instalación y ejecución ocurre aquí. |
| **Objetivo** | PS Vita 1000 | — | ARM Cortex-A9 32-bit, 512 MB RAM. Homebrew vía VitaSDK. |

---

## Regla de frontera

**En este repo se escriben** docs, skills, el código del MCP y scripts (la capa meta).

**No se escribe** el código C/C++/Rust que correrá en la Vita — ese nace en el PC de desarrollo.

**No se instala nada** del proyecto en la laptop. Todo se ejecuta e instala en el PC CachyOS.

---

## Mapa de carpetas

```
ps-vita-ros2/
├── README.md                        # este archivo
├── .gitignore
├── docs/
│   ├── 00-vision-y-objetivos.md
│   ├── 01-hardware-y-plataforma.md
│   ├── 02-arquitectura-fase1-microros.md
│   ├── 03-estrategia-dual-rust-cpp.md
│   ├── 04-investigacion-portabilidad-rviz2.md
│   ├── 05-setup-entorno-cachyos.md
│   ├── adr/                         # Architecture Decision Records
│   └── superpowers/
│       └── specs/                   # especificaciones de diseño
├── skills/                          # skills de Claude Code
├── mcp/                             # servidor MCP (ros2-introspection)
└── tools/                           # scripts de utilidad
    └── sync-to-devpc.sh
```

---

## Sincronizar al PC

Para transferir el contenido de este taller al PC de desarrollo, ejecuta el script de sincronización:

```bash
bash tools/sync-to-devpc.sh
```

La transferencia se realiza por SMB desde la laptop (192.168.1.108) al PC CachyOS (192.168.1.65). El script lo dispara el usuario manualmente.

---

## Especificación de diseño

El documento de diseño completo de la Fase 0 se encuentra en:

[`docs/superpowers/specs/2026-06-08-fundacion-psvita-ros2-design.md`](docs/superpowers/specs/2026-06-08-fundacion-psvita-ros2-design.md)
