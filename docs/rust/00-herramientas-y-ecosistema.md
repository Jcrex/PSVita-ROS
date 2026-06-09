# Rust 00 — Herramientas y ecosistema (lo que usa este proyecto)

> Serie de aprendizaje de Rust del proyecto PS Vita ↔ ROS2. No es un curso
> general: explica **exactamente** lo que el código del repo usa, con
> referencias a los archivos reales. Para profundizar: [El libro de Rust en
> español](https://book.rustlang-es.org/) y [The Rust Book](https://doc.rust-lang.org/book/).

## Qué es Rust y por qué está aquí

Rust es un lenguaje compilado, sin recolector de basura y sin runtime
obligatorio, que compite con C/C++ en rendimiento pero verifica en
compilación la seguridad de memoria (no hay use-after-free, dobles free ni
data races en código "safe"). En este proyecto **no sustituye a C**: cada
módulo de bajo nivel tiene ambas implementaciones tras el mismo header C
(`docs/03-estrategia-dual-rust-cpp.md`), y C/C++ es el respaldo permanente.

## Las piezas del ecosistema

| Herramienta | Qué es | Equivalente mental |
|---|---|---|
| `rustc` | El compilador. Casi nunca se invoca a mano. | `gcc` |
| **Cargo** | Build system + gestor de dependencias. Lee `Cargo.toml`. | CMake + pip |
| `rustup` | Instala/gestiona versiones del compilador ("toolchains"). | `vdpm` de VitaSDK |
| **crate** | Unidad de compilación: una biblioteca o un binario. | una lib `.a` o un ejecutable |
| `Cargo.toml` | Manifiesto del crate: nombre, edición, dependencias, perfiles. | `CMakeLists.txt` |
| `Cargo.lock` | Versiones exactas resueltas (se commitea en apps). | lockfile de npm |
| **edición** | Conjunto de reglas de sintaxis (2015/2018/2021/2024). El repo usa **2024**. | `-std=c11` vs `-std=c23` |

## Comandos que este repo usa

```bash
cargo build --release        # compila el crate (perfil optimizado)
cargo rustc --release --crate-type staticlib   # pide ADEMÁS un .a estilo C
cargo +nightly rustc ... -Zbuild-std=std,panic_abort \
      --target armv7-sony-vita-newlibeabihf    # cross-compilar a la Vita
```

- `--release`: perfil optimizado (sin él compila en `dev`, con asserts de
  overflow activados — ver `docs/rust/01`, overflow).
- `cargo rustc` (en vez de `cargo build`) permite pasar opciones extra al
  compilador; lo usamos para `--crate-type staticlib` (ver más abajo).
- `+nightly`: usa el toolchain *nightly* (inestable). El target de la Vita
  es **tier 3**: no hay binarios precompilados de la biblioteca estándar,
  así que `-Zbuild-std` la compila desde el código fuente (necesita el
  componente `rust-src`: `rustup component add rust-src`).

## `crate-type`: rlib vs staticlib (decisión clave del repo)

- **`rlib`**: formato nativo de Rust. Solo sirve para que *otros crates
  Rust* dependan de él. Es lo que declaran nuestros módulos
  (`modules/*/impl-rust/Cargo.toml`).
- **`staticlib`**: un `.a` clásico que gcc/CMake enlazan sin saber que
  dentro hay Rust. Contiene además una copia de `core`/`std`, por lo que
  **un binario solo puede enlazar UN staticlib de Rust**.

Por eso el repo sigue esta regla (aprendida al integrar `microros-transport`):
los crates de módulo son `rlib`, y el `.a` se genera explícitamente con
`cargo rustc --crate-type staticlib` solo en dos sitios:

1. Tests de paridad de cada módulo (`tools/run-parity-tests.sh`).
2. El **crate paraguas** `vita-app/rust-modules/`, que junta los tres
   módulos en un único `libvita_modules_rust.a` para la app.

Si se declarara `staticlib` en el `Cargo.toml` de un módulo, cargo
intentaría producir el `.a` también cuando otro crate lo usa como
dependencia, y fallaría exigiendo un `panic_handler` propio (lo vivimos:
ver mensaje de error documentado en `modules/microros-transport/README.md`).

## `cargo-vita` y el target de la Vita

- Target: `armv7-sony-vita-newlibeabihf` (tier 3, requiere nightly).
  Desglose del nombre: ARMv7 + Sony Vita + newlib (la libc embebida de
  VitaSDK) + EABI hard-float.
- [`cargo-vita`](https://crates.io/crates/cargo-vita) (`cargo install cargo-vita`)
  automatiza el empaquetado `.vpk` de apps 100% Rust. En este proyecto las
  apps son C con módulos Rust enlazados, así que `cargo-vita` solo se usa
  si se quiere el camino "todo Rust" (ADR 0003).

## Cómo se compila Rust en la laptop (sin instalar Rust)

Regla del proyecto: la laptop no instala toolchains. El runner de paridad
(`tools/run-parity-tests.sh`) usa la imagen Docker `rust:1-slim` montando el
repo y dejando los artefactos en `modules/*/impl-rust/target/` (ignorado por
git). Si `cargo` existe (en el PC), se usa directamente.

## Dónde mirar código

| Concepto | Archivo |
|---|---|
| Cargo.toml comentado línea a línea | `modules/mem-pool/impl-rust/Cargo.toml` |
| Dependencia entre crates propios | `modules/microros-transport/impl-rust/Cargo.toml` |
| Crate paraguas (un solo .a) | `vita-app/rust-modules/` |
| Features (`standalone`) | los tres `Cargo.toml` de módulos |
