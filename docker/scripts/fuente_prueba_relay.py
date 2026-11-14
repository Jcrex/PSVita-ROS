#!/usr/bin/env python3
"""Fuente de prueba para vita_relay sin robot: publica /map desde un PGM de map_server (por defecto la casa del G1,
montada en /ws/... o pasada como argumento) y un /scan sintético de 360 rayos que gira, a 10 Hz.
Uso (en la estación): python3 /scripts/fuente_prueba_relay.py /ruta/mapa.yaml"""
import math
import os
import sys

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, DurabilityPolicy
from nav_msgs.msg import OccupancyGrid
from sensor_msgs.msg import LaserScan


def leer_pgm_yaml(ruta_yaml):
    meta = {}
    for ln in open(ruta_yaml):
        if ":" in ln:
            k, v = ln.split(":", 1)
            meta[k.strip()] = v.strip()
    pgm = os.path.join(os.path.dirname(ruta_yaml), meta["image"])
    raw = open(pgm, "rb").read()
    partes = raw.split(b"\n", 3)          # P5 / ancho alto / 255 / datos
    w, h = (int(x) for x in partes[1].split())
    datos = partes[3]
    occ = []
    for y in range(h - 1, -1, -1):        # PGM: fila 0 arriba; OccupancyGrid: fila 0 abajo
        for x in range(w):
            p = datos[y * w + x]
            occ.append(100 if p < 50 else (0 if p > 250 else -1))
    origen = [float(v) for v in meta["origin"].strip("[]").split(",")]
    return occ, w, h, float(meta["resolution"]), origen


def main():
    rclpy.init()
    n = Node("fuente_prueba_relay")
    latched = QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE, durability=DurabilityPolicy.TRANSIENT_LOCAL)
    pm = n.create_publisher(OccupancyGrid, "/map", latched)
    ps = n.create_publisher(LaserScan, "/scan", 10)
    if len(sys.argv) > 1:
        occ, w, h, res, org = leer_pgm_yaml(sys.argv[1])
        m = OccupancyGrid()
        m.header.frame_id = "map"
        m.info.resolution, m.info.width, m.info.height = res, w, h
        m.info.origin.position.x, m.info.origin.position.y = org[0], org[1]
        m.info.origin.orientation.w = 1.0
        m.data = occ
        pm.publish(m)
        n.get_logger().info(f"/map {w}×{h} a {res} m publicado (latched)")
    t = [0.0]

    def scan():
        t[0] += 0.1
        s = LaserScan()
        s.header.frame_id = "base_scan"
        s.header.stamp = n.get_clock().now().to_msg()
        s.angle_min, s.angle_max = -math.pi, math.pi
        s.angle_increment = 2 * math.pi / 360
        s.range_min, s.range_max = 0.12, 10.0
        s.ranges = [2.0 + math.sin(i * 0.05 + t[0]) for i in range(360)]
        ps.publish(s)

    n.create_timer(0.1, scan)
    rclpy.spin(n)


if __name__ == "__main__":
    main()
