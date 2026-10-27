# Módulo dual `tf-tree`

Árbol de transformadas del mini-rviz: guarda el **último valor** de cada frame
y resuelve cadenas padre→hijo con `viz-math`. Etapa D3 de `docs/10`.

`include/tf_tree.h` es la única verdad. Depende de `viz-math` (matemática) y de
`msg-cdr` (solo los tipos de `TFMessage`).

## API

| Función | Qué hace |
|---|---|
| `tf_tree_required_size / create / clear` | Árbol de 32 frames en el buffer del llamador (3080 B) |
| `tf_tree_update(parent, child, t, q)` | Inserta/actualiza y puede **reparentar**; normaliza `q`; rechaza ciclos y tabla llena sin modificar nada |
| `tf_tree_apply_message(&TFMessage)` | Aplica un mensaje decodificado; cuenta rechazos (`tf_tree_rejected`) |
| `tf_tree_lookup(target, source, &mat4)` | `p_target = M · p_source` (como `tf2 lookupTransform`) |

## Simplificaciones respecto a tf2 (a propósito)

Sin historial temporal (no interpola ni mira timestamps), `/tf` y `/tf_static`
tratados igual, 32 frames, nombres con barra inicial opcional y 1..63 caracteres.

## Tests

`tests/parity_test.c`, con valores a mano: cadena world→odom→base_link(R90°)→laser,
inversa, hermanos (camera↔laser), identidad, desconectados (`NO_PATH`), ciclos,
reparentado, cuaternión no unitario, tabla llena (31 hijos + raíz) y
`apply_message` con un ciclo rechazado. La impl C pasó también con ASan/UBSan.

## Estado

- [x] Paridad C/Rust en host (2026-10-27).
- [ ] **Validar en el PC / hardware:** cross-compilar; medir `lookup` por frame.
- [ ] Integrar con `msg-cdr` en `on_topic` y con el modelo VBM (Etapa E).
