# Lección 01 — C de bajo nivel leyendo mem-pool

En esta lección leemos, de arriba abajo, el módulo más autocontenido del
proyecto: **mem-pool**. No tiene red ni SDK, solo memoria y punteros — perfecto
para aprender el C de bajo nivel que usa todo el repo. Al terminar sabrás leer
punteros, entender una *free-list*, y compilar y correr tu propio programa que
usa el módulo.

Archivos que recorremos:

- `modules/mem-pool/include/mem_pool.h` — el **contrato** (la verdad del módulo).
- `modules/mem-pool/impl-c/mem_pool.c` — la **implementación en C**.

> La versión en Rust del mismo módulo la vemos en la
> [Lección 02](./02-rust-fundamentos-con-mem-pool.md), comparándola línea a
> línea con lo de aquí.

## 1. Qué resuelve mem-pool

Un **pool de memoria** de bloques de tamaño fijo. En vez de pedir memoria al
sistema con `malloc()` cada vez (lento, y en sesiones larguísimas se
fragmenta y puede fallar), reservas **una vez** un bloque grande de memoria y
el pool te lo va repartiendo en trozos iguales, muy rápido y sin fallos
tardíos. La app de la Vita corre indefinidamente como nodo ROS2, así que esto
importa.

Dos ideas de diseño que verás reflejadas en el código (header, líneas 13–19):

- **El llamador aporta la memoria** (`backing`). El pool **no** llama a
  `malloc`; tú le das un buffer y él lo organiza. Así el buffer puede vivir en
  memoria estática de la app.
- **La estructura de control vive dentro de ese mismo buffer**, en sus
  primeros bytes. No hay memoria "aparte".

## 2. El header es el contrato

Abre `mem_pool.h`. Un header en C es la **lista de lo que existe**: qué
funciones puedes llamar y qué tipos hay, sin decir *cómo* están hechas. Piezas:

```c
#ifndef VITA_MEM_POOL_H
#define VITA_MEM_POOL_H
...
#endif
```

Esto es un **include guard**. Si dos archivos hacen `#include "mem_pool.h"`,
sin el guard el contenido se pegaría dos veces y el compilador se quejaría de
definiciones duplicadas. La primera vez define `VITA_MEM_POOL_H`; la segunda,
como ya está definido, el `#ifndef` salta todo el archivo.

```c
#ifdef __cplusplus
extern "C" {
#endif
```

C++ "decora" los nombres de las funciones (*name mangling*) para permitir
sobrecarga. `extern "C"` le dice: «trata estas funciones como C puro, sin
decorar». Es lo que permite que C, C++ **y** Rust hablen por el mismo header.

### El tipo opaco

```c
typedef struct mem_pool mem_pool;   // header, línea 38
```

Fíjate: se declara que **existe** un `struct mem_pool`, pero **no** qué campos
tiene. Eso está a propósito: es un **tipo opaco**. Quien usa el módulo recibe
un `mem_pool *` (un puntero a esa estructura) y lo pasa de vuelta, pero no
puede tocar sus campos porque no los conoce. Los campos reales se definen en el
`.c` (los vemos en la sección 4). Esto es **encapsulación** en C: el layout
interno es asunto de cada implementación, y por eso C y Rust pueden tenerlo
distinto por dentro cumpliendo el mismo header.

### Códigos de estado

```c
typedef enum {
    MEM_POOL_OK              = 0,
    MEM_POOL_ERR_INVALID_ARG = -1,
    MEM_POOL_ERR_BAD_PTR     = -2,
} mem_pool_status;
```

Convención de todo el proyecto: **0 = éxito, negativo = error**. Un `enum` en C
es solo un conjunto de constantes enteras con nombre. Muchas funciones
devuelven este `mem_pool_status` para decir si salió bien.

## 3. Los tipos de C que aparecen

Antes de la implementación, tres tipos que vas a ver mucho (vienen de
`<stddef.h>` y `<stdint.h>`):

| Tipo | Qué es | Por qué se usa aquí |
|---|---|---|
| `size_t` | Entero sin signo para **tamaños y conteos**. Su ancho es el de la máquina (32 bits en la Vita, 64 en tu PC). | Todo lo que mide bytes o cuenta bloques. |
| `uint8_t` | Entero de **exactamente 8 bits** (un byte). | Recorrer memoria byte a byte. |
| `uintptr_t` | Entero lo bastante grande para guardar **una dirección** de memoria. | Hacer aritmética de bits sobre punteros (alineación). |
| `void *` | Puntero "a cualquier cosa": una dirección sin tipo. | El pool reparte memoria cruda; quien la pide decide qué guardar. |

Un **puntero** es simplemente una variable que guarda **una dirección de
memoria**. `uint8_t *p` significa «`p` guarda la dirección de un byte». Si
sumas `p + 1`, avanzas **1 byte**; si fuera `int *`, `p + 1` avanzaría 4 bytes.
Esa es la clave de casi todo lo que sigue.

## 4. La estructura de control (por fin, dentro del .c)

En `mem_pool.c`, líneas 18–24, se define de verdad lo que el header dejó
opaco:

```c
struct mem_pool {
    uint8_t *blocks_start;   /* inicio del área de bloques                 */
    size_t   eff_block_size; /* tamaño de bloque redondeado a 8            */
    size_t   block_count;    /* bloques totales                            */
    size_t   blocks_free;    /* bloques libres ahora                       */
    void    *free_head;      /* cabeza de la lista de bloques libres       */
};
```

Y arriba, dos constantes (líneas 15–16):

```c
#define POOL_HEADER_BYTES 64u   /* espacio reservado para esta estructura */
#define POOL_ALIGN 8u           /* alineación garantizada de los bloques  */
```

El buffer que tú entregas queda así:

```
backing:
┌─────────────────────────┬───────┬───────┬───────┬─────┐
│ struct mem_pool (64 B)   │ blk 0 │ blk 1 │ blk 2 │ ... │
└─────────────────────────┴───────┴───────┴───────┴─────┘
^                          ^
backing                    blocks_start = backing + 64
```

Los primeros 64 bytes son la estructura de control; el resto son los bloques.
Se reservan 64 bytes fijos (más de lo que ocupa el struct en cualquier
plataforma) para que el **cálculo de tamaño sea idéntico** entre C y Rust —
requisito de la paridad.

## 5. Cuánta memoria hace falta: `mem_pool_required_size`

Antes de crear un pool necesitas saber cuánto buffer reservar. Eso lo dice
esta función (`.c`, líneas 42–55):

```c
size_t mem_pool_required_size(size_t block_size, size_t block_count)
{
    if (block_size == 0 || block_count == 0) {
        return 0;
    }
    size_t eff = effective_block_size(block_size);
    if (eff == 0) {
        return 0;
    }
    if (block_count > (SIZE_MAX - POOL_HEADER_BYTES) / eff) {
        return 0; /* desbordaría size_t */
    }
    return POOL_HEADER_BYTES + eff * block_count;
}
```

Dos detalles muy "de C":

**El tamaño efectivo del bloque** (`effective_block_size`, líneas 31–40):

```c
size_t eff = block_size < POOL_ALIGN ? POOL_ALIGN : block_size;
return round_up_align(eff);
```

Aunque pidas bloques de 4 bytes, el mínimo es **8**, porque un bloque libre
necesita guardar dentro un puntero (lo veremos en la sección 7), y además todo
se redondea hacia arriba a múltiplo de 8. Por eso, pedir bloques de 4 da
bloques efectivos de 8.

**El chequeo de overflow** (línea 51). Como `size_t` no tiene signo, si el
producto `eff * block_count` se pasa del máximo, **no** hay error: da la vuelta
y devuelve un número pequeño y equivocado (comportamiento silencioso y
peligroso). Para evitarlo, en vez de multiplicar y ver si "se pasó", se
comprueba **antes** con una división: «¿cabe `block_count` en el espacio que
queda?». Este patrón defensivo lo verás por todo el código de bajo nivel.

> **Redondeo con bits** (`round_up_align`, línea 26):
> ```c
> return (n + (POOL_ALIGN - 1)) & ~(size_t)(POOL_ALIGN - 1);
> ```
> Con `POOL_ALIGN = 8`, `POOL_ALIGN - 1 = 7` (en binario `...0111`). Sumar 7 y
> luego borrar los 3 bits bajos con `& ~7` redondea al siguiente múltiplo de 8.
> No hace falta que memorices la fórmula; sí que reconozcas «esto redondea a
> múltiplo de 8».

## 6. Crear el pool: `mem_pool_create`

`.c`, líneas 57–85. Primero valida, luego coloca la estructura y encadena los
bloques.

```c
if (((uintptr_t)backing & (POOL_ALIGN - 1)) != 0) {
    return NULL; /* el respaldo debe venir alineado a 8 */
}
```

Aquí se convierte el puntero a `uintptr_t` (un entero) para mirarle **los bits
bajos**. Si los 3 bits bajos no son 0, la dirección no es múltiplo de 8, y se
rechaza. Muchas arquitecturas (incluida la de la Vita) requieren que los datos
estén alineados; leer desalineado puede ir lento o fallar.

```c
mem_pool *pool = (mem_pool *)backing;      // línea 71
pool->blocks_start   = (uint8_t *)backing + POOL_HEADER_BYTES;
pool->eff_block_size = effective_block_size(block_size);
pool->block_count    = block_count;
pool->blocks_free    = block_count;
```

Esta línea es la que "coloca" la estructura de control **encima** de los
primeros bytes del buffer: se reinterpreta la dirección `backing` como si
fuera un `mem_pool *`, y a partir de ahí `pool->campo` escribe dentro del
buffer. `->` es «accede a un campo a través de un puntero» (equivale a
`(*pool).campo`).

`blocks_start` se calcula como `backing + 64`: justo después de la cabecera.
Fíjate en el `(uint8_t *)`: se convierte a puntero-a-byte **para** que el `+
POOL_HEADER_BYTES` avance exactamente 64 bytes (no 64 × algo).

## 7. El corazón: la free-list intrusiva

Esta es la idea más importante de la lección. ¿Cómo sabe el pool qué bloques
están libres, sin gastar memoria extra en una lista aparte?

Respuesta: usa los **propios bloques libres** para encadenarse. Cada bloque
libre guarda, **en sus primeros bytes**, la dirección del siguiente bloque
libre. Es una lista enlazada que vive *dentro* de la memoria que administra —
por eso "intrusiva". `free_head` apunta al primer libre.

El encadenado inicial (`.c`, líneas 78–83):

```c
pool->free_head = NULL;
for (size_t i = block_count; i > 0; i--) {
    uint8_t *blk = pool->blocks_start + (i - 1) * pool->eff_block_size;
    *(void **)blk = pool->free_head;
    pool->free_head = blk;
}
```

Vamos despacio con la línea clave, `*(void **)blk = pool->free_head;`:

- `blk` es la dirección del bloque `i-1` (aritmética de punteros: inicio + índice × tamaño).
- `(void **)blk` dice: «trata esa dirección como si ahí hubiera **un puntero**».
- `*(void **)blk = X` dice: «escribe `X` en los primeros bytes del bloque».

Es decir: en cada bloque escribimos la dirección del que hasta ahora era la
cabeza, y luego movemos la cabeza a este bloque. Recorriendo de atrás hacia
adelante, la lista queda encadenada **en orden de dirección ascendente**:

```
free_head → blk0 → blk1 → blk2 → NULL
            (cada flecha vive DENTRO del bloque anterior)
```

## 8. Pedir y devolver bloques

**`mem_pool_alloc`** (`.c`, líneas 87–96) — quitar el primero de la lista:

```c
void *blk = pool->free_head;
pool->free_head = *(void **)blk;  /* la nueva cabeza es "el siguiente" */
pool->blocks_free--;
return blk;
```

Lee el puntero "siguiente" que el propio bloque guardaba, lo pone como nueva
cabeza, y te entrega el bloque. O(1), sin buscar nada.

**`mem_pool_free`** (`.c`, líneas 98–124) — validar y volver a encadenar. Antes
de aceptar el bloque comprueba tres cosas:

```c
if (blk < pool->blocks_start || blk >= end) {
    return MEM_POOL_ERR_BAD_PTR;   /* no pertenece al pool */
}
if ((size_t)(blk - pool->blocks_start) % pool->eff_block_size != 0) {
    return MEM_POOL_ERR_BAD_PTR;   /* no apunta al inicio de un bloque */
}
for (void *cur = pool->free_head; cur != NULL; cur = *(void **)cur) {
    if (cur == block) {
        return MEM_POOL_ERR_BAD_PTR;  /* doble free */
    }
}
```

1. ¿Está dentro del rango del pool?
2. ¿Cae justo al **inicio** de un bloque? (la resta de punteros da el
   desplazamiento en bytes; si no es múltiplo del tamaño de bloque, el puntero
   está torcido).
3. ¿Ya estaba libre? Ese bucle es el patrón para **recorrer una lista
   enlazada**: empieza en `free_head` y en cada vuelta salta al siguiente con
   `cur = *(void **)cur`, hasta llegar a `NULL`. Si encuentra el bloque, es un
   **doble free** y lo rechaza.

Si pasa las tres, lo vuelve a poner como cabeza de la free-list (igual que en
el encadenado inicial) e incrementa `blocks_free`.

## 9. Las consultas

Dos funciones triviales pero que enseñan un patrón (`.c`, líneas 126–134):

```c
size_t mem_pool_blocks_free(const mem_pool *pool)
{
    return pool == NULL ? 0 : pool->blocks_free;
}
```

El `const mem_pool *pool` promete que la función **no modifica** el pool (solo
lo consulta). Y el `pool == NULL ? 0 : ...` es la defensa habitual: si te pasan
un puntero nulo, no revientes; devuelve un valor neutro.

---

## Retos

Recuerda el [workflow de retos](./00-guia-del-tutorial.md#workflow-de-un-reto):
haz el cambio, verifica, y vuelve al código de referencia con `git checkout`.
Intenta cada reto **antes** de abrir la solución.

### Reto 1 — Leer y predecir 🐳

Sin compilar nada, solo con lo aprendido, responde para un pool creado con
`block_size = 4` y `block_count = 3`:

1. ¿Cuántos bytes devuelve `mem_pool_required_size(4, 3)`?
2. ¿Cuál es el tamaño **efectivo** de cada bloque?
3. Tras crear el pool y hacer tres `mem_pool_alloc` seguidos, ¿en qué orden
   (de dirección) salen los tres bloques?

<details>
<summary>Ver solución</summary>

1. **88 bytes.** El tamaño efectivo es 8 (ver punto 2), así que
   `required = POOL_HEADER_BYTES + eff × count = 64 + 8 × 3 = 88`.
2. **8 bytes.** Pediste 4, pero el mínimo es `POOL_ALIGN = 8` (un bloque libre
   debe poder guardar un puntero), y además se redondea a múltiplo de 8.
3. **En orden de dirección ascendente**: primero el bloque de menor dirección,
   luego el siguiente, etc. Porque `mem_pool_create` encadena la free-list
   recorriendo de la última posición a la primera (`for i = count..1`), lo que
   deja `free_head` apuntando al bloque **0**; y `alloc` va sacando siempre la
   cabeza.

Puedes comprobarlo tú mismo compilando este mini-programa (usa
`mem_pool_block_size` para el punto 2):

```c
#include "mem_pool.h"
#include <stdio.h>
int main(void) {
    printf("required(4,3) = %zu\n", mem_pool_required_size(4, 3));
    _Alignas(8) static unsigned char backing[256];
    mem_pool *p = mem_pool_create(backing, sizeof backing, 4, 3);
    printf("block_size efectivo = %zu\n", mem_pool_block_size(p));
    return 0;
}
```
Salida: `required(4,3) = 88` y `block_size efectivo = 8`.
</details>

### Reto 2 — Escribe un cliente y compílalo 🐳 (reto estrella)

Escribe tú, de cero, un programa en `practica/mi_prueba_pool.c` que:

1. Calcule con `mem_pool_required_size` el buffer para **4 bloques de 16
   bytes**, y reserve un `backing` **estático y alineado a 8**
   (`_Alignas(8) static uint8_t backing[...]`).
2. Cree el pool.
3. Imprima `mem_pool_blocks_free` en tres momentos: tras crear, tras hacer
   **3** `alloc`, y tras hacer **1** `free`.

Compílalo enlazando la implementación C del módulo (comando de la guía 00):

```bash
gcc -std=c11 -Wall -I modules/mem-pool/include \
    practica/mi_prueba_pool.c modules/mem-pool/impl-c/mem_pool.c \
    -o practica/mi_prueba_pool && ./practica/mi_prueba_pool
```

**Salida esperada:** los conteos de libres deben ser `4`, luego `1`, luego
`2`.

<details>
<summary>Ver solución completa</summary>

```c
/* practica/mi_prueba_pool.c */
#include "mem_pool.h"
#include <stdint.h>
#include <stdio.h>

int main(void)
{
    /* 1. Buffer estático alineado a 8, del tamaño exacto que pide el módulo. */
    size_t need = mem_pool_required_size(16, 4);
    printf("required_size(16,4) = %zu\n", need);   /* 128 */
    _Alignas(8) static uint8_t backing[512];       /* de sobra para 128 */

    /* 2. Crear el pool dentro del buffer. */
    mem_pool *pool = mem_pool_create(backing, sizeof backing, 16, 4);
    if (pool == NULL) {
        printf("create fallo\n");
        return 1;
    }

    /* 3. Consultar libres en cada momento. */
    printf("libres tras crear: %zu\n", mem_pool_blocks_free(pool));   /* 4 */

    void *a = mem_pool_alloc(pool);
    void *b = mem_pool_alloc(pool);
    void *c = mem_pool_alloc(pool);
    printf("libres tras 3 alloc: %zu\n", mem_pool_blocks_free(pool)); /* 1 */

    mem_pool_free(pool, b);
    printf("libres tras 1 free: %zu\n", mem_pool_blocks_free(pool));  /* 2 */

    (void)a; (void)c;  /* silenciar "variable sin usar" */
    return 0;
}
```

Salida real:
```
required_size(16,4) = 128
libres tras crear: 4
libres tras 3 alloc: 1
libres tras 1 free: 2
```

Lo que practicaste: incluir un header, reservar memoria estática alineada,
llamar a la API, y **compilar enlazando** tu `.c` con el `.c` del módulo. El
segundo archivo en el comando de `gcc` es imprescindible: aporta el código de
las funciones que llamas.
</details>

### Reto 3 — Modifica el módulo y re-verifica la paridad 🐳

Aprende el ciclo **modificar → verificar → revertir** sin romper el contrato.
En `modules/mem-pool/impl-c/mem_pool.c`:

1. Añade `#include <assert.h>` arriba.
2. Al principio de `mem_pool_alloc`, añade una comprobación de coherencia
   interna:
   ```c
   assert(pool == NULL || pool->blocks_free <= pool->block_count);
   ```
3. Corre el test de paridad y comprueba que sigue en **verde**:
   ```bash
   tools/run-parity-tests.sh mem-pool
   ```
4. Restaura el archivo de referencia:
   ```bash
   git checkout -- modules/mem-pool/impl-c/mem_pool.c
   ```

No tocaste el header ni la firma de ninguna función, así que la paridad se
mantiene: un `assert` solo verifica una invariante en tiempo de ejecución.

<details>
<summary>Ver salida esperada del paso 3</summary>

```
== parity_test mem-pool [impl=c] ==
OK: todos los casos pasaron [impl=c]
...
== parity_test mem-pool [impl=rust] ==
OK: todos los casos pasaron [impl=rust]
==================================================
OK: paridad verificada
```

Ambas implementaciones pasan: tu `assert` no cambió el comportamiento
observable, solo añadió una red de seguridad interna. Ese es exactamente el
tipo de cambio "seguro" que puedes hacer con confianza.
</details>

---

## Qué te llevas de aquí

- Un **puntero** es una dirección; su tipo decide cuánto avanza al sumarle.
- Una **free-list intrusiva** encadena bloques libres usando su propia memoria.
- C te da control total y **ninguna red de seguridad**: overflow silencioso,
  punteros torcidos, doble free — por eso el código valida a mano.
- Sabes **compilar y enlazar** un programa contra un módulo del repo.

En la [Lección 02](./02-rust-fundamentos-con-mem-pool.md) veremos exactamente
este mismo módulo escrito en Rust: qué hace el compilador para evitarte estos
errores, y por qué aun así necesita bloques `unsafe` para la aritmética de
punteros.
