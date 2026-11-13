#!/usr/bin/env python3
"""Comprueba enlaces y rutas citadas en la documentación del repo (ADR 0014 §6).

Dos comprobaciones:

(a) **Enlaces Markdown relativos** `[texto](ruta)` de todo `*.md` versionado,
    salvo `archivo/` (es historia: sus rutas pueden quedar rotas) y `godot/rclgd/`.
    Se ignoran URLs (`http:`, `mailto:`…), anclas solas (`#x`) y los bloques de
    código. La ruta se resuelve desde la carpeta del fichero.

(b) **Rutas entre comillas invertidas** que empiezan por `docs/ godot/ tools/
    modules/ skills/ docker/ archivo/`, con o sin `:línea` (`docs/18-…md:335`,
    `godot/ros2_vita/SCsub:32-36`), en los ficheros «vivos» de la regla R-1/R-5
    (`docs/ia/organizacion/decision-fable.md` §0): se excluyen los registros, que
    conservan las rutas de su fecha. Se resuelven desde la raíz del repo y, si
    llevan línea, se comprueba que el fichero tenga al menos esas líneas.
    Las menciones abreviadas (`docs/18`, `docs/18:335`, `docs/adr/0008`, `docs/rust/03`)
    se resuelven por número en `docs/…` o en `archivo/docs/…` (R-2: no se reescriben).
    Se ignoran las rutas con comodines de plantilla (`<x>`, `$VAR`, `NN`, `…`, `24+`)
    y los rangos o listas de números (`docs/rust/00-02`, `docs/tutorial/00,07`).
    Los `*` y `{a,b}` se expanden como en el shell.

Uso:
    python3 tools/check-doc-links.py                        # lista los rotos; sale con 1 si hay
    python3 tools/check-doc-links.py > /tmp/antes.txt       # guardar una línea base
    python3 tools/check-doc-links.py --baseline /tmp/antes.txt   # solo los rotos NUEVOS

Formato de salida (una línea por roto, separada por tabuladores):
    fichero:línea <TAB> tipo (md|ruta) <TAB> referencia <TAB> motivo
Para comparar con la línea base se ignora el número de línea del fichero de
origen (cambia al editar), así que la clave es fichero + tipo + referencia + motivo.
"""
import argparse
import glob
import os
import re
import subprocess
import sys

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))

# Registros (R-1): conservan las rutas de su fecha; no se les aplica (b).
REGISTROS = re.compile(
    r'^(archivo/|web/|godot/rclgd/|docs/bitacora/|docs/informes/|'
    r'docs/ia/(workshops/posts|auditoria|revision-kimi|organizacion)/)')
# Extensiones de los ficheros «vivos» (R-5)
VIVOS_PATRONES = ['*.md', '*.sh', '*.fish', '*.py', '*.gd', '*.cpp', '*.h', '*.c', '*.toml',
                  '*.txt', '*.cfg', '*SCsub', '.gitignore', '.dockerignore']

ENLACE_MD = re.compile(r'(?<!!)\[[^\]\n]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)')
IMAGEN_MD = re.compile(r'!\[[^\]\n]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)')
RUTA_CITADA = re.compile(r'`((?:docs|godot|tools|modules|skills|docker|archivo)/[^`\s]*)`')
SUFIJO_LINEA = re.compile(r':(\d+)(?:[-–,]\s*(\d+))*$')
ABREVIADA = re.compile(r'^((?:archivo/)?docs(?:/[a-z-]+)?)/(\d{2,4}[a-z]?)$')
PLANTILLA = re.compile(r'[<>$…+]|\.\.\.|\bNN\b|AAAA|XXX|/X/|\bN\.|\bN-'
                       r'|/\d{2}[-–]\d{2}$|/\d{2},\d{2}')   # rangos y listas: «docs/rust/00-02»


def git_ls(*patrones):
    salida = subprocess.run(['git', '-C', RAIZ, 'ls-files', '-z', '--', *patrones],
                            capture_output=True, text=True, check=True).stdout
    return [f for f in salida.split('\0') if f]


def lineas_de(ruta, cache={}):
    """Número de líneas de un fichero (con caché); None si no es legible como texto."""
    if ruta not in cache:
        try:
            with open(ruta, 'rb') as fh:
                cache[ruta] = fh.read().count(b'\n') + 1
        except OSError:
            cache[ruta] = None
    return cache[ruta]


def expandir_llaves(patron):
    """`a/{b,c}.md` -> ['a/b.md', 'a/c.md'] (una sola pareja de llaves anidable)."""
    m = re.search(r'\{([^{}]*)\}', patron)
    if not m:
        return [patron]
    res = []
    for alt in m.group(1).split(','):
        res += expandir_llaves(patron[:m.start()] + alt + patron[m.end():])
    return res


def existe(ruta_abs):
    if any(c in ruta_abs for c in '*?['):
        return bool(glob.glob(ruta_abs, recursive=True))
    return os.path.lexists(ruta_abs)


def quitar_codigo(texto):
    """Sustituye los bloques ``` por líneas vacías (conserva la numeración)."""
    fuera = []
    dentro = False
    for linea in texto.split('\n'):
        if linea.lstrip().startswith(('```', '~~~')):
            dentro = not dentro
            fuera.append('')
            continue
        fuera.append('' if dentro else linea)
    return fuera


def comprobar_md(fichero, rotos):
    try:
        texto = open(os.path.join(RAIZ, fichero), encoding='utf-8', errors='replace').read()
    except OSError:
        return
    base = os.path.dirname(os.path.join(RAIZ, fichero))
    for n, linea in enumerate(quitar_codigo(texto), 1):
        linea = re.sub(r'`[^`]*`', '', linea)       # el código en línea no es un enlace
        for rx in (ENLACE_MD, IMAGEN_MD):
            for m in rx.finditer(linea):
                destino = m.group(1)
                if re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*:', destino) or destino.startswith(('#', '/')):
                    continue
                camino = destino.split('#', 1)[0].split('?', 1)[0]
                if not camino:
                    continue
                from urllib.parse import unquote
                if not existe(os.path.normpath(os.path.join(base, unquote(camino)))):
                    rotos.append((fichero, n, 'md', destino, 'no existe'))


def resolver_abreviada(ruta):
    """`docs/18` o `docs/adr/0008` -> fichero real (en docs/ o archivo/docs/) o None."""
    m = ABREVIADA.match(ruta)
    if not m:
        return None
    carpeta, num = m.group(1), m.group(2)
    carpetas = [carpeta] if carpeta.startswith('archivo/') else [carpeta, 'archivo/' + carpeta]
    for c in carpetas:
        hallados = sorted(glob.glob(os.path.join(RAIZ, c, num + '-*.md')))
        if hallados:
            return hallados[0]
    return None


def comprobar_rutas(fichero, rotos):
    try:
        texto = open(os.path.join(RAIZ, fichero), encoding='utf-8', errors='replace').read()
    except OSError:
        return
    for n, linea in enumerate(texto.split('\n'), 1):
        for m in RUTA_CITADA.finditer(linea):
            cita = m.group(1).rstrip('.,;:)')
            if PLANTILLA.search(cita):
                continue
            ruta, desde = cita, None
            ms = SUFIJO_LINEA.search(cita)
            if ms:
                ruta = cita[:ms.start()]
                numeros = [int(x) for x in re.findall(r'\d+', ms.group(0))]
                desde = max(numeros)
            ruta = ruta.split('#', 1)[0].split('§', 1)[0].rstrip('/') or ruta
            candidatos = [os.path.join(RAIZ, r) for r in expandir_llaves(ruta)]
            for cand in candidatos:
                real = cand if existe(cand) else resolver_abreviada(os.path.relpath(cand, RAIZ))
                if real is None:
                    rotos.append((fichero, n, 'ruta', cita, 'no existe'))
                    continue
                if desde and os.path.isfile(real):
                    total = lineas_de(real)
                    if total is not None and desde > total:
                        rotos.append((fichero, n, 'ruta', cita,
                                      f'línea {desde} > {total} líneas'))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--baseline', help='fichero con una salida anterior: solo se listan los rotos nuevos')
    args = ap.parse_args()

    rotos = []
    for f in git_ls('*.md'):
        if f.startswith(('archivo/', 'godot/rclgd/')):
            continue
        comprobar_md(f, rotos)
    for f in git_ls(*VIVOS_PATRONES):
        if REGISTROS.match(f):
            continue
        comprobar_rutas(f, rotos)

    clave = lambda fich, tipo, ref, motivo: (fich, tipo, ref, motivo)   # sin nº de línea
    vistos = set()
    if args.baseline:
        with open(args.baseline, encoding='utf-8') as fh:
            for linea in fh:
                partes = linea.rstrip('\n').split('\t')
                if len(partes) == 4:
                    vistos.add(clave(partes[0].rsplit(':', 1)[0], *partes[1:]))

    nuevos = [r for r in rotos if clave(r[0], *r[2:]) not in vistos]
    for fich, n, tipo, ref, motivo in nuevos:
        print(f'{fich}:{n}\t{tipo}\t{ref}\t{motivo}')
    print(f'# {len(nuevos)} rotos' + (' nuevos' if args.baseline else '')
          + f' ({len(rotos)} en total)', file=sys.stderr)
    return 1 if nuevos else 0


if __name__ == '__main__':
    sys.exit(main())
