#!/usr/bin/env python3
"""Casa del proyecto G1: UNA descripción (casa.json) → tres salidas coherentes entre sí.

  - MuJoCo: paredes y muebles como cajas de colisión junto al G1 (lo usa g1_sim.py --casa).
  - Godot:  escena `.tscn` con las mismas cajas (BoxMesh, ~12 triángulos cada una) en ejes de ROS
            bajo un RosFrame, igual que el robot de tools/urdf2godot (mismo marco = sin conversiones).
  - ROS:    mapa de ocupación `.pgm` + `.yaml` (map_server / Nav2, LT1) a 5 cm por celda.

Marco: el de ROS (x este, y norte, z arriba, metros). Muros = segmentos con huecos (puertas) a lo largo
del segmento; muebles = cajas con centro (x, y), tamaño (largo x, ancho y, alto z), yaw y color.

Uso (Python estándar, sin dependencias):
    docker/g1/casa.py docker/g1/casa.json --godot godot/g1-unitree/casa/casa.tscn \
        --mapa godot/g1-unitree/casa/mapa [--alto-visual 1.1]
"""
import argparse
import json
import math
import os


def cargar(ruta):
    return json.load(open(ruta))


def cajas(casa):
    """Todas las cajas: (nombre, (cx, cy, cz), (sx, sy, sz), yaw, color, es_muro)."""
    h, g = casa["altura_muro"], casa["grosor_muro"]
    res = []
    for i, m in enumerate(casa["muros"]):
        (x1, y1), (x2, y2) = m["de"], m["a"]
        largo = math.hypot(x2 - x1, y2 - y1)
        ux, uy = (x2 - x1) / largo, (y2 - y1) / largo
        yaw = math.atan2(uy, ux)
        tramos, ini = [], 0.0
        for a, b in sorted(m.get("huecos", [])):
            tramos.append((ini, a))
            ini = b
        tramos.append((ini, largo))
        for k, (a, b) in enumerate(tramos):
            if b - a < 1e-3:
                continue
            # prolongar media pared en los extremos para cerrar las esquinas
            a2 = a - (g / 2 if a == 0 else 0)
            b2 = b + (g / 2 if b == largo else 0)
            c = (a2 + b2) / 2
            res.append((f"muro_{i}_{k}", (x1 + ux * c, y1 + uy * c, h / 2), (b2 - a2, g, h), yaw,
                        [0.86, 0.84, 0.80], True))
    for mb in casa["muebles"]:
        sx, sy, sz = mb["tam"]
        z0 = mb.get("z", 0.0)
        res.append((mb["nombre"], (mb["centro"][0], mb["centro"][1], z0 + sz / 2), (sx, sy, sz),
                    math.radians(mb.get("yaw", 0)), mb["color"], False))
    return res


def escribir_mjcf(ruta_casa, dir_desc):
    """Escena MuJoCo = suelo + luz + G1 (g1_12dof.xml oficial) + cajas. Se escribe junto al modelo de
    Unitree para que el <include> y meshdir resuelvan igual que en su scene.xml."""
    casa = cargar(ruta_casa)
    geoms = []
    for (n, (cx, cy, cz), (sx, sy, sz), yaw, col, _) in cajas(casa):
        geoms.append(f'    <geom name="{n}" type="box" pos="{cx:.4f} {cy:.4f} {cz:.4f}" '
                     f'size="{sx / 2:.4f} {sy / 2:.4f} {sz / 2:.4f}" euler="0 0 {yaw:.5f}" '
                     f'rgba="{col[0]} {col[1]} {col[2]} 1"/>')
    xml = f"""<mujoco model="g1 en {casa['nombre']}">
  <include file="g1_12dof.xml"/>
  <worldbody>
    <light pos="5 4 5" dir="0 0 -1" directional="true"/>
    <geom name="suelo" size="0 0 0.05" type="plane" rgba="0.5 0.5 0.5 1"/>
{chr(10).join(geoms)}
  </worldbody>
</mujoco>
"""
    ruta = os.path.join(dir_desc, f"scene_{casa['nombre']}.xml")
    open(ruta, "w").write(xml)
    return ruta


def num(v):
    s = f"{v:.5f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def escribir_tscn(ruta_casa, salida, alto_visual):
    """Escena Godot. `alto_visual` recorta la altura de los muros (vista de casa de muñecas: con la cámara
    por encima se ve el robot dentro); la colisión en MuJoCo sigue con la altura real."""
    casa = cargar(ruta_casa)
    sub, nodos, mats = [], [], {}

    def mat(col):
        k = tuple(round(c, 3) for c in col)
        if k not in mats:
            mats[k] = f"mat_{len(mats)}"
            sub.append(f'[sub_resource type="StandardMaterial3D" id="{mats[k]}"]\n'
                       f'albedo_color = Color({num(col[0])}, {num(col[1])}, {num(col[2])}, 1)\n')
        return mats[k]

    def caja(nombre, padre, c, s, yaw, col):
        mid = f"box_{nombre}"
        sub.append(f'[sub_resource type="BoxMesh" id="{mid}"]\nsize = Vector3({num(s[0])}, {num(s[1])}, {num(s[2])})\n')
        cy, sy = math.cos(yaw), math.sin(yaw)
        # BoxMesh de Godot es simétrica: en el marco de ROS basta girar en z (yaw) y poner el centro.
        nodos.append(f'[node name="{nombre}" type="MeshInstance3D" parent="{padre}"]\n'
                     f"transform = Transform3D({num(cy)}, {num(-sy)}, 0, {num(sy)}, {num(cy)}, 0, 0, 0, 1, "
                     f"{num(c[0])}, {num(c[1])}, {num(c[2])})\nmesh = SubResource(\"{mid}\")\n"
                     f'material_override = SubResource("{mat(col)}")\n')

    ix, iy, iyaw = casa.get("inicio_robot", [0, 0, 0])
    nodos.append(f'[node name="Casa" type="Node3D"]\nmetadata/casa = "{casa["nombre"]}"\n'
                 f"metadata/inicio_robot = Vector3({num(ix)}, {num(iy)}, {num(iyaw)})\n")
    nodos.append('[node name="RosFrame" type="Node3D" parent="."]\n'
                 "transform = Transform3D(0, -1, 0, 0, 0, 1, -1, 0, 0, 0, 0, 0)\n")
    nodos.append('[node name="Suelos" type="Node3D" parent="RosFrame"]\n')
    nodos.append('[node name="Muros" type="Node3D" parent="RosFrame"]\n')
    nodos.append('[node name="Muebles" type="Node3D" parent="RosFrame"]\n')
    for e in casa["estancias"]:
        x1, y1, x2, y2 = e["rect"]
        caja("suelo_" + e["nombre"], "RosFrame/Suelos", ((x1 + x2) / 2, (y1 + y2) / 2, -0.01),
             (x2 - x1, y2 - y1, 0.02), 0, e["color"])
    for (n, c, s, yaw, col, muro) in cajas(casa):
        if muro and alto_visual:
            s = (s[0], s[1], min(s[2], alto_visual))
            c = (c[0], c[1], s[2] / 2)
        caja(n, "RosFrame/Muros" if muro else "RosFrame/Muebles", c, s, yaw, col)
    os.makedirs(os.path.dirname(os.path.abspath(salida)), exist_ok=True)
    open(salida, "w").write("[gd_scene format=3]\n\n" + "\n".join(sub) + "\n" + "\n".join(nodos))
    return len(cajas(casa)) + len(casa["estancias"])


def escribir_mapa(ruta_casa, base, res=0.05, margen=0.5):
    """OccupancyGrid como PGM (P5) + YAML de map_server: 0 = ocupado (negro), 254 = libre."""
    casa = cargar(ruta_casa)
    xs = [p for m in casa["muros"] for p in (m["de"][0], m["a"][0])]
    ys = [p for m in casa["muros"] for p in (m["de"][1], m["a"][1])]
    x0, y0 = min(xs) - margen, min(ys) - margen
    w = int(math.ceil((max(xs) + margen - x0) / res))
    h = int(math.ceil((max(ys) + margen - y0) / res))
    celdas = bytearray([205] * (w * h))  # desconocido fuera de la casa
    for e in casa["estancias"]:
        x1, y1, x2, y2 = e["rect"]
        for j in range(int((y1 - y0) / res), int((y2 - y0) / res)):
            for i in range(int((x1 - x0) / res), int((x2 - x0) / res)):
                celdas[(h - 1 - j) * w + i] = 254
    for (_, (cx, cy, cz), (sx, sy, sz), yaw, _, _) in cajas(casa):
        if cz - sz / 2 > 0.3:  # objetos en alto (tele) no bloquean el plano del láser bajo
            continue
        c, s = math.cos(yaw), math.sin(yaw)
        r = math.hypot(sx, sy) / 2
        for j in range(int((cy - r - y0) / res), int((cy + r - y0) / res) + 1):
            for i in range(int((cx - r - x0) / res), int((cx + r - x0) / res) + 1):
                px, py = x0 + (i + 0.5) * res - cx, y0 + (j + 0.5) * res - cy
                lx, ly = c * px + s * py, -s * px + c * py
                if abs(lx) <= sx / 2 and abs(ly) <= sy / 2 and 0 <= i < w and 0 <= j < h:
                    celdas[(h - 1 - j) * w + i] = 0
    os.makedirs(os.path.dirname(os.path.abspath(base)), exist_ok=True)
    with open(base + ".pgm", "wb") as f:
        f.write(f"P5\n{w} {h}\n255\n".encode() + bytes(celdas))
    open(base + ".yaml", "w").write(
        f"image: {os.path.basename(base)}.pgm\nmode: trinary\nresolution: {res}\n"
        f"origin: [{x0:.3f}, {y0:.3f}, 0.0]\nnegate: 0\noccupied_thresh: 0.65\nfree_thresh: 0.25\n")
    return w, h


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("casa")
    ap.add_argument("--godot", help="ruta del .tscn a generar")
    ap.add_argument("--alto-visual", type=float, default=1.1, help="altura visible de los muros en Godot (m)")
    ap.add_argument("--mapa", help="base de ruta del mapa (sin extensión)")
    a = ap.parse_args()
    if a.godot:
        print("Godot:", a.godot, escribir_tscn(a.casa, a.godot, a.alto_visual), "cajas")
    if a.mapa:
        print("Mapa:", a.mapa + ".pgm", "%dx%d" % escribir_mapa(a.casa, a.mapa))
