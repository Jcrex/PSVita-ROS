#!/usr/bin/env python3
"""vita_relay_percepcion — módulos camara, det2d, det3d y nube del relay VC/1 rev. 2 (V10; doc 36 §5.3, D12, D13).

Parte de NODO (con ROS) de la percepción. Las funciones puras (referencia de bytes) están en
`vita_relay_formatos.py` (bloque «percepción (V10)») y su copia en `godot/plantillas/ros/vc1.gd`. `vita_relay.py`
solo llama a `iniciar_percepcion(nodo, mods)`: así este bloque no se mezcla con los de otros módulos.

Salidas (prefijo `<p>` = /vita o /vita/<robot>):
  <p>/camara/compressed  sensor_msgs/CompressedImage  FIABLE (prof. 1)  `camara_hz` (3; máx. 5; 0 = apagado)
                         JPEG ≤ 160×120 q40, mensaje ≤ 2 994 B (baja la calidad si no cabe; si ni así, se salta)
  <p>/detecciones        Float32MultiArray BE 5 Hz  [seq, 0, 1, n, ancho, alto, (clase, score, cx, cy, w, h)·n] n ≤ 18
  <p>/det_clases         String FIABLE + TRANSIENT_LOCAL  nombres de clase por índice (al cambiar)
  <p>/detecciones3d      Float32MultiArray BE 5 Hz  [seq, 0, 1, n, (clase, score, x, y, z, yaw, sx, sy, sz)·n] n ≤ 12
                         en el marco fijo (`marco_fijo`, «map»; con tf2); sin TF la detección no se manda
  <p>/nube2d             Int16MultiArray BE 5 Hz × ≤ 3  [seq, trozo, n_trozos, n, (x, y, z)·n] cm, n ≤ 76, ≤ 228
                         puntos (vóxel 10 cm) en el marco fijo
Solo se publica lo NUEVO (det2d, det3d, nube y cámara): un dato viejo no se repite; el display lo da por caducado.

Parámetros: camara_in (/camera/color/image_raw/compressed; Image o CompressedImage, el tipo se descubre en el
grafo), camara_hz (3.0), det2d_in (/detections), det2d_tam ([640, 480]: tamaño de la imagen original si el módulo
camara no lo sabe), det3d_in (/detections_3d), nube_in (/points), marco_fijo (map; compartido con marcadores).
"""
import math

from vita_relay_formatos import (CAMARA_HZ, CAMARA_HZ_MAX, MAX_BE, TablaClasesDet, cdr_compressed_image,
                                 cdr_multiarray, componer, empaquetar_det2d, empaquetar_det3d, empaquetar_nube,
                                 recomprimir_camara, voxelizar_nube_np, yaw_de_quat, IDENTIDAD)

MODULOS_PERCEPCION = ("camara", "det2d", "det3d", "nube")


def _param_percepcion(nodo, nombre, defecto):
    """declare_parameter sin chocar si otro bloque (marcadores) ya declaró el mismo nombre (marco_fijo)."""
    if nodo.has_parameter(nombre):
        return nodo.get_parameter(nombre).value
    return nodo.declare_parameter(nombre, defecto).value


def _nube_numpy_percepcion(m):
    """sensor_msgs/PointCloud2 → array (N, 3) float64 con x, y, z (FLOAT32 = 7 o FLOAT64 = 8; *big endian* por campo,
    trampa T28). None si faltan campos. Sin sensor_msgs_py en la estación [V]: numpy con dtype estructurado."""
    import numpy as np
    campos = {f.name: f for f in m.fields}
    if not all(k in campos for k in "xyz"):
        return None
    orden = ">" if m.is_bigendian else "<"
    tipos = {7: "f4", 8: "f8"}
    nombres, formatos, offsets = [], [], []
    for k in "xyz":
        f = campos[k]
        if f.datatype not in tipos:
            return None
        nombres.append(k)
        formatos.append(orden + tipos[f.datatype])
        offsets.append(f.offset)
    dt = np.dtype({"names": nombres, "formats": formatos, "offsets": offsets, "itemsize": m.point_step})
    n = m.width * m.height
    if n == 0 or m.point_step == 0:
        return np.zeros((0, 3))
    filas = np.frombuffer(bytes(m.data), dtype=np.uint8)
    if m.row_step == m.width * m.point_step:
        pts = np.frombuffer(filas[:n * m.point_step].tobytes(), dtype=dt)
    else:                                            # filas con relleno: se quita fila a fila
        pts = np.concatenate([np.frombuffer(filas[r * m.row_step:r * m.row_step + m.width * m.point_step].tobytes(),
                                            dtype=dt) for r in range(m.height)])
    return np.stack([pts["x"], pts["y"], pts["z"]], axis=1).astype(np.float64)


def _matriz_percepcion(q):
    x, y, z, w = q
    return [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]


class Percepcion:
    """Estado y temporizadores de los módulos de percepción, colgados del nodo del relay."""

    def __init__(self, nodo, mods):
        from rclpy.qos import QoSProfile, ReliabilityPolicy, DurabilityPolicy, HistoryPolicy, qos_profile_sensor_data
        from std_msgs.msg import Float32MultiArray, Int16MultiArray, String
        self.n = nodo
        self.F32, self.I16, self.String = Float32MultiArray, Int16MultiArray, String
        pre = nodo.pre
        be = QoSProfile(depth=1, reliability=ReliabilityPolicy.BEST_EFFORT, history=HistoryPolicy.KEEP_LAST)
        latched = QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE,
                             durability=DurabilityPolicy.TRANSIENT_LOCAL, history=HistoryPolicy.KEEP_LAST)
        fiable1 = QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE, history=HistoryPolicy.KEEP_LAST)
        self.sensor = qos_profile_sensor_data
        self.marco_fijo = str(_param_percepcion(nodo, "marco_fijo", "map")).lstrip("/")
        self.clases = TablaClasesDet()
        self.tam_imagen = None                       # (ancho, alto) de la imagen original (módulo camara)
        self.saltadas = 0                            # imágenes que no cupieron en CAMARA_MAX_B
        self.tf_buf = getattr(nodo, "tf_buf", None)
        if self.tf_buf is None and ("det3d" in mods or "nube" in mods):
            try:
                import tf2_ros
                self.tf_buf = tf2_ros.Buffer()
                self.tf_lis = tf2_ros.TransformListener(self.tf_buf, nodo)
            except ImportError:
                nodo.get_logger().warning("percepción: sin tf2_ros; solo valen datos ya en el marco fijo")
        if "det2d" in mods or "det3d" in mods:
            self.p_clases = nodo.create_publisher(String, pre + "/det_clases", latched)
        if "camara" in mods:
            hz = min(float(_param_percepcion(nodo, "camara_hz", CAMARA_HZ)), CAMARA_HZ_MAX)
            if hz > CAMARA_HZ:                       # revisión V3: el presupuesto declarado (PRESUPUESTO) es a 3 Hz
                nodo.get_logger().warning(f"camara: {hz:g} Hz > {CAMARA_HZ:g} Hz declarados: +{(hz - CAMARA_HZ) * 2.994:.1f}"
                                          " KB/s sobre el perfil (percepcion pasa de 40 KB/s)")
            self.cam_in = _param_percepcion(nodo, "camara_in", "/camera/color/image_raw/compressed")
            self.cam = None
            self.sub_cam = None
            if hz > 0:
                self.p_cam = nodo.create_publisher(_tipo("sensor_msgs/msg/CompressedImage"), pre + "/camara/compressed",
                                                   fiable1)
                self._t_cam = nodo.create_timer(2.0, self._buscar_camara)
                self._buscar_camara()
                nodo.create_timer(1.0 / hz, self._tx_camara)
            else:
                nodo.get_logger().info("camara: camara_hz = 0 → módulo apagado (D13)")
        if "det2d" in mods:
            from vision_msgs.msg import Detection2DArray
            self.det2d = None
            self.seq_det2d = 0
            self.det2d_tam = list(_param_percepcion(nodo, "det2d_tam", [640, 480]))
            nodo.create_subscription(Detection2DArray, _param_percepcion(nodo, "det2d_in", "/detections"),
                                     lambda m: setattr(self, "det2d", m), self.sensor)
            self.p_det2d = nodo.create_publisher(Float32MultiArray, pre + "/detecciones", be)
            nodo.create_timer(0.2, self._tx_det2d)                         # 5 Hz
        if "det3d" in mods:
            from vision_msgs.msg import Detection3DArray
            self.det3d = None
            self.seq_det3d = 0
            nodo.create_subscription(Detection3DArray, _param_percepcion(nodo, "det3d_in", "/detections_3d"),
                                     lambda m: setattr(self, "det3d", m), self.sensor)
            self.p_det3d = nodo.create_publisher(Float32MultiArray, pre + "/detecciones3d", be)
            nodo.create_timer(0.2, self._tx_det3d)                         # 5 Hz
        if "nube" in mods:
            from sensor_msgs.msg import PointCloud2
            self.nube = None
            self.seq_nube = 0
            nodo.create_subscription(PointCloud2, _param_percepcion(nodo, "nube_in", "/points"),
                                     lambda m: setattr(self, "nube", m), self.sensor)
            self.p_nube = nodo.create_publisher(Int16MultiArray, pre + "/nube2d", be)
            nodo.create_timer(0.2, self._tx_nube)                          # 5 Hz × ≤ 3 trozos

    # --- TF al marco fijo
    def _resolver(self, frame):
        frame = frame.lstrip("/")
        if frame in ("", self.marco_fijo):
            return IDENTIDAD
        if self.tf_buf is None:
            return None
        try:
            from rclpy.time import Time
            tr = self.tf_buf.lookup_transform(self.marco_fijo, frame, Time()).transform
        except Exception:
            return None
        t, r = tr.translation, tr.rotation
        return ((t.x, t.y, t.z), (r.x, r.y, r.z, r.w))

    def _clases_si_cambian(self):
        if self.clases.cambio:
            self.clases.cambio = False
            self.p_clases.publish(self.String(data=self.clases.texto()))

    @staticmethod
    def _mejor(det, por_defecto):
        """Mejor hipótesis (class_id, score) de una detección; sin resultados, (id o «?», 1)."""
        mejor = None
        for r in det.results:
            h = r.hypothesis
            if mejor is None or h.score > mejor[1]:
                mejor = (h.class_id, float(h.score))
        return mejor or (por_defecto or "?", 1.0)

    # --- cámara
    def _buscar_camara(self):
        from rosidl_runtime_py.utilities import get_message
        if self.sub_cam is not None:
            return
        t = dict(self.n.get_topic_names_and_types()).get(self.cam_in)
        if not t:
            return
        self.sub_cam = self.n.create_subscription(get_message(t[0]), self.cam_in,
                                                  lambda m: setattr(self, "cam", m), self.sensor)
        self._t_cam.cancel()
        self.n.get_logger().info(f"camara: {self.cam_in} ({t[0]}) → {self.n.pre}/camara/compressed")

    def _tx_camara(self):
        m = self.cam
        if m is None:
            return
        self.cam = None                              # solo lo nuevo
        entrada = (("cruda", m.encoding, m.width, m.height, m.step, m.data) if hasattr(m, "encoding")   # Image
                   else ("comprimida", m.format, m.data))
        frame = m.header.frame_id
        jpeg, info, tam = recomprimir_camara(entrada, frame)
        if tam is not None:
            self.tam_imagen = tam                    # las cajas 2D vienen en px de la imagen ORIGINAL
        if jpeg is None:
            self.saltadas += 1
            if self.saltadas == 1 or self.saltadas % 50 == 0:
                self.n.get_logger().warning(f"camara: imagen saltada ({info}); {self.saltadas} en total")
            return
        o = _tipo("sensor_msgs/msg/CompressedImage")()
        o.header = m.header
        o.format = "jpeg"
        o.data = jpeg
        self.p_cam.publish(o)
        nb = cdr_compressed_image(frame, "jpeg", len(jpeg))
        self.n.bytes += nb                           # fiable y fragmentado: no pasa por _pub (que exige ≤ MAX_BE)
        self.n.msgs += math.ceil(nb / MAX_BE)        # ≈ datagramas

    # --- detecciones 2D
    def _tx_det2d(self):
        m = self.det2d
        if m is None:
            return
        self.det2d = None
        cajas = []
        for d in m.detections:
            nombre, score = self._mejor(d, d.id)
            b = d.bbox
            cajas.append([self.clases.indice(nombre), score, b.center.position.x, b.center.position.y,
                          b.size_x, b.size_y])
        self._clases_si_cambian()
        ancho, alto = self.tam_imagen or self.det2d_tam
        self.seq_det2d += 1
        d = empaquetar_det2d(cajas, ancho, alto, self.seq_det2d)
        self.n._pub(self.p_det2d, self.F32(data=[float(v) for v in d]), cdr_multiarray(len(d), 4))

    # --- detecciones 3D
    def _tx_det3d(self):
        m = self.det3d
        if m is None:
            return
        self.det3d = None
        t = self._resolver(m.header.frame_id)
        if t is None:
            return                                   # sin TF al fijo: no se manda (como marcadores)
        cajas = []
        for d in m.detections:
            nombre, score = self._mejor(d, d.id)
            c = d.bbox.center
            p, o = c.position, c.orientation
            (x, y, z), q = componer(t, ((p.x, p.y, p.z), (o.x, o.y, o.z, o.w)))
            s = d.bbox.size
            cajas.append([self.clases.indice(nombre), score, x, y, z, yaw_de_quat(*q), s.x, s.y, s.z])
        self._clases_si_cambian()
        self.seq_det3d += 1
        d = empaquetar_det3d(cajas, self.seq_det3d)
        self.n._pub(self.p_det3d, self.F32(data=[float(v) for v in d]), cdr_multiarray(len(d), 4))

    # --- nube
    def _tx_nube(self):
        m = self.nube
        if m is None:
            return
        self.nube = None
        t = self._resolver(m.header.frame_id)
        if t is None:
            return
        import numpy as np
        xyz = _nube_numpy_percepcion(m)
        if xyz is None:
            return
        if t is not IDENTIDAD:
            xyz = xyz @ np.array(_matriz_percepcion(t[1])).T + np.array(t[0])
        self.seq_nube += 1
        for d in empaquetar_nube(voxelizar_nube_np(xyz), self.seq_nube):
            self.n._pub(self.p_nube, self.I16(data=[int(v) for v in d]), cdr_multiarray(len(d), 2))


def _tipo(nombre):
    from rosidl_runtime_py.utilities import get_message
    return get_message(nombre)


def iniciar_percepcion(nodo, mods):
    """Lo llama el nodo del relay en su __init__ (después de fijar `nodo.pre`). None si no hay módulos de percepción."""
    if not any(m in mods for m in MODULOS_PERCEPCION):
        return None
    return Percepcion(nodo, mods)

