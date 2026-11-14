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
  --- VC/1 rev. 2 (V6; doc 36 §5, ADR 0013, sentencia W13 D4–D5) ---
  /vita/relay_info     String  FIABLE + TRANSIENT_LOCAL  «VC/1.2;mód1,mód2,…» (saludo de versión y módulos activos)
  /vita/rosout         rcl_interfaces/Log  FIABLE ≤ 10/s  solo ≥ WARN, file/function vacíos, msg ≤ 200 car.  [rosout]
  /vita/diagnostics    DiagnosticArray   ≤ 10 Hz  UN estado por mensaje, ≤ 3 pares, textos ≤ 40 car.; primero los
                        que cambian de nivel o mensaje y un repaso a 1 Hz por estado                         [diag]
  /vita/ritmo/<nombre> el tipo de entrada  Hz fija  el mismo mensaje (bytes tal cual), solo si ≤ 488 B;
                        ≤ 30 Hz y ≤ 10 KB/s en total                                                          [ritmo]
  Época del mapa: `version` solo sube si cambian resolución, tamaño u origen (antes, con cada OccupancyGrid).
  --- V9 (doc 36 §5.3; parámetros pose_cov_in (/amcl_pose), poses_in (/particle_cloud), tf_lista ([odom])) ---
  /vita/pose_cov       Float32MultiArray 2 Hz   [x, y, yaw, σxx, σxy, σyy, σyaw] (varianzas, de PoseWithCovariance) [pose_cov]
  /vita/poses          Float32MultiArray 2 Hz   cab. + [x, y, yaw]·n, n ≤ 36 diezmado (PoseArray o ParticleCloud) [poses]
  /vita/tf             Float32MultiArray 10 Hz  cab. + [idx, x, y, z, qx, qy, qz, qw]·n, n ≤ 8 hijos de tf_lista    [tf]
  /vita/tf_marcos      String  FIABLE + TRANSIENT_LOCAL  «padre>hijo,…»: el `idx` de tf y tf_estatico           [tf]
  /vita/tf_estatico    Float32MultiArray FIABLE + TRANSIENT_LOCAL  como tf, ≤ 16 de /tf_static (al cambiar)        [tf]

Módulos: scan, pose, joints, mapa, path, rosout, diag, ritmo, o un perfil: hmi (= los 7 primeros), viz,
percepcion (sus módulos extra llegan con V8–V11) y todo. TOPE DE RED (D5.7): al arrancar se suma lo declarado por
módulo (`vita_relay_formatos.PRESUPUESTO`); si pasa de 100 KB/s o de 200 datagramas/s el relay NO arranca y dice qué
módulo sobra («todo» se rechaza siempre: 65,9 KB/s y 229 dgr/s). Comprobar sin ROS:
`python3 vita_relay.py --comprobar hmi`.

Parámetros: prefijo (/vita; contrato VC/1: /vita/<robot>, p. ej. -p prefijo:=/vita/g1), modulos (lista; por
            defecto scan,pose,joints,mapa,path), scan_in, odom_in, joints_in, map_in, path_in, rosout_in (/rosout),
            rosout_nivel (30 = WARN), diag_in (/diagnostics), ritmo (lista «nombre=/topic@hz»; el tipo se descubre
            en el grafo), max_rayos (180), teselas_por_s (20).
Uso: docker/vita-ros.sh relay [modulos] [prefijo] [ritmo]   (dentro de la estación; ver docker/README.md)
     p. ej. docker/vita-ros.sh relay hmi,ritmo /vita imu=/imu/data@20
Funciones puras (referencia de bytes): vita_relay_formatos.py; pruebas: python3 docker/scripts/test_vita_relay.py
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# Funciones puras del contrato VC/1 rev. 2 (V6, D5.3: el script se parte; aquí queda solo el nodo). Se reexportan
# para que `import vita_relay as vr; vr.empaquetar_scan(...)` siga valiendo.
from vita_relay_formatos import *  # noqa: E402,F401,F403
from vita_relay_formatos import (MAX_BE, TESELA, PlanDiag, CuboBytes, cdr_multiarray, compactar_estado,  # noqa: E402
                                 compactar_log, empaquetar_path, empaquetar_scan, empaquetar_tesela, epoca_mapa,
                                 parsear_ritmo, relay_info, resolver_modulos, yaw_de_quat)
import math  # noqa: E402


# ----------------------------------------------------------------------------- nodo ROS 2

def main():
    # Sin ROS: `python3 vita_relay.py --comprobar hmi` dice si el relay arrancaría con esos módulos (tope de red).
    if len(sys.argv) >= 3 and sys.argv[1] == "--comprobar":
        try:
            mods, kb, dgr = resolver_modulos(sys.argv[2].split(","))
        except ValueError as e:
            print(f"vita_relay NO arranca: {e}")
            sys.exit(1)
        print(f"vita_relay arrancaría: {','.join(mods)} = {kb:.1f} KB/s, {dgr:.0f} dgr/s nominales")
        return

    import rclpy
    import rclpy.executors
    from rclpy.node import Node
    from rclpy.qos import QoSProfile, ReliabilityPolicy, DurabilityPolicy, HistoryPolicy, qos_profile_sensor_data
    from rclpy.serialization import serialize_message
    from nav_msgs.msg import Odometry, OccupancyGrid, Path
    from sensor_msgs.msg import LaserScan, JointState
    from std_msgs.msg import Float32MultiArray, Int16MultiArray, UInt8MultiArray, String

    be = QoSProfile(depth=1, reliability=ReliabilityPolicy.BEST_EFFORT, history=HistoryPolicy.KEEP_LAST)
    latched = QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE,
                         durability=DurabilityPolicy.TRANSIENT_LOCAL, history=HistoryPolicy.KEEP_LAST)
    fiable = QoSProfile(depth=10, reliability=ReliabilityPolicy.RELIABLE, history=HistoryPolicy.KEEP_LAST)

    class Relay(Node):
        def __init__(self):
            super().__init__("vita_relay")
            p = self.declare_parameter
            pedidos = p("modulos", ["scan", "pose", "joints", "mapa", "path"]).value
            pre = p("prefijo", "/vita").value.rstrip("/")
            self.pre = pre
            self.max_rayos = p("max_rayos", 180).value
            self.teselas_s = p("teselas_por_s", 20).value
            # Tope de red (D5.7): si la suma nominal pasa de 100 KB/s o 200 dgr/s, NO se arranca.
            mods, kb, dgr = resolver_modulos(pedidos)       # ValueError → main() sale con código 1
            ritmos = parsear_ritmo(p("ritmo", [""]).value) if "ritmo" in mods else []
            self.mods = mods
            self.bytes = 0
            self.msgs = 0
            self.pose = None
            self.odom = None
            if "scan" in mods:
                self.scan = None
                self.seq = 0
                self.create_subscription(LaserScan, p("scan_in", "/scan").value, self._on_scan, qos_profile_sensor_data)
                self.p_scan = self.create_publisher(Int16MultiArray, pre + "/scan_compacto", be)
                self.create_timer(0.1, self._tx_scan)
            if "pose" in mods or "mapa" in mods:
                self.create_subscription(Odometry, p("odom_in", "/odom").value, self._on_odom, 10)
            if "pose" in mods:
                self.p_pose = self.create_publisher(Float32MultiArray, pre + "/pose2d", be)
                self.create_timer(1 / 30, self._tx_pose)
            if "joints" in mods:
                self.js = None
                self.orden = []
                self.create_subscription(JointState, p("joints_in", "/joint_states").value, self._on_js, 10)
                self.p_js = self.create_publisher(Float32MultiArray, pre + "/joints", be)
                self.p_orden = self.create_publisher(String, pre + "/joints_orden", latched)
                self.create_timer(1 / 25, self._tx_js)
            if "mapa" in mods:
                self.mapa = None
                self.hash = {}
                self.cola = []
                self.repaso = 0
                self.version = 0
                self.geo_epoca = None
                self.create_subscription(OccupancyGrid, p("map_in", "/map").value, self._on_map, latched)
                self.p_meta = self.create_publisher(Float32MultiArray, pre + "/mapa_meta", latched)
                self.p_tes = self.create_publisher(UInt8MultiArray, pre + "/mapa_tesela", be)
                self.create_timer(0.05, self._tx_teselas)
            if "path" in mods:
                self.path = None
                self.create_subscription(Path, p("path_in", "/plan").value, self._on_path, 10)
                self.p_path = self.create_publisher(Float32MultiArray, pre + "/path_compacto", be)
                self.create_timer(0.5, self._tx_path)
            # --- V9: pose_cov, poses y tf (doc 36 §5.3; funciones puras en vita_relay_formatos.py)
            if "pose_cov" in mods:
                from geometry_msgs.msg import PoseWithCovarianceStamped
                self.pose_cov = None
                self.create_subscription(PoseWithCovarianceStamped, p("pose_cov_in", "/amcl_pose").value,
                                         self._on_pose_cov, 10)
                self.p_pose_cov = self.create_publisher(Float32MultiArray, pre + "/pose_cov", be)
                self.create_timer(0.5, self._tx_pose_cov)                            # 2 Hz
            if "poses" in mods:
                # PoseArray o nav2_msgs/ParticleCloud (la nube de AMCL en Jazzy): el tipo se descubre en el grafo.
                self.poses = None
                self.seq_poses = 0
                self.poses_in = p("poses_in", "/particle_cloud").value
                self.sub_poses = None
                self.p_poses = self.create_publisher(Float32MultiArray, pre + "/poses", be)
                self._t_poses = self.create_timer(2.0, self._buscar_poses)
                self._buscar_poses()
                self.create_timer(0.5, self._tx_poses)                               # 2 Hz
            if "tf" in mods:
                # Lista blanca de ≤ 8 hijos dinámicos (D3); por defecto «odom» = map → odom (doc 36 §9.3.3).
                from tf2_msgs.msg import TFMessage
                self.tabla_tf = TablaTf(p("tf_lista", ["odom"]).value)
                self.seq_tf = 0
                self.create_subscription(TFMessage, "/tf", self._on_tf, 100)
                self.create_subscription(TFMessage, "/tf_static", self._on_tf_static,
                                         QoSProfile(depth=100, reliability=ReliabilityPolicy.RELIABLE,
                                                    durability=DurabilityPolicy.TRANSIENT_LOCAL,
                                                    history=HistoryPolicy.KEEP_LAST))
                self.p_tf = self.create_publisher(Float32MultiArray, pre + "/tf", be)
                self.p_tf_marcos = self.create_publisher(String, pre + "/tf_marcos", latched)
                self.p_tf_estatico = self.create_publisher(Float32MultiArray, pre + "/tf_estatico", latched)
                self.create_timer(0.1, self._tx_tf)                                  # 10 Hz
            if "rosout" in mods:
                # /rosout: los emisores publican fiable + TRANSIENT_LOCAL; aquí fiable y volátil (sin historial).
                from rcl_interfaces.msg import Log
                self.Log = Log
                self.cola_log = []
                self.log_descartados = 0
                self.log_minimo = p("rosout_nivel", 30).value
                self.create_subscription(Log, p("rosout_in", "/rosout").value, self._on_log, 50)
                self.p_log = self.create_publisher(Log, pre + "/rosout", fiable)   # fiable: un aviso no se repite
                self.create_timer(0.1, self._tx_log)                                 # ≤ 10 msg/s
            if "diag" in mods:
                from diagnostic_msgs.msg import DiagnosticArray, DiagnosticStatus, KeyValue
                self.DA, self.DS, self.KV = DiagnosticArray, DiagnosticStatus, KeyValue
                self.plan_diag = PlanDiag()
                self.create_subscription(DiagnosticArray, p("diag_in", "/diagnostics").value, self._on_diag, 10)
                self.p_diag = self.create_publisher(DiagnosticArray, pre + "/diagnostics", be)
                self.create_timer(0.1, self._tx_diag)                                # ≤ 10 Hz, un estado por tic
            if "ritmo" in mods:
                # Módulo ritmo (D5.9): <p>/ritmo/<nombre> = el mismo mensaje, a Hz fija y ≤ MAX_BE. El tipo se
                # descubre en el grafo (reintento cada 2 s) y se reenvían los bytes tal cual (raw, sin
                # deserializar): el tamaño es exacto y la CPU mínima.
                self.ritmos = {n: {"topic": t, "hz": hz, "ultimo": None, "pub": None, "grandes": 0}
                               for (n, t, hz) in ritmos}
                self.cubo_ritmo = CuboBytes()
                self.ritmo_descartados = 0
                if not ritmos:
                    self.get_logger().warning("ritmo activo sin entradas: -p ritmo:='[nombre=/topic@hz]'")
                self._t_ritmo = self.create_timer(2.0, self._buscar_ritmos)
                self._buscar_ritmos()
            self.p_bw = self.create_publisher(Float32MultiArray, pre + "/relay_bw", be)
            self.create_timer(1.0, self._tx_bw)
            # relay_info (D5.8): saludo de versión y lista de módulos activos (fiable + TRANSIENT_LOCAL).
            self.p_info = self.create_publisher(String, pre + "/relay_info", latched)
            self.p_info.publish(String(data=relay_info(mods)))
            self.get_logger().info(f"vita_relay {relay_info(mods)} en {pre}/…; {kb:.1f} KB/s y {dgr:.0f} dgr/s "
                                   f"nominales; todas las salidas ≤ {MAX_BE} B")

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
            ntx, nty = math.ceil(i.width / TESELA), math.ceil(i.height / TESELA)
            self.geo = (i.resolution, i.origin.position.x, i.origin.position.y, ntx, nty)
            # Época (D5.5): solo sube si cambian resolución, tamaño u origen. Con la misma geometría (un costmap a
            # 1–5 Hz, un mapa que crece por dentro) se reenvían SOLO las teselas cambiadas, con la misma época.
            geo = (float(i.resolution), int(i.width), int(i.height), float(i.origin.position.x),
                   float(i.origin.position.y))
            self.version, nueva = epoca_mapa(self.geo_epoca, geo, self.version)
            self.geo_epoca = geo
            if nueva:
                self.hash = {}          # época nueva: el cliente descarta todo, hay que mandar todas las teselas
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
            pend = [t for t in self.cola if t not in cambiadas] if not nueva else []
            self.cola = cambiadas + pend
            self.get_logger().info(f"mapa {i.width}×{i.height} → {ntx}×{nty} teselas, {len(cambiadas)} cambiadas, "
                                   f"época {self.version}{' (nueva)' if nueva else ''}")

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

        # --- V9: pose_cov (2 Hz, 44 B), poses (2 Hz, ≤ 464 B) y tf (10 Hz, ≤ 288 B; tf_marcos/tf_estatico F+TL)
        def _on_pose_cov(self, m):
            self.pose_cov = m

        def _tx_pose_cov(self):
            m = self.pose_cov
            if m is None:
                return
            p, q = m.pose.pose.position, m.pose.pose.orientation
            d = empaquetar_pose_cov(p.x, p.y, yaw_de_quat(q.x, q.y, q.z, q.w), list(m.pose.covariance))
            self._pub(self.p_pose_cov, Float32MultiArray(data=[float(v) for v in d]), cdr_multiarray(7, 4))

        def _buscar_poses(self):
            from rosidl_runtime_py.utilities import get_message
            if self.sub_poses is not None:
                return
            t = dict(self.get_topic_names_and_types()).get(self.poses_in)
            if not t:
                return
            cls = get_message(t[0])
            self.sub_poses = self.create_subscription(cls, self.poses_in, self._on_poses, qos_profile_sensor_data)
            self._t_poses.cancel()
            self.get_logger().info(f"poses: {self.poses_in} ({t[0]}) → {self.pre}/poses a 2 Hz")

        def _on_poses(self, m):
            lista = m.poses if hasattr(m, "poses") else [pt.pose for pt in m.particles]   # ParticleCloud
            self.poses = [(o.position.x, o.position.y,
                           yaw_de_quat(o.orientation.x, o.orientation.y, o.orientation.z, o.orientation.w))
                          for o in lista]

        def _tx_poses(self):
            if self.poses is None:
                return
            self.seq_poses += 1
            d = empaquetar_poses(self.poses, self.seq_poses)
            self._pub(self.p_poses, Float32MultiArray(data=[float(v) for v in d]), cdr_multiarray(len(d), 4))

        @staticmethod
        def _tq(ts):
            tr = ts.transform
            return ((tr.translation.x, tr.translation.y, tr.translation.z),
                    (tr.rotation.x, tr.rotation.y, tr.rotation.z, tr.rotation.w))

        def _on_tf(self, m):
            for ts in m.transforms:
                self.tabla_tf.dinamico(ts.header.frame_id, ts.child_frame_id, *self._tq(ts))

        def _on_tf_static(self, m):
            for ts in m.transforms:
                self.tabla_tf.estatico(ts.header.frame_id, ts.child_frame_id, *self._tq(ts))

        def _tx_tf(self):
            tabla = self.tabla_tf
            if tabla.cambio_marcos:                 # primero los nombres: el índice de tf/tf_estatico apunta aquí
                tabla.cambio_marcos = False
                self.p_tf_marcos.publish(String(data=tabla.texto_marcos()))
            if tabla.cambio_estaticos:
                tabla.cambio_estaticos = False
                d = tabla.trozo_estatico()
                self.p_tf_estatico.publish(Float32MultiArray(data=[float(v) for v in d]))
            if tabla.dinamicos:
                self.seq_tf += 1
                d = tabla.trozo_tf(self.seq_tf)
                self._pub(self.p_tf, Float32MultiArray(data=[float(v) for v in d]), cdr_multiarray(len(d), 4))

        # --- rosout: ≥ WARN, sin file/function, msg ≤ 200 car., ≤ 10/s (cola de 20: lo que sobra se descarta)
        def _on_log(self, m):
            c = compactar_log(m.level, m.name, m.msg, self.log_minimo)
            if c is None:
                return
            o = self.Log(stamp=m.stamp, level=m.level, name=c[0], msg=c[1], file="", function="", line=0)
            self.cola_log.append(o)
            if len(self.cola_log) > 20:
                self.cola_log.pop(0)
                self.log_descartados += 1

        def _tx_log(self):
            if self.cola_log:
                m = self.cola_log.pop(0)
                self._pub(self.p_log, m, len(serialize_message(m)))

        # --- diagnostics: un DiagnosticArray de UN estado por tic; cambios primero y repaso a 1 Hz por estado
        def _on_diag(self, m):
            self.stamp_diag = m.header.stamp
            for st in m.status:
                self.plan_diag.actualizar(compactar_estado(
                    st.level[0] if isinstance(st.level, bytes) else st.level, st.name, st.message,
                    [(kv.key, kv.value) for kv in st.values]))

        def _tx_diag(self):
            e = self.plan_diag.siguiente(time.monotonic())
            if e is None:
                return
            nivel, nombre, mensaje, pares = e
            st = self.DS(level=bytes([nivel & 0xFF]), name=nombre, message=mensaje, hardware_id="",
                         values=[self.KV(key=k, value=v) for k, v in pares])
            m = self.DA(status=[st])
            m.header.stamp = self.stamp_diag
            self._pub(self.p_diag, m, len(serialize_message(m)))

        # --- ritmo
        def _buscar_ritmos(self):
            from rosidl_runtime_py.utilities import get_message
            tipos = dict(self.get_topic_names_and_types())
            faltan = 0
            for nombre, r in self.ritmos.items():
                if r["pub"] is not None:
                    continue
                t = tipos.get(r["topic"])
                if not t:
                    faltan += 1
                    continue
                cls = get_message(t[0])
                r["pub"] = self.create_publisher(cls, f"{self.pre}/ritmo/{nombre}", be)
                r["sub"] = self.create_subscription(cls, r["topic"], lambda b, r=r: r.__setitem__("ultimo", b),
                                                    qos_profile_sensor_data, raw=True)
                r["timer"] = self.create_timer(1.0 / r["hz"], lambda n=nombre: self._tx_ritmo(n))
                self.get_logger().info(f"ritmo: {r['topic']} ({t[0]}) → {self.pre}/ritmo/{nombre} a {r['hz']} Hz")
            if faltan == 0:
                self._t_ritmo.cancel()

        def _tx_ritmo(self, nombre):
            r = self.ritmos[nombre]
            b = r["ultimo"]
            if b is None:
                return
            r["ultimo"] = None              # solo lo nuevo: no se repite un valor viejo
            if len(b) > MAX_BE:             # «topics pequeños»: lo que no cabe en un datagrama no se manda
                r["grandes"] += 1
                if r["grandes"] == 1:
                    self.get_logger().warning(f"ritmo/{nombre}: {len(b)} B > {MAX_BE}; se descartan")
                return
            if not self.cubo_ritmo.permitir(len(b), time.monotonic()):
                self.ritmo_descartados += 1
                return
            r["pub"].publish(b)
            self.bytes += len(b)
            self.msgs += 1

        def _tx_bw(self):
            self.p_bw.publish(Float32MultiArray(data=[float(self.bytes), float(self.msgs)]))
            self.bytes = 0
            self.msgs = 0

    rclpy.init()
    try:
        nodo = Relay()
    except ValueError as e:
        print(f"vita_relay NO arranca: {e}", file=sys.stderr)
        rclpy.shutdown()
        sys.exit(1)
    try:
        rclpy.spin(nodo)
    except (KeyboardInterrupt, rclpy.executors.ExternalShutdownException):
        pass                                # Ctrl+C / timeout: salida limpia, sin traza


if __name__ == "__main__":
    main()
