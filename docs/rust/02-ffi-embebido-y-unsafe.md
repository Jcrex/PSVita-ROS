# Rust 02 — FFI, embebido y `unsafe`: la frontera con C

> La parte más específica (y más valiosa) de lo aprendido: cómo Rust
> convive con C y con una consola sin sistema operativo "completo".

## `#![no_std]`: renunciar a la biblioteca estándar

`std` asume un OS con hilos, ficheros, heap, red... La Vita tiene newlib,
no glibc, y nuestros módulos deben enlazarse dentro de un binario C sin
arrastrar runtime. `#![no_std]` deja solo **`core`**: tipos básicos,
`Option`, iteradores, punteros — todo lo que no necesita OS ni heap.
Consecuencias visibles en el repo:

- No hay `println!` (los tests de paridad son C y usan `printf`).
- No hay `Vec`/`String`/`Box` (nada de heap; por eso `mem-pool` recibe el
  buffer del llamador).
- Hay que aportar un `panic_handler` (abajo).

## `unsafe`: el contrato explícito

En Rust, las operaciones que el compilador no puede verificar (desreferenciar
punteros crudos, llamar funciones FFI, acceder a estado global mutable)
solo compilan dentro de un bloque `unsafe { ... }`. **No desactiva ninguna
comprobación en runtime**: marca la región donde la garantía pasa del
compilador a nosotros, exactamente el estado permanente de cualquier
archivo C. La disciplina del repo: bloques `unsafe` pequeños, con la
invariante anotada (busca los comentarios `// SAFETY:`).

## Punteros crudos: `*const T` y `*mut T`

Son los punteros de C (`const T*` / `T*`): sin lifetimes, pueden ser NULL,
aritmética con `.add(n)` / `.offset_from()`. Operaciones del repo:

```rust
ptr.is_null()                  // ptr == NULL
ptr::null_mut()                // NULL tipado
(*pool).blocks_free -= 1;      // pool->blocks_free-- (en unsafe)
blk as *mut *mut u8            // reinterpretar: bloque -> puntero a puntero
backing as usize & 7           // chequear alineación
```

`mem-pool` es el tour completo: free-list intrusiva con punteros crudos,
idéntica a la versión C pero con cada acceso marcado.

## `extern "C"` + `#[unsafe(no_mangle)]`: exportar hacia C

```rust
#[unsafe(no_mangle)]                     // conservar el nombre del símbolo
pub extern "C" fn net_udp_init() -> i32  // convención de llamada de C
```

- Sin `no_mangle`, Rust "mangla" los nombres como C++ y el linker no los
  encuentra. Desde la edición 2024 se escribe `#[unsafe(no_mangle)]`:
  prometemos que el nombre no colisiona.
- `extern "C"` fija la convención de llamada (cómo viajan los argumentos).
- Con ambos, el `.a` generado expone `net_udp_init` indistinguible de la
  versión C — es **todo** el truco de la estrategia dual.

## `unsafe extern "C" { ... }`: importar desde C

La dirección contraria: declarar símbolos ajenos para llamarlos desde Rust.
`net-udp` lo hace dos veces (módulos `sys`): contra la libc de Linux
(`socket`, `connect`, `recv`, `__errno_location`...) y contra los stubs
`sceNet*` de VitaSDK. Si la firma declarada miente, es UB — como en C.
No usamos el crate `libc` a propósito: ver qué hay debajo es parte del
objetivo de aprendizaje (y evita dependencias de red en el build).

## `#[repr(C)]`: layout de memoria compatible

Rust reordena campos de structs para optimizar; C no. Todo struct que cruza
la frontera lleva `#[repr(C)]` para fijar el layout C: los `SockaddrIn`
replicados a mano, `MemPool`, `NetUdpSocket`. Bonus del repo: la aserción
de compilación

```rust
const _: () = assert!(core::mem::size_of::<MemPool>() <= 64);
```

rompe el build si la cabecera de control dejara de caber en los 64 bytes
que el contrato C reserva.

## `panic_handler` y `rust_eh_personality`

Un binario no_std necesita exactamente **un** `#[panic_handler]` (a dónde
saltar si ocurre lo imposible; el nuestro: `loop {}`). Además, `core`
precompilado referencia el símbolo `rust_eh_personality` (del unwinding)
aunque compilemos con `panic = "abort"`; se satisface con un stub vacío.
Ambos viven tras la feature `standalone` de cada módulo, y el crate
paraguas (`vita-app/rust-modules`) los aporta una sola vez para la app —
la historia completa está en los comentarios de los `Cargo.toml`.

## Estado global mutable sin malloc: `UnsafeCell` + `Sync`

C: `static struct net_udp_socket g_sockets[4];` y a correr. Rust prohíbe
mutar estáticas a la ligera porque dos hilos podrían hacerlo a la vez (UB).
El patrón del repo:

```rust
struct ModuleState { sockets: UnsafeCell<[NetUdpSocket; 4]> }
unsafe impl Sync for ModuleState {}   // promesa: "se usa mono-hilo"
static STATE: ModuleState = ...;
```

`UnsafeCell` es la única vía legal de "mutabilidad interior"; `unsafe impl
Sync` es nuestra promesa escrita de que la app de la Vita llama a estos
módulos desde un solo hilo. La versión C asume lo mismo *sin decirlo*;
en Rust la suposición queda en el código y se ve en el diff si algún día
cambia.

## Componer crates y el problema del staticlib único

`microros_transport_rust` depende de `net_udp_rust` (dependencia de ruta) y
llama a sus funciones como Rust normal — aunque sean `extern "C"`. El
binario "todo Rust" se forma con el crate paraguas que re-exporta los tres
módulos (`pub use`) para que el linker conserve sus símbolos `no_mangle`.
Regla aprendida: **un binario, un staticlib de Rust** (cada `.a` arrastra
su copia de `core`; dos copias = símbolos duplicados).

## Glosario C ↔ Rust del repo

| C | Rust |
|---|---|
| `void*` | `*mut core::ffi::c_void` |
| `uint8_t* / size_t` | `*mut u8` / `usize` |
| `NULL` | `ptr::null_mut()` / `.is_null()` |
| `p->campo` | `(*p).campo` (en `unsafe`) |
| `#ifdef __vita__` | `#[cfg(target_os = "vita")]` |
| `#define` flag de build | feature en `Cargo.toml` + `#[cfg(feature)]` |
| `static` (privado) | sin `pub` |
| variable global mutable | `static` + `UnsafeCell` + `unsafe impl Sync` |
| valor centinela (-1, NULL) | `Option<T>` |
| `switch` | `match` (exhaustivo) |
| cast implícito | `as` explícito |
| header `.h` | el propio header sigue siendo la verdad (estrategia dual) |
