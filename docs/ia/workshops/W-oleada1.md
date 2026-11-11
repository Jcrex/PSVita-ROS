# Oleada 1 — registro (2026-11-11)

| W | Pregunta | Equipo (modelo) | Duración | Resultado |
|---|---|---|---|---|
| W1 | Presupuesto HW real | investigador-vita-sdk (Opus), investigador-red (Opus), ambos aislados | ~8 y ~6 min | posts/W1-*.json — cifras en `tablero.json` |
| W4 | Portabilidad Ozuba + paridad API | inventario (Haiku, esfuerzo bajo) → investigador-portabilidad (Opus) | ~1 + ~10 min | posts/W4-*.json, W4-matriz-borrador.md |
| W5 | Addon godot-urdf | investigador-urdf (Opus) | ~6 min | posts/W5-urdf.json |
| W7 | Capacidades del port | investigador-motor (Opus) | ~4,5 min | posts/W7-motor.json |

- **Aislamiento**: cada investigador escribió solo su archivo; W4-portabilidad leyó únicamente el inventario de
  Haiku (dependencia declarada en el DAG).
- **Escalados**: ninguno de Haiku a Opus (el inventario fue mecánico; sus 3 dudas [?] las resolvió W4-portabilidad).
- **Revisión** (§4.3): revisor escéptico aislado (Opus, sin contexto de los workshops) → `posts/revision-oleada1.json`.
  Las decisiones que acaben en ADR las juzga Fable.
- **Condición de parada**: preguntas respondidas en código o marcadas «Por medir» con su prueba.
- **Hallazgo transversal**: un solo núcleo efectivo en la Vita (W1) + GXM solo triángulos (W7) + techo XRCE
  (W1) ⇒ todo lo pesado (decodificación, decimado, mapas) va a un **relay en el PC** o a C nativo con hilo propio.
- **Proyecto G1** (encargo del usuario, en paralelo): usa W5 (preprocesar URDF en el PC), W7 (solo
  MeshInstance3D/BoxMesh/albedo) y W1 (mensaje compacto ≤ 490 B en best effort).
