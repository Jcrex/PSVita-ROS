#!/usr/bin/env python3
import argparse
import pathlib
import xml.etree.ElementTree as ET

import trimesh


def main():
    ap = argparse.ArgumentParser(description="Convierte mallas DAE referenciadas por un URDF a OBJ para Blender 5.2+")
    ap.add_argument("urdf")
    ap.add_argument("--salida", required=True)
    ap.add_argument("--paquete", action="append", default=[])
    ap.add_argument("--mallas", required=True)
    args = ap.parse_args()
    paquetes = dict(v.split("=", 1) for v in args.paquete)
    origen = pathlib.Path(args.urdf).resolve()
    destino_mallas = pathlib.Path(args.mallas).resolve()
    tree = ET.parse(origen)
    convertidas = 0
    for mesh in tree.getroot().iter("mesh"):
        nombre = mesh.get("filename", "")
        if not nombre.lower().endswith(".dae"):
            continue
        if nombre.startswith("package://"):
            paquete, _, relativo = nombre[len("package://"):].partition("/")
            ruta = pathlib.Path(paquetes[paquete]) / relativo
            salida = destino_mallas / paquete / relativo
        else:
            ruta = (origen.parent / nombre).resolve()
            salida = destino_mallas / ruta.name
        salida = salida.with_suffix(".obj")
        salida.parent.mkdir(parents=True, exist_ok=True)
        escena = trimesh.load(ruta, force="scene", process=False)
        modelo = escena.to_mesh()
        modelo.export(salida, file_type="obj", include_texture=False)
        mesh.set("filename", salida.as_uri())
        convertidas += 1
    salida_urdf = pathlib.Path(args.salida)
    tree.write(salida_urdf, encoding="utf-8", xml_declaration=True)
    print(f"{convertidas} mallas DAE convertidas; URDF: {salida_urdf}")


if __name__ == "__main__":
    main()
