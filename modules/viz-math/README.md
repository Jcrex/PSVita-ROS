# Módulo dual `viz-math`

Matemática 3D mínima en `float` (vec3, quaternion, mat4 column-major) para el
mini-rviz: TF, cámara orbital y animación del robot (`docs/11`). Sin malloc ni
estado global; solo `libm`. Etapa D1 de `docs/10`.

`include/viz_math.h` es la única verdad; `impl-c/` e `impl-rust/` la cumplen
y pasan `tests/parity_test.c`, cuyos valores esperados están **calculados a
mano** (rotación de 90°, T·R, `look_at` desde (0,0,5), `perspective` 90°...).

## API (resumen)

| Grupo | Funciones |
|---|---|
| vec3 | `add sub scale cross dot norm normalize` |
| quat | `identity from_axis_angle mul normalize rotate_vec3 to_mat4` |
| mat4 | `identity mul translate from_trs inverse_rigid perspective look_at transform_point` |

Convenciones: mano derecha, radianes, `(x,y,z,w)`, matrices column-major
(`m[col*4+fila]`, traslación en `m[12..14]`), `p' = M·p`, `mul(out,a,b)=a·b`.
Alias permitido en `mul`, `cross`, `quat_mul`, `rotate_vec3`.

## Decisiones

- **`f32`, no `f64`**: el Cortex-A9 tiene VFPv3/NEON para `f32` (docs/14 §2).
- **Rust sin `std`**: `sinf/cosf/tanf/sqrtf` se piden a la libm de C
  (`unsafe extern "C"` + `safe fn`); mismo origen que impl-c → resultados
  prácticamente idénticos. Detalle en los comentarios de `impl-rust/src/lib.rs`.
- Funciones con entrada inválida devuelven `-1` y dejan identidad/cero en `out`
  (`perspective`, `look_at`, `normalize`), nunca NaN silenciosos.
- La app ya enlaza `libmathneon` (vdpm); sustituir partes por NEON es una
  optimización **futura y medible**, no necesaria para la paridad.

## Estado

- [x] Paridad C/Rust verde en host (2026-10-27).
- [ ] **Validar en el PC:** cross-compilar (el crate paraguas ya lo incluye).
- [ ] **Validar en hardware:** medir coste de `mat4_mul` / `from_trs` por frame.
- [ ] Integrar en `vita-app/src/viz/` (hoy `camera.c` trae su propia matemática).
