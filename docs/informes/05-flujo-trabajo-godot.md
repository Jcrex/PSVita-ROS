# 05 — Cómo trabajar con Godot (tú + Claude)

Investigado el 2026-11-01 con 3 subagentes. Detalle y fuentes: `docs/ia/investigacion-flujo-godot-2026-11-01.md`.

## Conclusión

**De momento no hace falta un MCP.** El editor 4.8-dev7 ya trae casi todo lo que necesitamos.
Ningún MCP funciona en la Vita: allí seguimos con export, FTP y logs.

## Qué funciona ya (probado con tu binario)

| Para qué | Cómo |
|---|---|
| Errores de código | `--check-only --script res://x.gd` (sale con 1 si hay error) |
| Avisos tratados como errores | en `project.godot`: `[debug] gdscript/warnings/untyped_declaration=2` |
| Que Claude **vea** la escena 3D | `$G --path P --write-movie /tmp/shot.png --quit-after 30` → Claude lee el PNG |
| Pruebas | el runner propio `godot/test/` (GUT y gdUnit4 no aportan aquí) |
| API real, incluidas `RosNode`… | `--doctool` |
| Errores en vivo (LSP) | el editor lo sirve sin ventana (`--lsp-port`) |

## Reparto del trabajo

| Tú, en el editor | Claude, en texto |
|---|---|
| componer escenas (nodos, inspector, materiales) | `.gd` y esqueletos de escena |
| abrir y guardar (Ctrl+S) cada `.tscn` nueva antes del commit | explicar el diff |

¿Por qué guardar? Las `.tscn` escritas a mano se reescriben la primera vez que el editor las guarda,
y el diff sale ruidoso. Además, hay que **subir los `*.uid`** al commit; `.godot/` nunca.

## Opciones, por orden

| # | Opción | Valor | Coste |
|---|---|---|---|
| 1 | Hábitos de arriba (guardar escenas, `.uid`, avisos=error, capturas) | alto | nada |
| 2 | **LSP del editor en Claude Code** (puente con `socat`): errores tras cada edición | alto | 1 script + plugin local; sin probar |
| 3 | Hook que pasa `--check-only` a cada `.gd` editado | medio | pocas líneas |
| 4 | MCP `hi-godot/godot-ai` (capturas del editor, logs) | medio | addon; compatibilidad con 4.8-dev7 sin probar |

MCP descartados: los que abren un puerto que ejecuta código sin contraseña (`game_eval`), los
abandonados y los de pago o cerrados.

## Tú decides

1. ¿Aplico los hábitos de la opción 1 (CLAUDE.md, skill y la lista P10)?
2. ¿Montamos el LSP (opción 2) como mini-hito con lección?
3. ¿Probamos un MCP en un proyecto desechable, o lo dejamos?
