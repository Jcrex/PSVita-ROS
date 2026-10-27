#!/usr/bin/env python3
"""Comprueba que los símbolos externos de nuestras bibliotecas existen en la
tabla de imports del loader de godot4-vita (platform/vita/loader/default_dynlib.c).

Por qué: godot4-vita enlaza `libgodot.so` con `-nostdlib -shared
-Wl,--unresolved-symbols=ignore-all`; TODO símbolo no definido (libc, SDK de Sony,
helpers del compilador) lo resuelve el loader en tiempo de carga con esa tabla, y
`verify_runtime.py` rechaza el runtime si falta alguno. Si nuestras bibliotecas
(XRCE, Micro-CDR, módulos duales C y Rust) piden algo que no está en la tabla,
hay que añadirlo a la tabla del loader (o evitarlo en el código).

Uso (en el PC, con las bibliotecas CROSS-COMPILADAS para la Vita):
    tools/check-vita-imports.py --dynlib ~/godot4-vita/platform/vita/loader/default_dynlib.c \
        --nm "$VITASDK/bin/arm-vita-eabi-nm" libmicroxrcedds_client.a libmicrocdr.a libvita_modules_rust.a

Uso preliminar en la laptop (nm del host: solo aproxima, p. ej. glibc ≠ newlib):
    tools/check-vita-imports.py --dynlib ... ARCHIVO.a ...
Salida: por archivo, los símbolos que faltan. Código de salida = nº de faltantes.
"""
import argparse
import re
import subprocess
import sys

# Símbolos que NO son imports reales (los añade el enlazador o el host)
IGNORE = re.compile(
    r"^(_GLOBAL_OFFSET_TABLE_|__stack_chk_.*|_ITM_.*|__gmon_start__|__cxa_finalize|"
    r"_DYNAMIC|__dso_handle|_fini|_init|__bss_start|_edata|_end)$"
)


def table_names(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    return set(re.findall(r'\{\s*"([^"\n]+)"\s*,', text))


def undefined(nm, path):
    out = subprocess.run([nm, "-u", "--no-demangle", path], capture_output=True, text=True)
    syms = set()
    for line in out.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[-2] in ("U", "w", "v"):
            if parts[-2] == "U":  # los débiles (w) no son obligatorios
                syms.add(parts[-1].split("@")[0])
    return syms


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dynlib", required=True, help="loader/default_dynlib.c de godot4-vita")
    ap.add_argument("--nm", default="nm", help="nm a usar (arm-vita-eabi-nm en el PC)")
    ap.add_argument("--provided", action="append", default=[],
                    help="fichero .a/.o cuyas definiciones cuentan como disponibles (p. ej. el propio motor)")
    ap.add_argument("files", nargs="+")
    args = ap.parse_args()

    table = table_names(args.dynlib)
    print(f"tabla del loader: {len(table)} símbolos", file=sys.stderr)

    # Lo que definen nuestros propios archivos juntos no es un import
    defined = set()
    for f in args.files + args.provided:
        out = subprocess.run([args.nm, "--defined-only", "--no-demangle", f], capture_output=True, text=True)
        for line in out.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 3 and parts[-2] in "TtDdBbRrWwVvSsGg":
                defined.add(parts[-1])

    missing_total = 0
    for f in args.files:
        miss = sorted(s for s in undefined(args.nm, f)
                      if s not in table and s not in defined and not IGNORE.match(s))
        print(f"\n== {f}: {len(miss)} imports que NO están en la tabla del loader")
        for s in miss:
            print("   ", s)
        missing_total += len(miss)
    sys.exit(min(missing_total, 125))


if __name__ == "__main__":
    main()
