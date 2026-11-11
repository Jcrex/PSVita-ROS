# Workshops de investigación — etapa «estación robótica» (2026-11)

Registro del método multiagente pedido por el usuario el 2026-11-11 (LT1–LT8, fases 1–4, apartado 4 del
encargo). Documentación para Claude; no va a la web (en pausa).

## Piezas

| Pieza | Dónde | Regla |
|---|---|---|
| Registro de cada workshop | `Wn-<tema>.md` | pregunta, equipo (modelo de cada papel), rondas, veredicto, escalados, condición de parada |
| Posts de la ronda divergente | `posts/Wn-<papel>.json` | cada investigador **escribe solo su archivo y no lee los de los demás** hasta la integración |
| Tablero integrado | `tablero.json` | solo lo modifica el orquestador, con parches (`tablero-parches.log`: fecha, workshop, qué cambia y por qué) |

## Esquema de post (§4.2)

```json
{ "workshop": "W1", "autor": "investigador-vita (opus)", "candidato": "…", "evidencia": "…",
  "fuentes": ["ruta:línea o URL"], "confianza": "[V]|[I]|[?]", "coste_estimado": "…",
  "como_se_mediria_en_hardware": "…" }
```

Un archivo de posts es un array JSON de objetos con ese esquema.

## Veredictos (§4.3)

`VERIFICADO` (revisor sin contexto previo lo confirma) · `DESAFÍO` (el escéptico encontró un fallo sin
resolver) · `ALTERNATIVA` (hay una opción mejor). Nada entra en un doc final sin VERIFICADO y sin al menos una
búsqueda de alternativa registrada. Si la respuesta solo puede salir de medir en la Vita: `Por medir` + gate.

## Modelos (§4.6)

Fable 5.2 (`fable`, esfuerzo máx.): ADRs, escalera DB-TSDF, plugins, reparto Vita/PC, juez dudoso, pre-mortem
de fase. Opus 5.5 (`opus`): orquestador, investigadores, escéptico, revisor. Haiku 5.5 (`haiku`, esfuerzo
bajo): inventarios, grep, enlaces, versiones; nunca veredictos.

## DAG aprobado (2026-11-11)

① W1 presupuesto HW · W7 capacidades del port · W4 portabilidad Ozuba · W5 addon godot-urdf →
② W3 DB-TSDF · W2 límites XRCE · W6 prueba TF+RobotModel →
③ W8 render sin shaders · W9 acciones sin XRCE · W12 sensores y visión →
④ W10 plugins + capa URDF · W11 reparto Vita/PC → síntesis (docs 24+, ADRs, backlog de gates, [?]).

En paralelo: proyecto **Unitree G1** (`godot/g1-unitree/`, pedido por el usuario el 2026-11-11), que sirve de
caso de prueba real para W5, W6, W10 y LT4.
