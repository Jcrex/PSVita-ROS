# docs/ia — documentación de trabajo de la IA (no para el usuario)

Decisión del usuario (2026-10-31): **dos documentaciones**.

| Para | Dónde | Forma |
|---|---|---|
| El usuario | `docs/tutorial/` (y las respuestas en el chat) | **≤ 500 palabras** por documento o explicación. Al grano: tablas, comandos, 3–5 preguntas de control. Sin historia ni rodeos |
| Claude | `docs/ia/` (esta carpeta) + los docs numerados, ADRs y README de módulos (índice: [`../README.md`](../README.md)) | Tan detallado como convenga: guiones de enseñanza, cadenas de llamadas con archivo:línea, hipótesis, matices |

Desde el 2026-11-11 el modo aprendizaje está **en pausa** (`CLAUDE.md`, «Working method»): solo informes largos;
las versiones cortas, solo si el usuario las pide.

## Carpetas (ADR 0014 §4.4)

| Carpeta | Qué hay | Tipo |
|---|---|---|
| [`tutorial/`](tutorial/) | Guiones largos del tutorial: `guion-ruta-aprendizaje.md` (versión larga de `docs/tutorial/07`: 11 pistas, prácticas, auditoría, autoevaluación), `guion-leccion-08-imu.md` (de `docs/tutorial/08`: cadena del sensor y retos 3–6), `guion-g7c-3d-en-la-vita.md` (G7c), `plan-tutorial-2026-07-12.md` / `spec-tutorial-2026-07-12.md` (único guion de las lecciones 02–06, **sin escribir**; originales en `archivo/docs/superpowers/`) | Vigente (pausa) |
| [`medidas/`](medidas/) | Logs de hardware de la Vita (hoy, `g1-sensores` del 2026-11-13, doc 34 §7); aquí van los logs de los gates de la Fase V | Registro de datos |
| [`workshops/`](workshops/README.md) | Método multiagente de la etapa «estación robótica» (LT1–LT8, W1–W13): README con el método, tablero, `W13-visualizacion-topics.md`; `posts/` = borradores y JSON de cada workshop | Vigente (método); `posts/` = registro |
| [`auditoria/`](auditoria/README.md) | Auditoría de la flota del 2026-11-01 (limpieza, optimización, mapa Rust, DB-TSDF) y estado de sus lotes | Registro (lotes 4–5 abiertos) |
| [`revision-kimi/`](revision-kimi/README.md) | Revisión del trabajo de Kimi (2026-11-12/13): R1–R4, arreglos GDScript | Registro |
| [`organizacion/`](organizacion/decision-fable.md) | Fase O (2026-11-13): diagnósticos O1b–O1d, decisión del juez y registro de ejecución O2 | Registro |

Sueltos (ADR 0014 §4.4: solo este README, el plan en ejecución y la investigación de flujo):

- [`plan-organizacion-y-visor-2026-11-13.md`](plan-organizacion-y-visor-2026-11-13.md): plan en ejecución (Fase O → Fase V).
- [`investigacion-flujo-godot-2026-11-01.md`](investigacion-flujo-godot-2026-11-01.md): cómo trabajar con Godot (IA + usuario).

Archivado (2026-11-13): `guion-guia-tutorial-original.md` y `prompt-siguiente-sesion.md` → `archivo/docs/ia/`.

## Reglas al escribir para el usuario

1. Cuenta las palabras (`wc -w`) antes de entregar: máximo 500.
2. Primero el qué y el comando; el porqué en una línea.
3. Si hace falta más detalle, va aquí y la lección corta solo enlaza o lo omite.
4. Una lección nueva por hito: corta en `docs/tutorial/` y su guion largo aquí (`tutorial/`) si hace falta.
5. **Shell:** en el PC CachyOS el usuario usa **fish**; en las demás máquinas, **zsh**. Los comandos
   para el PC tienen que funcionar en fish: `set G ruta` (no `G=ruta` suelto), `(cmd)` (no `$(cmd)`),
   `set -x VAR valor` (no `export`). `VAR=valor comando` y `&&` sí funcionan en fish 4.9.

Esta carpeta no está en una colección de la web a propósito: es material de trabajo de la IA,
no documentación del proyecto.
