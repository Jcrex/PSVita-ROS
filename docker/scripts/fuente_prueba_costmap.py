#!/usr/bin/env python3
"""fuente_prueba_costmap — costmap sintético al estilo de Nav2 para probar el módulo `costmap` del relay (V11).

Publica `/global_costmap/costmap` (OccupancyGrid, fiable + TRANSIENT_LOCAL, como `costmap_2d_publisher.cpp`) UNA vez:
10 × 10 m a 5 cm (200 × 200), origen (−5, −5), paredes letales (100) con inflado (99 inscrito y degradado 98 → 1) y
desconocido (−1) en una esquina. Después, cada `--periodo` s, un obstáculo que se mueve en
`/global_costmap/costmap_updates` (map_msgs/OccupancyGridUpdate: solo el parche, sin cambiar la época).

  docker/vita-ros.sh fuente-costmap          # y en otra terminal: docker/vita-ros.sh relay hmi,costmap
"""
import argparse
import math

import rclpy
import rclpy.executors
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from nav_msgs.msg import OccupancyGrid
from map_msgs.msg import OccupancyGridUpdate

W = H = 200
RES = 0.05
INSCRITO = 0.20           # m (radio inscrito de un TB3 burger ≈ 0,105 m; aquí más grande para verlo)
INFLADO = 0.60            # m


def coste(d):
    """Distancia (m) al obstáculo → coste de Nav2 escalado a 0–100 (letal 100, inscrito 99, degradado)."""
    if d <= 0.0:
        return 100
    if d <= INSCRITO:
        return 99
    if d >= INFLADO:
        return 0
    return max(1, int(98 * math.exp(-6.0 * (d - INSCRITO))))


def rejilla(obst):
    """obst = lista de (x, y) en celdas → costmap con inflado (fuerza bruta, solo al arrancar)."""
    r = int(INFLADO / RES) + 1
    data = [0] * (W * H)
    for (ox, oy) in obst:
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                x, y = ox + dx, oy + dy
                if 0 <= x < W and 0 <= y < H:
                    c = coste(math.hypot(dx, dy) * RES)
                    k = y * W + x
                    if c > data[k]:
                        data[k] = c
    for y in range(160, H):                      # esquina sin explorar
        for x in range(0, 40):
            data[y * W + x] = -1
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--periodo", type=float, default=1.0)
    a = ap.parse_args()
    rclpy.init()
    n = Node("fuente_prueba_costmap")
    latched = QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE,
                         durability=DurabilityPolicy.TRANSIENT_LOCAL, history=HistoryPolicy.KEEP_LAST)
    p_cm = n.create_publisher(OccupancyGrid, "/global_costmap/costmap", latched)
    p_up = n.create_publisher(OccupancyGridUpdate, "/global_costmap/costmap_updates", 10)
    obst = [(x, 20) for x in range(20, 180)] + [(x, 180) for x in range(20, 180)] + \
           [(20, y) for y in range(20, 181)] + [(180, y) for y in range(20, 181)] + [(100, y) for y in range(60, 120)]
    data = rejilla(obst)
    m = OccupancyGrid()
    m.header.frame_id = "map"
    m.info.resolution = RES
    m.info.width = W
    m.info.height = H
    m.info.origin.position.x = -5.0
    m.info.origin.position.y = -5.0
    m.info.origin.orientation.w = 1.0
    m.data = data
    m.header.stamp = n.get_clock().now().to_msg()
    p_cm.publish(m)
    n.get_logger().info(f"costmap {W}×{H} a {RES} m publicado; parches cada {a.periodo} s")
    estado = {"t": 0, "previo": None}
    lado = 16

    def tic():
        # Obstáculo de 16 × 16 celdas que da vueltas: borra el parche anterior y pinta el nuevo.
        t = estado["t"]
        estado["t"] += 1
        cx = int(100 + 50 * math.cos(t * 0.3)) - lado // 2
        cy = int(100 + 50 * math.sin(t * 0.3)) - lado // 2
        for (x0, y0, val) in ([(estado["previo"][0], estado["previo"][1], None)] if estado["previo"] else []) + \
                [(cx, cy, 100)]:
            u = OccupancyGridUpdate()
            u.header.frame_id = "map"
            u.header.stamp = n.get_clock().now().to_msg()
            u.x, u.y, u.width, u.height = x0, y0, lado, lado
            u.data = [val if val is not None else data[(y0 + j) * W + x0 + i] for j in range(lado) for i in range(lado)]
            p_up.publish(u)
        estado["previo"] = (cx, cy)

    n.create_timer(a.periodo, tic)
    try:
        rclpy.spin(n)
    except (KeyboardInterrupt, rclpy.executors.ExternalShutdownException):
        pass


if __name__ == "__main__":
    main()
