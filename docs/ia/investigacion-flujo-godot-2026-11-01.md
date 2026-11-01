# Investigación: cómo trabajar con Godot (IA + usuario) — 2026-11-01

Versión larga, para Claude. La corta para el usuario: `docs/informes/05-flujo-trabajo-godot.md`.
Tres subagentes en paralelo: (A) servidores MCP, (B) herramientas nativas (LSP, avisos, pruebas,
capturas, docs), (C) reparto de trabajo y convenciones. Ninguno tocó el repo. B ejecutó el binario
4.8-dev7 sobre una copia en `/tmp` (ya borrada) y abrió un instante la ventana `.gui`.

## A. Servidores MCP (estrellas y fechas: `gh api`, 2026-11-01)

| Servidor | Conexión | Lo útil | Godot | Estado | Riesgo |
|---|---|---|---|---|---|
| Coding-Solo/godot-mcp | CLI (lanza el binario, `GODOT_PATH`), sin addon | run_project, get_debug_output, create_scene, add_node | cualquiera (UIDs 4.4+) | MIT, 6,5k★, push 2026-04 | bajo |
| tugcantopaloglu/godot-mcp (fork) | CLI + autoload TCP 9090 opcional | 157 herramientas; `validate_script` resuelve autoloads; capturas | 4.4+ (probado 4.7) | MIT, 508★, push 2026-10-09 | `game_eval` por TCP sin autenticación; no copiar el autoload |
| hi-godot/godot-ai | addon editor → WS 9500 → Python 8000 → stdio | escena, nodos, `editor_screenshot`, `logs_read`, `test_run` | 4.7+, editor con ventana | MIT, 3,3k★, v4.3.1 2026-10-24 | el mejor: credenciales rotativas, loopback, escrituras confinadas; telemetría desactivable |
| satelliteoflove/godot-mcp | addon + WS, protocolo del depurador | capturas, estado en ejecución, `--read-only` | 4.5+ | MIT, 183★ | `godot_exec` |
| ee0pdt/Godot-MCP | addon + Node | básico | ? | abandonado (2025-03) | — |
| GDAI MCP / Godot MCP Pro | plugin cerrado | — | — | de pago / propietario | no auditables |

No hay MCP oficial. Ninguno ejecuta en la Vita: XRCE real, IMU y rendimiento siguen con export → FTP → logs.
Riesgos comunes: `npx -y`/`uvx` sin versión fija; addons en `addons/` deben excluirse del preset de export;
godot-ai registra por defecto en ámbito `user` (ponerlo en `project`).

## B. Herramientas nativas (verificado con 4.8.dev7.custom_build.d1a5f291b)

| Herramienta | Comando | Estado |
|---|---|---|
| LSP sin ventana | `$B --headless --editor --path P --lsp-port 6015` → diagnósticos de tipos, funciones inexistentes, avisos | verificado |
| LSP en Claude Code | plugin con `lspServers`/`.lsp.json`; Claude Code solo habla stdio → puente `socat STDIO TCP:127.0.0.1:PORT` (`/usr/bin/socat` existe) | **hipótesis** (doc: code.claude.com/docs/en/plugins-reference) |
| Avisos como error | `project.godot`: `[debug] gdscript/warnings/untyped_declaration=2` (también `unsafe_*`, `unused_variable`) → `--check-only` sale con 1 | verificado (no existe `treat_warnings_as_errors` para GDScript) |
| Pruebas | runner propio `godot/test/project/runner.gd` (`run_host_tests.sh`); GUT/gdUnit4 sin verificar en 4.8-dev | mantener el propio |
| Captura para que Claude VEA | `$G --path P --resolution 480x272 --write-movie /tmp/shot.png --fixed-fps 30 --quit-after 30` → PNG legibles con Read | verificado (en headless saldría negra: hipótesis) |
| `--import` | necesario en proyectos sin `.godot/` antes de `--check-only` | verificado |
| API offline | `$B --headless --doctool DIR` → 1085 XML, incluidas `Ros*` (sin descripciones) | verificado |
| gdtoolkit 4.5.0 | `gdlint`/`gdformat`, no instalado; puede ir por detrás de 4.8 | sin verificar |

Propuesta LSP: `tools/godot-lsp-stdio.sh <proyecto>` (lanza el editor headless con `--lsp-port`, espera el
puerto, `exec socat STDIO TCP:…`) + plugin local con `.lsp.json`
(`command` absoluto, `extensionToLanguage {".gd":"gdscript"}`, `startupTimeout 30000`). Limitación: un
servidor por proyecto (`--path`).

## C. Reparto y convenciones

- El usuario compone escenas en el editor (pista P3); Claude escribe `.gd` y como mucho esqueletos de escena.
- `.tscn` escrita a mano ⇒ el primer guardado del editor reescribe ids/uids/valores por defecto y ensucia
  el diff de la P10. Práctica: tras crear una escena, el usuario la abre y guarda (Ctrl+S) antes del commit.
  Escenas «de código» (rejillas, ejes): nodos creados en `_ready()`.
- Versionar `*.uid` (Godot 4.4+: godotengine.org/article/uid-changes-coming-to-godot-4-4/); `.godot/` nunca.
  Hoy: g7-imu los versiona, g7b sin seguimiento, g6-hmi no tiene.
- Convenciones: tipado estático; `%Nodo` en vez de rutas largas; señales hacia arriba; lógica pura en `.gd`
  aparte con prueba headless (como `filtro.gd`).
- Hook PostToolUse `Edit|Write` sobre `.gd` → `--check-only`; exit 2 con el error. `.claude/` es local:
  documentarlo en `skills/INSTALAR.md`. Riesgo: falsos errores sin `.godot/` (hacer `--import`).
- Tutor: retos pequeños, «predice el `print()`», comparar `.tscn` antes/después de guardar. P10 + «¿escena
  re-guardada? ¿`.uid` en el commit?».

## Síntesis (recomendación)

1. **Ya, sin instalar nada:** avisos a nivel 2 en los `project.godot` nuevos, `--check-only` + runner propio,
   capturas con `--write-movie` para escenas visuales, `.uid` versionados, escena re-guardada por el usuario.
2. **Siguiente (mayor valor):** LSP del editor vía `socat` como plugin local → diagnósticos tras cada edición.
3. **Hook `--check-only`** si el LSP no cuaja (más simple, menos información).
4. **MCP: no ahora.** Duplica lo que ya hacemos por shell y choca con el modo aprendizaje (lanza cosas solo).
   Si se quiere probar: godot-ai en un proyecto desechable (compatibilidad 4.8-dev7 = hipótesis); nunca
   autoloads TCP ni `game_eval` pre-aprobado.
