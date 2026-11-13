#!/usr/bin/env python3
"""generar-lod-vita.py — variantes de pocos triángulos de los OBJ del mundo de las plantillas (perfil «Vita ligero»).

Uso (desde la raíz del repo; necesita `numpy` y `pillow`):
    python3 tools/generar-lod-vita.py                 # regenera todos los `*_vita.obj` y anota mundo.tscn
    python3 tools/generar-lod-vita.py --min-tris 250 --objetivo 0.35   # los valores por defecto

Qué hace con cada modelo de `godot/plantillas/mundo/mundo.tscn` (nodos `asset_mundo.gd`) que pasa de `--min-tris`
triángulos:
 1. Lee el OBJ y agrupa las caras por COLOR: el `Kd` de su material o, si el material tiene textura (los
    «colormap» de Kenney), el texel bajo el centro de la cara. Los kits de Kenney pintan cada cara de un color
    plano, así que el grupo conserva el aspecto.
 2. Reduce la malla por AGRUPAMIENTO DE VÉRTICES en rejilla (los vértices de cada celda se funden en su media y
    las caras que degeneran desaparecen). Es tosco pero robusto: no depende de que la malla sea cerrada ni
    soldada (las de Kenney son piezas sueltas) y nunca saca vértices fuera del modelo. El colapso de aristas
    (pyfqmr) se probó y se descartó: por grupos de color rompía paredes enteras.
 3. Escribe `<modelo>_vita.obj` junto al original, con los mismos materiales (mismo `.mtl`, misma textura): cada
    cara usa UNA coordenada de textura constante (su color), y no sube el número de superficies (draws).
 4. Escribe la propiedad `modelo_vita` del nodo en mundo.tscn. `asset_mundo.gd` la usa solo con el perfil ligero.
    Desde el 2026-11-13 la escena es la fuente de verdad del mundo (doc 35); antes esto anotaba `assets.json`.
    Con el editor de Godot cerrado (si no, al guardar la escena pisaría el cambio).

El 3D GXM de la Vita no tiene LOD de malla (rasterizer_scene_gxm_vita.inc: «this backend has no mesh LOD»), así
que el LOD se hornea aquí, en el PC (misma idea que el ADR 0009 para los URDF).
"""
import argparse
import pathlib
import re

import numpy as np
from PIL import Image

RAIZ = pathlib.Path(__file__).resolve().parent.parent
MUNDO = RAIZ / "godot" / "plantillas" / "mundo"


def leer_mtl(ruta: pathlib.Path) -> dict:
    """nombre -> {"kd": (r, g, b), "tex": Image | None}"""
    mats, actual = {}, None
    if not ruta.exists():
        return mats
    for linea in ruta.read_text(errors="ignore").splitlines():
        p = linea.split()
        if not p:
            continue
        if p[0] == "newmtl":
            actual = p[1]
            mats[actual] = {"kd": (1.0, 1.0, 1.0), "tex": None}
        elif p[0] == "Kd" and actual:
            mats[actual]["kd"] = tuple(float(x) for x in p[1:4])
        elif p[0] == "map_Kd" and actual:
            tex = ruta.parent / p[-1]
            if tex.exists():
                mats[actual]["tex"] = Image.open(tex).convert("RGB")
    return mats


def leer_obj(ruta: pathlib.Path):
    v, vt, caras, mtllib = [], [], [], None
    material = ""
    for linea in ruta.read_text(errors="ignore").splitlines():
        p = linea.split()
        if not p:
            continue
        if p[0] == "v":
            v.append([float(x) for x in p[1:4]])
        elif p[0] == "vt":
            vt.append([float(p[1]), float(p[2])])
        elif p[0] == "usemtl":
            material = p[1]
        elif p[0] == "mtllib":
            mtllib = p[1]
        elif p[0] == "f":
            idx = []
            for tok in p[1:]:
                partes = tok.split("/")
                iv = int(partes[0])
                it = int(partes[1]) if len(partes) > 1 and partes[1] else 0
                idx.append((iv - 1 if iv > 0 else len(v) + iv, it - 1 if it > 0 else (len(vt) + it if it < 0 else -1)))
            for k in range(1, len(idx) - 1):   # abanico: triangula polígonos
                caras.append((material, idx[0], idx[k], idx[k + 1]))
    return np.array(v, dtype=np.float64), np.array(vt, dtype=np.float64).reshape(-1, 2), caras, mtllib


def color_cara(cara, vt, mats):
    material, a, b, c = cara
    m = mats.get(material)
    if m is None:
        return (material, 255, 255, 255, -1)
    if m["tex"] is not None and a[1] >= 0 and len(vt):
        uv = (vt[a[1]] + vt[b[1]] + vt[c[1]]) / 3.0
        ancho, alto = m["tex"].size
        x = min(ancho - 1, max(0, int(uv[0] % 1.0 * ancho)))
        y = min(alto - 1, max(0, int((1.0 - uv[1] % 1.0) * alto)))
        r, g, bb = m["tex"].getpixel((x, y))
        return (material, r, g, bb, a[1])   # a[1] = una vt representativa de ese color
    kd = m["kd"]
    return (material, int(kd[0] * 255), int(kd[1] * 255), int(kd[2] * 255), -1)


def agrupar_vertices(v, tris, celda):
    """Agrupamiento de vértices en rejilla: todos los vértices de una celda se funden en su media.

    Devuelve (vértices nuevos, triángulos, índice de la cara original de cada triángulo que sobrevive). Las caras que
    degeneran (dos vértices en la misma celda) desaparecen y las repetidas se quedan en una.
    """
    claves = np.floor(v / celda).astype(np.int64)
    _, inv, cuenta = np.unique(claves, axis=0, return_inverse=True, return_counts=True)
    inv = inv.reshape(-1)
    nv = np.zeros((len(cuenta), 3))
    np.add.at(nv, inv, v)
    nv /= cuenta[:, None]
    t = inv[tris]
    vivas = (t[:, 0] != t[:, 1]) & (t[:, 1] != t[:, 2]) & (t[:, 0] != t[:, 2])
    indices = np.nonzero(vivas)[0]
    t = t[vivas]
    _, unicas = np.unique(np.sort(t, axis=1), axis=0, return_index=True)   # misma terna = misma cara (o su reverso)
    unicas.sort()
    return nv, t[unicas], indices[unicas]


def procesar(ruta: pathlib.Path, salida: pathlib.Path, fraccion: float) -> tuple[int, int]:
    v, vt, caras, mtllib = leer_obj(ruta)
    mats = leer_mtl(ruta.parent / mtllib) if mtllib else {}
    tris = np.array([[c[1][0], c[2][0], c[3][0]] for c in caras], dtype=np.int64)
    # Búsqueda de la celda: la más pequeña (más detalle) que deja como mucho `fraccion` de los triángulos.
    diagonal = float(np.linalg.norm(v.max(axis=0) - v.min(axis=0)))
    mejor = None
    for divisor in (200, 150, 120, 100, 80, 64, 50, 40, 32, 26, 20, 16, 12, 10, 8):
        nv, nt, origen = agrupar_vertices(v, tris, diagonal / divisor)
        mejor = (nv, nt, origen)
        if len(nt) <= len(tris) * fraccion:
            break
    nv, nt, origen = mejor
    lineas = [f"# LOD «Vita ligero» de {ruta.name}; generado por tools/generar-lod-vita.py (no editar a mano)"]
    if mtllib:
        lineas.append(f"mtllib {mtllib}")
    for p in nv:
        lineas.append(f"v {p[0]:.5f} {p[1]:.5f} {p[2]:.5f}")
    # Cada cara conserva el color de su cara original: una `vt` por color (centro de la cara en la textura).
    vts, por_material = {}, {}
    for tri, i in zip(nt, origen):
        material, r, g, b, _ = color_cara(caras[i], vt, mats)
        uv = None
        m = mats.get(material)
        if m is not None and m["tex"] is not None and caras[i][1][1] >= 0:
            c = (vt[caras[i][1][1]] + vt[caras[i][2][1]] + vt[caras[i][3][1]]) / 3.0
            uv = vts.setdefault((material, r, g, b), (len(vts) + 1, c))[0]
        por_material.setdefault(material, []).append((tri, uv))
    for (_m, _r, _g, _b), (_i, c) in sorted(vts.items(), key=lambda kv: kv[1][0]):
        lineas.append(f"vt {c[0]:.6f} {c[1]:.6f}")
    n_vn = 0
    for material in sorted(por_material):   # un `usemtl` por material = una superficie (un draw) por material
        if material:
            lineas.append(f"usemtl {material}")
        for tri, uv in por_material[material]:
            # Normal plana por triángulo (los kits de Kenney son de caras planas).
            n = np.cross(nv[tri[1]] - nv[tri[0]], nv[tri[2]] - nv[tri[0]])
            largo = np.linalg.norm(n)
            n = n / largo if largo > 1e-12 else np.array([0.0, 1.0, 0.0])
            lineas.append(f"vn {n[0]:.4f} {n[1]:.4f} {n[2]:.4f}")
            n_vn += 1
            t = str(uv) if uv is not None else ""
            lineas.append(f"f {tri[0] + 1}/{t}/{n_vn} {tri[1] + 1}/{t}/{n_vn} {tri[2] + 1}/{t}/{n_vn}")
    salida.write_text("\n".join(lineas) + "\n")
    return len(caras), len(nt)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--min-tris", type=int, default=250, help="solo modelos con más triángulos que esto")
    ap.add_argument("--objetivo", type=float, default=0.35, help="fracción máxima de triángulos que se conserva")
    args = ap.parse_args()
    ruta_tscn = MUNDO / "mundo.tscn"
    texto = ruta_tscn.read_text()
    # La escena se edita como texto, sección a sección ("[node …]" y sus propiedades), para no tocar nada más.
    secciones = re.split(r"(?m)^(?=\[)", texto)
    hechos = {}
    for sec in secciones:
        m = re.search(r'(?m)^modelo = "([^"]*)"$', sec)
        if not m:
            continue
        modelo = m.group(1)
        l = re.search(r"(?m)^lod_vita = (-?[0-9.]+)$", sec)
        lod = float(l.group(1)) if l else 0.0
        # lod_vita < 0 en el nodo = este modelo no se reduce (p. ej. la persona: brazos y piernas finos que el
        # agrupamiento deja en hilos).
        if not modelo.endswith(".obj") or modelo in hechos or lod < 0:
            continue
        ruta = MUNDO / modelo.replace("res://comun/mundo/", "")
        n = sum(len(x.split()) - 3 for x in ruta.read_text(errors="ignore").splitlines() if x.startswith("f "))
        if n <= args.min_tris:
            continue
        salida = ruta.with_name(ruta.stem + "_vita.obj")
        # lod_vita = 0.2 en el nodo = otra fracción para ese modelo (edificios y coches, los más pesados).
        fraccion = lod if lod > 0 else args.objetivo
        antes, despues = procesar(ruta, salida, fraccion)
        hechos[modelo] = modelo[:-4] + "_vita.obj"
        print(f"{ruta.name}: {antes} -> {despues} triángulos ({salida.name})")
    nuevas = []
    for sec in secciones:
        m = re.search(r'(?m)^modelo = "([^"]*)"$', sec)
        if m:
            sec = re.sub(r'(?m)^modelo_vita = "[^"]*"\n', "", sec)
            l = re.search(r"(?m)^lod_vita = (-?[0-9.]+)$", sec)
            if m.group(1) in hechos and not (l and float(l.group(1)) < 0):
                sec = sec.replace(m.group(0), m.group(0) + f'\nmodelo_vita = "{hechos[m.group(1)]}"', 1)
        nuevas.append(sec)
    ruta_tscn.write_text("".join(nuevas))

if __name__ == "__main__":
    main()
