# docs/ia — documentación para Claude (no para el usuario)

Decisión del usuario (2026-10-31): **dos documentaciones**.

| Para | Dónde | Forma |
|---|---|---|
| El usuario | `docs/tutorial/` (y las respuestas en el chat) | **≤ 500 palabras** por documento o explicación. Al grano: tablas, comandos, 3–5 preguntas de control. Sin historia ni rodeos |
| Claude | `docs/ia/` (esta carpeta) + `docs/00–22`, ADRs, README de módulos | Tan detallado como convenga: guiones de enseñanza, cadenas de llamadas con archivo:línea, hipótesis, matices |

## Contenido

- `guion-ruta-aprendizaje.md`: versión larga de `docs/tutorial/07`. Las 11 pistas con lecturas,
  prácticas, la lista de auditoría completa y la autoevaluación de 9 preguntas. Úsala para preparar
  sesiones y elegir qué enseñar a continuación.
- `guion-leccion-08-imu.md`: versión larga de `docs/tutorial/08`. La cadena del sensor
  (`display_server_vita.cpp` → `RosPublisher::publish` → `XrceTransport::publish`), la explicación
  de `main.gd` por bloques y los retos 3–6. Úsala para responder dudas del usuario sobre G7a.
- `guion-guia-tutorial-original.md`: la guía 00 completa anterior (sandbox `practica/`, flujo de
  retos, rama `tutorial-vita`).
- `plan-tutorial-2026-07-12.md` / `spec-tutorial-2026-07-12.md`: copias del plan y la spec del
  tutorial (originales archivados en `archivo/docs/superpowers/`). Es el único guion de las
  lecciones 02–06, que siguen **sin escribir** (Tasks 3–7 del plan).
- `auditoria/`: informes de la auditoría de la flota (2026-11-01): limpieza, optimización, mapa de
  Rust y viabilidad de dbtsdf. Índice en `auditoria/README.md`.

## Reglas al escribir para el usuario

1. Cuenta las palabras (`wc -w`) antes de entregar: máximo 500.
2. Primero el qué y el comando; el porqué en una línea.
3. Si hace falta más detalle, va aquí y la lección corta solo enlaza o lo omite.
4. Una lección nueva por hito: corta en `docs/tutorial/` y su guion largo aquí si hace falta.

Esta carpeta no está en una colección de la web a propósito: es material de trabajo de la IA,
no documentación del proyecto.
5. **Shell:** en el PC CachyOS el usuario usa **fish**; en las demás máquinas, **zsh**. Los comandos
   para el PC tienen que funcionar en fish: `set G ruta` (no `G=ruta` suelto), `(cmd)` (no `$(cmd)`),
   `set -x VAR valor` (no `export`). `VAR=valor comando` y `&&` sí funcionan en fish 4.9.
