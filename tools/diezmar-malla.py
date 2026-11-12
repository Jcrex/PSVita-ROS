#!/usr/bin/env python3
import argparse
import pathlib

import trimesh


def main():
    ap = argparse.ArgumentParser(description="Reduce una malla a un número máximo de triángulos para Godot/Vita")
    ap.add_argument("entrada")
    ap.add_argument("salida")
    ap.add_argument("--tris", type=int, required=True)
    args = ap.parse_args()
    if args.tris < 4:
        raise SystemExit("--tris debe ser >= 4")
    malla = trimesh.load(args.entrada, force="mesh", process=False)
    if len(malla.faces) > args.tris:
        malla = malla.simplify_quadric_decimation(face_count=args.tris)
    # Sin esto el OBJ arrastra los vértices originales sin usar (RB-KAIROS+: 8,8 MB para 1 201 caras).
    malla.remove_unreferenced_vertices()
    salida = pathlib.Path(args.salida)
    salida.parent.mkdir(parents=True, exist_ok=True)
    malla.export(salida, file_type="obj", include_texture=False)
    print(f"{salida}: {len(malla.faces)} triángulos")


if __name__ == "__main__":
    main()
