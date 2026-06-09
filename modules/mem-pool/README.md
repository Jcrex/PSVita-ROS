# Módulo dual `mem-pool`

Asignador de memoria por **pools de bloques de tamaño fijo**. micro-ROS lo
usará para sus asignaciones internas: evita la fragmentación del heap y los
fallos tardíos de `malloc()` en sesiones largas (la app de la Vita corre
indefinidamente como nodo ROS2).

Primer módulo dual del proyecto (ver `docs/03-estrategia-dual-rust-cpp.md`):
`include/mem_pool.h` es la única verdad; `impl-c/` e `impl-rust/` la cumplen
y pasan la misma batería `tests/parity_test.c`.

## API (resumen del header)

| Función | Qué hace |
|---|---|
| `mem_pool_required_size(bs, n)` | Bytes de respaldo necesarios (cabecera 64 B + bloques redondeados a 8). 0 si inválido o desborda. |
| `mem_pool_create(backing, len, bs, n)` | Inicializa el pool dentro del buffer del llamador (sin malloc). NULL si argumentos inválidos. |
| `mem_pool_alloc(pool)` | Toma un bloque; NULL si agotado. |
| `mem_pool_free(pool, blk)` | Devuelve un bloque; detecta punteros ajenos, desalineados y doble free (`MEM_POOL_ERR_BAD_PTR`). |
| `mem_pool_blocks_free(pool)` | Bloques libres actuales. |
| `mem_pool_block_size(pool)` | Tamaño efectivo de bloque. |

## Diseño interno (idéntico comportamiento observable en ambas impl)

- La estructura de control vive en los primeros 64 bytes del buffer de
  respaldo; el pool **no llama a malloc** (apto para memoria estática).
- Free-list intrusiva: cada bloque libre guarda en sus primeros 8 bytes el
  puntero al siguiente libre. Por eso el bloque mínimo son 8 bytes.
- El primer `alloc` tras crear devuelve el bloque de dirección más baja
  (orden de la free-list = parte del contrato observable, lo verifica
  `test_alloc_order_parity`).

## Tests de paridad

```bash
tools/run-parity-tests.sh mem-pool   # host: gcc para C, cargo (o docker rust:1-slim) para Rust
```

Casos cubiertos: tamaños requeridos y desbordamiento de `size_t`, argumentos
inválidos de create, ciclo alloc/free completo con agotamiento, alineación,
no-solapamiento, orden del primer alloc, free de punteros ajenos/interiores,
doble free, y consultas sobre pool NULL.

## Estado

- [x] Paridad verificada en host (laptop, x86_64): C y Rust pasan 100%.
- [ ] Compilación cruzada a la Vita (`-DVITA_IMPL=c|rust` con VitaSDK/cargo
      nightly): pendiente de hacerse en el PC.
