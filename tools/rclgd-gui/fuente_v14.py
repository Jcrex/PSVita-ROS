#!/usr/bin/env python3
"""Fuente sintética de los extras «solo PC» (V14) del visor, para probarlos con rclgd (doc 37 §5.4).

La estación (docker/vita-ros.sh fuente-visor / fuente-v2) no publica estos tipos; este script sí, y corre en la
imagen de tools/rclgd-gui.sh (que trae octomap_msgs y grid_map_msgs):

  /basic_controls/*        servidor de marcadores interactivos (interactive_markers de ROS 2): una caja con
                           6 GDL en (1, -1, 0.5); el servicio get_interactive_markers lo da el propio servidor
  /octomap_binary          octomap_msgs/Octomap binario (id OcTree, res 0,1 m): esfera hueca de radio 0,8 m en
                           (-1.5, 1.5, 1), FIABLE + TRANSIENT_LOCAL, cada 5 s
  /elevation_map           grid_map_msgs/GridMap 4 × 4 m a 0,1 m, capa «elevation» con una onda que se mueve, 1 Hz
  /camera/depth/image_raw  sensor_msgs/Image 16UC1 160 × 120 (mm), degradado que se desplaza, 5 Hz

Todo en el marco «map» (el marco fijo del visor): no hace falta TF.
Uso: tools/rclgd-gui.sh fuente-v14     (o, en un contenedor jazzy con esos paquetes, python3 fuente_v14.py)
Los feedback de la herramienta «Interactuar» del visor se imprimen aquí ([feedback] ...).
"""
import math
import struct

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, DurabilityPolicy
from geometry_msgs.msg import Point, Pose
from sensor_msgs.msg import Image
from std_msgs.msg import Float32MultiArray, MultiArrayDimension
from visualization_msgs.msg import InteractiveMarker, InteractiveMarkerControl, Marker
from interactive_markers import InteractiveMarkerServer
from octomap_msgs.msg import Octomap
from grid_map_msgs.msg import GridMap

PROF = 16          # niveles del árbol de octomap
CENTRO = 1 << 15   # clave del origen


def octomap_binario(claves):
    """Codifica un conjunto de claves (ix, iy, iz) de hojas ocupadas al formato binario de octomap.

    2 B por nodo interior (hijos 0-3 en el primer byte, 4-7 en el segundo), 2 bit por hijo: 2 ocupado, 3 con hijos;
    recorrido en profundidad con hijos en orden 0..7 (el que lee godot/plantillas/visor/displays/3d/octomap.gd).
    Hijo i: bit 0 → x, bit 1 → y, bit 2 → z; en la profundidad d decide el bit (15 - d) de la clave.
    """
    salida = bytearray()

    def nodo(conjunto, d):
        bit = 15 - d
        grupos = [[] for _ in range(8)]
        for k in conjunto:
            i = ((k[0] >> bit) & 1) | (((k[1] >> bit) & 1) << 1) | (((k[2] >> bit) & 1) << 2)
            grupos[i].append(k)
        valor = 0
        for i, g in enumerate(grupos):
            if g:
                valor |= (2 if d == PROF - 1 else 3) << (2 * i)
        salida.extend(struct.pack("<H", valor))
        if d < PROF - 1:
            for g in grupos:
                if g:
                    nodo(g, d + 1)

    if claves:
        nodo(list(claves), 0)
    return bytes(salida)


def esfera(res, centro, radio):
    claves = set()
    n = int(radio / res) + 1
    for ix in range(-n, n + 1):
        for iy in range(-n, n + 1):
            for iz in range(-n, n + 1):
                r = math.sqrt(ix * ix + iy * iy + iz * iz) * res
                if abs(r - radio) < res * 0.6:
                    claves.add(tuple(int(math.floor(c / res)) + CENTRO + o
                                     for c, o in zip(centro, (ix, iy, iz))))
    return claves


class FuenteV14(Node):
    def __init__(self):
        super().__init__("fuente_v14")
        lat = QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE, durability=DurabilityPolicy.TRANSIENT_LOCAL)
        self.p_oct = self.create_publisher(Octomap, "/octomap_binary", lat)
        self.p_gm = self.create_publisher(GridMap, "/elevation_map", 10)
        self.p_img = self.create_publisher(Image, "/camera/depth/image_raw", 10)
        self.t = 0.0
        res = 0.1
        claves = esfera(res, (-1.5, 1.5, 1.0), 0.8)
        self.oct = Octomap(binary=True, id="OcTree", resolution=res)
        self.oct.header.frame_id = "map"
        self.oct.data = list(struct.unpack(f"{len(octomap_binario(claves))}b", octomap_binario(claves)))
        self.get_logger().info(f"octomap: {len(claves)} vóxeles, {len(self.oct.data)} B")
        self.im = InteractiveMarkerServer(self, "basic_controls")
        self.im.insert(self._marcador(), feedback_callback=self._feedback)
        self.im.applyChanges()
        self.create_timer(5.0, self._octomap)
        self.create_timer(1.0, self._gridmap)
        self.create_timer(0.2, self._imagen)
        self._octomap()

    def _marcador(self):
        m = InteractiveMarker()
        m.header.frame_id = "map"
        m.name = "caja"
        m.description = "caja 6 GDL"
        m.scale = 0.6
        m.pose.position = Point(x=1.0, y=-1.0, z=0.5)
        caja = Marker(type=Marker.CUBE)
        caja.scale.x = caja.scale.y = caja.scale.z = 0.3
        caja.color.r, caja.color.g, caja.color.b, caja.color.a = 0.2, 0.6, 1.0, 1.0
        visual = InteractiveMarkerControl(always_visible=True)
        visual.markers.append(caja)
        m.controls.append(visual)
        for nombre, (w, x, y, z) in (("x", (1.0, 1.0, 0.0, 0.0)), ("z", (1.0, 0.0, 1.0, 0.0)),
                                     ("y", (1.0, 0.0, 0.0, 1.0))):
            for modo in (InteractiveMarkerControl.MOVE_AXIS, InteractiveMarkerControl.ROTATE_AXIS):
                c = InteractiveMarkerControl()
                c.orientation.w, c.orientation.x, c.orientation.y, c.orientation.z = w, x, y, z
                n = math.sqrt(w * w + x * x + y * y + z * z)
                c.orientation.w, c.orientation.x, c.orientation.y, c.orientation.z = w / n, x / n, y / n, z / n
                c.name = ("move_" if modo == InteractiveMarkerControl.MOVE_AXIS else "rotate_") + nombre
                c.interaction_mode = modo
                m.controls.append(c)
        return m

    def _feedback(self, fb):
        p = fb.pose.position
        self.get_logger().info(f"[feedback] tipo={fb.event_type} control={fb.control_name} "
                               f"pos=({p.x:.2f}, {p.y:.2f}, {p.z:.2f})")

    def _octomap(self):
        self.oct.header.stamp = self.get_clock().now().to_msg()
        self.p_oct.publish(self.oct)

    def _gridmap(self):
        self.t += 1.0
        res, lx, ly = 0.1, 4.0, 4.0
        filas, cols = int(lx / res), int(ly / res)
        g = GridMap()
        g.header.frame_id = "map"
        g.header.stamp = self.get_clock().now().to_msg()
        g.info.resolution, g.info.length_x, g.info.length_y = res, lx, ly
        g.info.pose = Pose()
        g.info.pose.position.x, g.info.pose.position.y = 2.5, -2.5
        g.info.pose.orientation.w = 1.0
        g.layers = ["elevation"]
        arr = Float32MultiArray()
        arr.layout.dim = [MultiArrayDimension(label="column_index", size=cols, stride=filas * cols),
                          MultiArrayDimension(label="row_index", size=filas, stride=filas)]
        datos = []
        for j in range(cols):           # column-major: data[j * filas + i]
            for i in range(filas):
                datos.append(0.3 * math.sin(i * 0.3 + self.t) * math.cos(j * 0.3))
        arr.data = datos
        g.data = [arr]
        self.p_gm.publish(g)

    def _imagen(self):
        w, h = 160, 120
        desp = int(self.t * 10) % w
        fila = struct.pack(f"<{w}H", *[500 + ((x + desp) % w) * 25 for x in range(w)])
        img = Image(height=h, width=w, encoding="16UC1", is_bigendian=0, step=w * 2)
        img.header.frame_id = "map"
        img.header.stamp = self.get_clock().now().to_msg()
        img.data = fila * h
        self.p_img.publish(img)


def main():
    rclpy.init()
    n = FuenteV14()
    try:
        rclpy.spin(n)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
