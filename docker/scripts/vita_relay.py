#!/usr/bin/env python3
"""vita_relay — adapta topics ROS 2 grandes a mensajes compactos que caben en XRCE para la PS Vita.

Por qué (doc 27, workshop W2): en la Vita, una suscripción best effort solo recibe mensajes de ≤ 488 B de CDR
(un datagrama de 512 B) y la fiable ≈ 7,5 KiB; casi nada de RViz cabe en crudo (LaserScan 360 = 1 504 B,
JointState 29 = 1 668 B, OccupancyGrid 384² = 147 KB). Este nodo publica, a ritmo fijo y con el ÚLTIMO valor
recibido, formatos compactos en best effort, todos ≤ 488 B. Patrón probado: /g1/estado del proyecto G1.

Salidas (todas BEST_EFFORT salvo las marcadas):
  /vita/scan_compacto  Int16MultiArray   10 Hz  [seq, ang_min_cdeg, inc_cdeg, n, r0..r(n-1)] en cm, 0 = sin dato, n ≤ 180
  /vita/pose2d         Float32MultiArray 30 Hz  [x, y, yaw, vx, vy, wz] (de /odom)
  /vita/joints         Float32MultiArray 25 Hz  posiciones en el orden de /vita/joints_orden (≤ 118)
  /vita/joints_orden   String  FIABLE + TRANSIENT_LOCAL  nombres separados por comas (se publica al cambiar)
  /vita/mapa_meta      Float32MultiArray FIABLE + TRANSIENT_LOCAL  [res, ancho, alto, ox, oy, teselas_x, teselas_y, version]
  /vita/mapa_tesela    UInt8MultiArray   ≤ 20/s [ver_lo, ver_hi, tx, ty, 256 B = 32×32 celdas a 2 bit]
                        (0 desconocido, 1 libre, 2 ocupado); primero las cercanas al robot, luego las cambiadas,
                        y un repaso lento de todas para quien se conecte tarde (best effort no tiene historial)
  /vita/path_compacto  Float32MultiArray 2 Hz   [n, x0, y0, …] Douglas-Peucker ε 5 cm, ≤ 57 puntos
  /vita/relay_bw       Float32MultiArray 1 Hz   [bytes/s de salida, mensajes/s]

Parámetros: modulos (lista: scan,pose,joints,mapa,path), scan_in, odom_in, joints_in, map_in, path_in,
            max_rayos (180), teselas_por_s (20).
Uso: docker/vita-ros.sh relay [modulos]   (dentro de la estación; ver docker/README.md)
"""
import math
import struct
import time

TESELA = 32               # celdas por lado de una tesela de mapa
MAX_BE = 488              # bytes de CDR que caben en un datagrama best effort de la Vita (doc 27)


# ----------------------------------------------------------------------------- funciones puras (con pruebas)

def empaquetar_scan(ranges, angle_min, angle_increment, range_min, range_max, seq, max_rayos=180):
    """LaserScan → lista de int16. Diezma por paso fijo para que quepan ≤ max_rayos."""
    n_in = len(ranges)
    paso = max(1, math.ceil(n_in / max_rayos))
    sel = ranges[::paso][:max_rayos]
    out = [seq & 0x7FFF, _i16(round(math.degrees(angle_min) * 100)),
           _i16(round(math.degrees(angle_increment * paso) * 100)), len(sel)]
    for r in sel:
        if r is None or math.isnan(r) or math.isinf(r) or r < range_min or r > range_max:
            out.append(0)
        else:
            out.append(_i16(round(r * 100)))
    return out


def desempaquetar_scan(d):
    """Inverso (lo que hará la Vita): [(ángulo_rad, distancia_m)] sin los rayos vacíos."""
    ang0, inc, n = math.radians(d[1] / 100), math.radians(d[2] / 100), d[3]
    return [(ang0 + i * inc, d[4 + i] / 100) for i in range(n) if d[4 + i] > 0]


def _i16(v):
    return max(-32768, min(32767, int(v)))


def celda_2bit(v):
    """OccupancyGrid (-1 desconocido, 0..100) → 0 desconocido, 1 libre, 2 ocupado (umbrales de map_server)."""
    if v < 0:
        return 0
    return 2 if v >= 65 else (1 if v <= 25 else 0)


def empaquetar_tesela(data, ancho, alto, tx, ty, version):
    """Una tesela de 32×32 celdas a 2 bit = 256 B + cabecera de 4 B. Celdas fuera del mapa = desconocido."""
    cuerpo = bytearray(TESELA * TESELA // 4)
    for j in range(TESELA):
        y = ty * TESELA + j
        for i in range(TESELA):
            x = tx * TESELA + i
            c = celda_2bit(data[y * ancho + x]) if (x < ancho and y < alto) else 0
            k = j * TESELA + i
            cuerpo[k >> 2] |= c << ((k & 3) * 2)
    return bytes([version & 0xFF, (version >> 8) & 0xFF, tx, ty]) + bytes(cuerpo)


def desempaquetar_tesela(b):
    """Inverso: (version, tx, ty, lista de 1024 valores 0/1/2 por filas)."""
    ver, tx, ty = b[0] | (b[1] << 8), b[2], b[3]
    celdas = [(b[4 + (k >> 2)] >> ((k & 3) * 2)) & 3 for k in range(TESELA * TESELA)]
    return ver, tx, ty, celdas


def douglas_peucker(pts, eps):
    if len(pts) < 3:
        return list(pts)
    (x0, y0), (x1, y1) = pts[0], pts[-1]
    dx, dy = x1 - x0, y1 - y0
    norma = math.hypot(dx, dy) or 1e-9
    peor, idx = -1.0, 0
    for i in range(1, len(pts) - 1):
        d = abs(dy * pts[i][0] - dx * pts[i][1] + x1 * y0 - y1 * x0) / norma
        if d > peor:
            peor, idx = d, i
    if peor <= eps:
        return [pts[0], pts[-1]]
    return douglas_peucker(pts[:idx + 1], eps)[:-1] + douglas_peucker(pts[idx:], eps)


def empaquetar_path(pts, eps=0.05, max_pts=57):
    s = douglas_peucker(pts, eps)
    while len(s) > max_pts:          # si aún sobran, ε creciente
        eps *= 1.5
        s = douglas_peucker(pts, eps)
    return [float(len(s))] + [v for p in s for v in p]


def yaw_de_quat(x, y, z, w):
    return math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))


def cdr_multiarray(n_elem, tam_elem):
    """Bytes de CDR de un *MultiArray sin dimensiones: encapsulado 4 + dim seq 4 + data_offset 4 + seq 4 + datos."""
    return 4 + 4 + 4 + 4 + n_elem * tam_elem


# ----------------------------------------------------------------------------- nodo ROS 2

def main():
    import rclpy
    from rclpy.node import Node
    from rclpy.qos import QoSProfile, ReliabilityPolicy, DurabilityPolicy, HistoryPolicy, qos_profile_sensor_data
    from nav_msgs.msg import Odometry, OccupancyGrid, Path
    from sensor_msgs.msg import LaserScan, JointState
    from std_msgs.msg import Float32MultiArray, Int16MultiArray, UInt8MultiArray, String

    be = QoSProfile(depth=1, reliability=ReliabilityPolicy.BEST_EFFORT, history=HistoryPolicy.KEEP_LAST)
    latched = QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE,
                         durability=DurabilityPolicy.TRANSIENT_LOCAL, history=HistoryPolicy.KEEP_LAST)

    class Relay(Node):
        def __init__(self):
            super().__init__("vita_relay")
            p = self.declare_parameter
            mods = p("modulos", ["scan", "pose", "joints", "mapa", "path"]).value
            self.max_rayos = p("max_rayos", 180).value
            self.teselas_s = p("teselas_por_s", 20).value
            self.bytes = 0
            self.msgs = 0
            self.pose = None
            if "scan" in mods:
                self.scan = None
                self.seq = 0
                self.create_subscription(LaserScan, p("scan_in", "/scan").value, self._on_scan, qos_profile_sensor_data)
                self.p_scan = self.create_publisher(Int16MultiArray, "/vita/scan_compacto", be)
                self.create_timer(0.1, self._tx_scan)
            if "pose" in mods or "mapa" in mods:
                self.odom = None
                self.create_subscription(Odometry, p("odom_in", "/odom").value, self._on_odom, 10)
            if "pose" in mods:
                self.p_pose = self.create_publisher(Float32MultiArray, "/vita/pose2d", be)
                self.create_timer(1 / 30, self._tx_pose)
            if "joints" in mods:
                self.js = None
                self.orden = []
                self.create_subscription(JointState, p("joints_in", "/joint_states").value, self._on_js, 10)
                self.p_js = self.create_publisher(Float32MultiArray, "/vita/joints", be)
                self.p_orden = self.create_publisher(String, "/vita/joints_orden", latched)
                self.create_timer(1 / 25, self._tx_js)
            if "mapa" in mods:
                self.mapa = None
                self.hash = {}
                self.cola = []
                self.repaso = 0
                self.version = 0
                self.create_subscription(OccupancyGrid, p("map_in", "/map").value, self._on_map, latched)
                self.p_meta = self.create_publisher(Float32MultiArray, "/vita/mapa_meta", latched)
                self.p_tes = self.create_publisher(UInt8MultiArray, "/vita/mapa_tesela", be)
                self.create_timer(0.05, self._tx_teselas)
            if "path" in mods:
                self.path = None
                self.create_subscription(Path, p("path_in", "/plan").value, self._on_path, 10)
                self.p_path = self.create_publisher(Float32MultiArray, "/vita/path_compacto", be)
                self.create_timer(0.5, self._tx_path)
            self.p_bw = self.create_publisher(Float32MultiArray, "/vita/relay_bw", be)
            self.create_timer(1.0, self._tx_bw)
            self.get_logger().info(f"vita_relay: módulos {mods}; todas las salidas ≤ {MAX_BE} B")

        def _pub(self, pub, msg, nbytes):
            assert nbytes <= MAX_BE, f"{pub.topic_name}: {nbytes} B > {MAX_BE}"
            pub.publish(msg)
            self.bytes += nbytes
            self.msgs += 1

        # --- scan
        def _on_scan(self, m):
            self.scan = m

        def _tx_scan(self):
            m = self.scan
            if m is None:
                return
            self.seq += 1
            d = empaquetar_scan(list(m.ranges), m.angle_min, m.angle_increment, m.range_min, m.range_max,
                                self.seq, self.max_rayos)
            self._pub(self.p_scan, Int16MultiArray(data=d), cdr_multiarray(len(d), 2))

        # --- pose
        def _on_odom(self, m):
            self.odom = m

        def _tx_pose(self):
            m = self.odom
            if m is None:
                return
            q = m.pose.pose.orientation
            t = m.twist.twist
            d = [m.pose.pose.position.x, m.pose.pose.position.y, yaw_de_quat(q.x, q.y, q.z, q.w),
                 t.linear.x, t.linear.y, t.angular.z]
            self._pub(self.p_pose, Float32MultiArray(data=[float(v) for v in d]), cdr_multiarray(6, 4))

        # --- joints
        def _on_js(self, m):
            self.js = m
            if not self.orden:
                self.orden = list(m.name)[:118]
                self.p_orden.publish(String(data=",".join(self.orden)))

        def _tx_js(self):
            m = self.js
            if m is None:
                return
            pos = dict(zip(m.name, m.position))
            d = [float(pos.get(n, 0.0)) for n in self.orden]
            self._pub(self.p_js, Float32MultiArray(data=d), cdr_multiarray(len(d), 4))

        # --- mapa por teselas
        def _on_map(self, m):
            i = m.info
            self.mapa = (list(m.data), i.width, i.height)
            self.version = (self.version + 1) & 0xFFFF
            ntx, nty = math.ceil(i.width / TESELA), math.ceil(i.height / TESELA)
            self.geo = (i.resolution, i.origin.position.x, i.origin.position.y, ntx, nty)
            self.p_meta.publish(Float32MultiArray(data=[float(i.resolution), float(i.width), float(i.height),
                                                        float(i.origin.position.x), float(i.origin.position.y),
                                                        float(ntx), float(nty), float(self.version)]))
            cambiadas = []
            for ty in range(nty):
                for tx in range(ntx):
                    b = empaquetar_tesela(self.mapa[0], i.width, i.height, tx, ty, self.version)
                    h = hash(b[4:])
                    if self.hash.get((tx, ty)) != h:
                        self.hash[(tx, ty)] = h
                        cambiadas.append((tx, ty))
            self.cola = cambiadas
            self.get_logger().info(f"mapa {i.width}×{i.height} → {ntx}×{nty} teselas, {len(cambiadas)} cambiadas")

        def _tx_teselas(self):
            if self.mapa is None:
                return
            res, ox, oy, ntx, nty = self.geo
            if not self.cola:   # repaso lento de todo el mapa (1 tesela por tic) para clientes tardíos
                self.repaso = (self.repaso + 1) % (ntx * nty)
                self.cola = [(self.repaso % ntx, self.repaso // ntx)]
            elif self.odom is not None:   # primero las cercanas al robot
                px = (self.odom.pose.pose.position.x - ox) / (res * TESELA)
                py = (self.odom.pose.pose.position.y - oy) / (res * TESELA)
                self.cola.sort(key=lambda t: (t[0] + 0.5 - px) ** 2 + (t[1] + 0.5 - py) ** 2)
            n = max(1, round(self.teselas_s * 0.05))
            datos, w, h = self.mapa
            for (tx, ty) in self.cola[:n]:
                b = empaquetar_tesela(datos, w, h, tx, ty, self.version)
                self._pub(self.p_tes, UInt8MultiArray(data=b), cdr_multiarray(len(b), 1))
            self.cola = self.cola[n:]

        # --- path
        def _on_path(self, m):
            self.path = [(p.pose.position.x, p.pose.position.y) for p in m.poses]

        def _tx_path(self):
            if not self.path:
                return
            d = empaquetar_path(self.path)
            self._pub(self.p_path, Float32MultiArray(data=d), cdr_multiarray(len(d), 4))

        def _tx_bw(self):
            self.p_bw.publish(Float32MultiArray(data=[float(self.bytes), float(self.msgs)]))
            self.bytes = 0
            self.msgs = 0

    rclpy.init()
    rclpy.spin(Relay())


if __name__ == "__main__":
    main()
