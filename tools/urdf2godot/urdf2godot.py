#!/usr/bin/env python3
"""URDF -> escena de Godot 4 (.tscn) con mallas diezmadas para la PS Vita (o para el PC).

Vía «preprocesar en el PC» de la LT4: la Vita no parsea XML ni STL; solo carga una escena con OBJ ya
reducidos. Los nombres de link y joint del URDF se conservan como nombres de nodo, para aplicar
/joint_states y publicar TF con los mismos nombres que ROS.

Estructura generada (todo lo que cuelga de RosFrame está en ejes de ROS, REP-103, Z arriba):

    <Robot> (Node3D, script urdf_robot.gd)
      RosFrame (Node3D: gira ROS -> Godot, ros = (-g.z, -g.x, g.y) como rclgd)
        Base (Node3D: pose odom -> link raíz; la mueve set_base_pose_ros)
          <link raíz> (Node3D) + visuales (MeshInstance3D)
            <joint> (Node3D, metadata urdf_*: tipo, eje, origen, límites)
              <link hijo> ...

Uso:
    tools/urdf2godot/urdf2godot.py robot.urdf --proyecto godot/g1-unitree --dir robot \
        --nombre g1_vita --tris 12000 [--paquete nombre=/ruta]

Requiere Blender >= 4.2 en el PATH (diezmado sin ventana). Python estándar, sin dependencias.
Formatos de malla: STL, OBJ, DAE (DAE depende del importador Collada de Blender). Primitivas URDF
box/cylinder/sphere -> BoxMesh/CylinderMesh/SphereMesh de Godot. Sin xacro (procesarlo antes con
`xacro robot.urdf.xacro > robot.urdf`). Sin colisiones ni inercias: modo solo visual/cinemático.
"""
import argparse
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

AQUI = os.path.dirname(os.path.abspath(__file__))

# Matriz que lleva un vector de ROS a Godot: g = (-ros.y, ros.z, -ros.x)  (inversa de rclgd)
ROS_A_GODOT = [[0, -1, 0], [0, 0, 1], [-1, 0, 0]]


def rpy_a_matriz(r, p, y):
    """URDF: R = Rz(yaw) * Ry(pitch) * Rx(roll) (ejes fijos)."""
    cr, sr, cp, sp, cy, sy = math.cos(r), math.sin(r), math.cos(p), math.sin(p), math.cos(y), math.sin(y)
    return [
        [cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr],
        [sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr],
        [-sp, cp * sr, cp * cr],
    ]


def leer_origen(elem):
    o = elem.find("origin") if elem is not None else None
    xyz = [float(v) for v in (o.get("xyz", "0 0 0") if o is not None else "0 0 0").split()]
    rpy = [float(v) for v in (o.get("rpy", "0 0 0") if o is not None else "0 0 0").split()]
    return rpy_a_matriz(*rpy), xyz


def num(v):
    s = f"{v:.6f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def t3d(m, xyz):
    """Transform3D de un .tscn: 9 valores de la base por filas y luego el origen."""
    vals = [m[i][j] for i in range(3) for j in range(3)] + list(xyz)
    return "Transform3D(" + ", ".join(num(v) for v in vals) + ")"


def nombre_nodo(s):
    return re.sub(r'[.:@/"%]', "_", s)


def resolver_malla(fichero, dir_urdf, paquetes):
    if fichero.startswith("package://"):
        pkg, _, resto = fichero[len("package://"):].partition("/")
        if pkg not in paquetes:
            raise SystemExit(f"falta --paquete {pkg}=/ruta para {fichero}")
        return os.path.join(paquetes[pkg], resto)
    if fichero.startswith("file://"):
        return fichero[len("file://"):]
    return os.path.join(dir_urdf, fichero)


def triangulos_stl(ruta):
    with open(ruta, "rb") as f:
        cab = f.read(5)
    if cab.lower() == b"solid":  # STL ASCII
        return sum(1 for ln in open(ruta, errors="ignore") if ln.strip().startswith("facet"))
    return (os.path.getsize(ruta) - 84) // 50


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("urdf")
    ap.add_argument("--proyecto", required=True, help="carpeta del proyecto Godot (la de project.godot)")
    ap.add_argument("--dir", default="robot", help="subcarpeta res:// para la escena y las mallas")
    ap.add_argument("--nombre", required=True, help="nombre de la escena y de la carpeta de mallas")
    ap.add_argument("--tris", type=int, default=12000, help="presupuesto total de triángulos")
    ap.add_argument("--min-tris", type=int, default=60, help="mínimo por malla")
    ap.add_argument("--paquete", action="append", default=[], help="nombre=/ruta para package://")
    ap.add_argument("--blender", default="blender")
    ap.add_argument("--sin-diezmar", action="store_true", help="reusar los OBJ ya generados")
    a = ap.parse_args()

    paquetes = dict(p.split("=", 1) for p in a.paquete)
    dir_urdf = os.path.dirname(os.path.abspath(a.urdf))
    raiz = ET.parse(a.urdf).getroot()

    materiales = {}
    for m in raiz.findall("material"):
        c = m.find("color")
        if c is not None:
            materiales[m.get("name")] = [float(v) for v in c.get("rgba").split()]

    links = {l.get("name"): l for l in raiz.findall("link")}
    joints = raiz.findall("joint")
    hijos = {}
    es_hijo = set()
    for j in joints:
        hijos.setdefault(j.find("parent").get("link"), []).append(j)
        es_hijo.add(j.find("child").get("link"))
    raices = [n for n in links if n not in es_hijo]
    if len(raices) != 1:
        raise SystemExit(f"se esperaba un link raíz, hay {raices}")

    # --- mallas: reparto del presupuesto y diezmado ---
    dir_mallas = os.path.join(a.proyecto, a.dir, "mallas_" + a.nombre)
    os.makedirs(dir_mallas, exist_ok=True)
    visuales = []  # (link, idx, visual, ruta_entrada, escala, salida_res)
    for ln, l in links.items():
        for i, v in enumerate(l.findall("visual")):
            m = v.find("geometry/mesh")
            if m is None:
                visuales.append((ln, i, v, None, None, None))
                continue
            ent = resolver_malla(m.get("filename"), dir_urdf, paquetes)
            esc = [float(x) for x in m.get("scale", "1 1 1").split()]
            sal = f"{nombre_nodo(ln)}_{i}.obj"
            visuales.append((ln, i, v, ent, esc, sal))
    con_malla = [x for x in visuales if x[3]]
    tris = {x[3]: (triangulos_stl(x[3]) if x[3].lower().endswith(".stl") else 2000) for x in con_malla}
    # Reparto proporcional a n^0.75: las piezas pequeñas conservan algo más de detalle relativo.
    peso = {k: n ** 0.75 for k, n in tris.items()}
    total_peso = sum(peso.values()) or 1
    trabajos = [
        {"entrada": x[3], "salida": os.path.abspath(os.path.join(dir_mallas, x[5])), "escala": x[4],
         "tris": int(max(a.min_tris, min(tris[x[3]], a.tris * peso[x[3]] / total_peso)))}
        for x in con_malla
    ]
    informe = []
    if not a.sin_diezmar and trabajos:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(trabajos, f)
        r = subprocess.run([a.blender, "-b", "--factory-startup", "-P", os.path.join(AQUI, "blender_diezmar.py"),
                            "--", f.name], capture_output=True, text=True)
        os.unlink(f.name)
        for ln in r.stdout.splitlines():
            if ln.startswith("URDF2GODOT_INFORME "):
                informe = json.loads(ln.split(" ", 1)[1])
        if r.returncode != 0 or not informe:
            sys.stderr.write(r.stdout[-3000:] + r.stderr[-3000:])
            raise SystemExit("falló Blender")

    # --- escena ---
    res_base = f"res://{a.dir}"
    ext, sub, nodos = [], [], []
    ext.append(f'[ext_resource type="Script" path="{res_base}/urdf_robot.gd" id="script"]')
    mats = {}

    def material(v):
        mat = v.find("material")
        rgba = None
        if mat is not None:
            c = mat.find("color")
            rgba = [float(x) for x in c.get("rgba").split()] if c is not None else materiales.get(mat.get("name"))
        rgba = rgba or [0.7, 0.7, 0.7, 1.0]
        clave = tuple(round(x, 3) for x in rgba)
        if clave not in mats:
            mid = f"mat_{len(mats)}"
            mats[clave] = mid
            sub.append(f'[sub_resource type="StandardMaterial3D" id="{mid}"]\n'
                       f'albedo_color = Color({", ".join(num(x) for x in rgba)})\n'
                       + ("transparency = 1\n" if rgba[3] < 1 else ""))
        return mats[clave]

    def prim(geo, sid):
        b, c, s = geo.find("box"), geo.find("cylinder"), geo.find("sphere")
        if b is not None:
            x, y, z = (float(t) for t in b.get("size").split())
            sub.append(f'[sub_resource type="BoxMesh" id="{sid}"]\nsize = Vector3({num(x)}, {num(y)}, {num(z)})\n')
            return None
        if c is not None:
            r, h = float(c.get("radius")), float(c.get("length"))
            sub.append(f'[sub_resource type="CylinderMesh" id="{sid}"]\ntop_radius = {num(r)}\n'
                       f'bottom_radius = {num(r)}\nheight = {num(h)}\nradial_segments = 16\nrings = 1\n')
            # CylinderMesh de Godot va a lo largo de su Y; el de URDF a lo largo de Z: girar +90° en X.
            return [[1, 0, 0], [0, 0, -1], [0, 1, 0]]
        if s is not None:
            sub.append(f'[sub_resource type="SphereMesh" id="{sid}"]\nradius = {num(float(s.get("radius")))}\n'
                       f'height = {num(2 * float(s.get("radius")))}\nradial_segments = 12\nrings = 6\n')
            return None
        return None

    def ruta_nodo(cadena):
        return "/".join(cadena)

    def emitir_link(nombre, padre_ruta):
        l = links[nombre]
        nn = nombre_nodo(nombre)
        nodos.append(f'[node name="{nn}" type="Node3D" parent="{padre_ruta}"]\nmetadata/urdf_link = "{nombre}"\n')
        mi_ruta = f"{padre_ruta}/{nn}"
        for (ln, i, v, ent, esc, sal) in visuales:
            if ln != nombre:
                continue
            m, xyz = leer_origen(v)
            mid = material(v)
            if ent:
                rid = f"malla_{nn}_{i}"
                ext.append(f'[ext_resource type="ArrayMesh" path="{res_base}/mallas_{a.nombre}/{sal}" id="{rid}"]')
                ref = f'ExtResource("{rid}")'
            else:
                rid = f"prim_{nn}_{i}"
                giro = prim(v.find("geometry"), rid)
                if giro:
                    m = [[sum(m[r][k] * giro[k][c] for k in range(3)) for c in range(3)] for r in range(3)]
                ref = f'SubResource("{rid}")'
            nodos.append(f'[node name="visual_{i}" type="MeshInstance3D" parent="{mi_ruta}"]\n'
                         f"transform = {t3d(m, xyz)}\nmesh = {ref}\nmaterial_override = SubResource(\"{mid}\")\n")
        for j in hijos.get(nombre, []):
            jn = nombre_nodo(j.get("name"))
            tipo = j.get("type")
            m, xyz = leer_origen(j)
            eje = [float(x) for x in (j.find("axis").get("xyz") if j.find("axis") is not None else "1 0 0").split()]
            lim = j.find("limit")
            meta = [f'metadata/urdf_joint = "{j.get("name")}"', f'metadata/urdf_type = "{tipo}"',
                    f"metadata/urdf_origin = {t3d(m, xyz)}",
                    f"metadata/urdf_axis = Vector3({', '.join(num(x) for x in eje)})"]
            if lim is not None and tipo in ("revolute", "prismatic"):
                meta.append(f"metadata/urdf_lower = {num(float(lim.get('lower', 0)))}")
                meta.append(f"metadata/urdf_upper = {num(float(lim.get('upper', 0)))}")
            mim = j.find("mimic")
            if mim is not None:
                meta.append(f'metadata/urdf_mimic = "{mim.get("joint")}"')
                meta.append(f"metadata/urdf_mimic_k = {num(float(mim.get('multiplier', 1)))}")
                meta.append(f"metadata/urdf_mimic_off = {num(float(mim.get('offset', 0)))}")
            nodos.append(f'[node name="{jn}" type="Node3D" parent="{mi_ruta}"]\ntransform = {t3d(m, xyz)}\n'
                         + "\n".join(meta) + "\n")
            emitir_link(j.find("child").get("link"), f"{mi_ruta}/{jn}")

    nombre_robot = nombre_nodo(raiz.get("name", a.nombre))
    nodos.append(f'[node name="{nombre_robot}" type="Node3D"]\nscript = ExtResource("script")\n'
                 f'metadata/urdf_robot = "{raiz.get("name", "")}"\n')
    nodos.append(f'[node name="RosFrame" type="Node3D" parent="."]\ntransform = {t3d(ROS_A_GODOT, [0, 0, 0])}\n')
    nodos.append('[node name="Base" type="Node3D" parent="RosFrame"]\n')
    emitir_link(raices[0], "RosFrame/Base")

    escena = "[gd_scene format=3]\n\n" + "\n".join(ext) + "\n\n" + "\n".join(sub) + "\n" + "\n".join(nodos)
    ruta_esc = os.path.join(a.proyecto, a.dir, a.nombre + ".tscn")
    open(ruta_esc, "w").write(escena)

    total_antes = sum(x["antes"] for x in informe)
    total_desp = sum(x["despues"] for x in informe)
    resumen = {"urdf": os.path.abspath(a.urdf), "escena": ruta_esc, "links": len(links), "joints": len(joints),
               "movibles": sum(1 for j in joints if j.get("type") not in ("fixed",)),
               "triangulos_original": total_antes, "triangulos_escena": total_desp, "mallas": informe}
    open(os.path.join(dir_mallas, "informe.json"), "w").write(json.dumps(resumen, indent=1))
    print(json.dumps({k: v for k, v in resumen.items() if k != "mallas"}, indent=1))


if __name__ == "__main__":
    main()
