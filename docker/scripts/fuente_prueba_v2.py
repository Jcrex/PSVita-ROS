#!/usr/bin/env python3
"""fuente_prueba_v2 — publicadores de prueba de los gates de hardware de la fase V2 del visor (V6, V8, V9).

Revisión V2 (docs/ia/workshops/posts/V2-revision.md §5). Complementa a `fuente_prueba_visor.py` (mapa, scan, odom…):
se lanza a la vez, en otra terminal, con `docker/vita-ros.sh fuente-v2 <modo>[,<modo>…]`.

Modos:
  avisos      gate V6: /rosout con 20 WARN/s (y 1 INFO/s que el relay debe filtrar) y /diagnostics con 6 estados a
              2 Hz; el estado «bateria» cambia de nivel cada 5 s (OK → WARN → ERROR) para que el relay lo priorice.
  marcadores  gates G-W13-M1 / M3: MarkerArray en /visualization_marker_array a 10 Hz con `--n` sólidos (CUBE,
              SPHERE, CYLINDER, ARROW) moviéndose en círculo, un LINE_STRIP de 50 puntos y un TEXT_VIEW_FACING.
              Por defecto n = 31 (31 + línea + texto = 33, el estado completo del relay; el cupo de la Vita es 12 en
              HMI y 32 en Viz). Marco «map» (el fijo del relay: sin TF).
  vida        gate G-W13-M2: 48 marcadores con lifetime 2 s republicados a 2 Hz en dos ns; cada 5 s DELETEALL del
              ns «vida_b». El número de nodos de la Vita debe quedarse constante.
  tf          gate V9: /tf con 8 hijos dinámicos a 10 Hz (map → odom y 7 eslabones bajo base_link), odom → base_link
              sacado de /odom (el de `fuente-visor`) y /tf_static base_link → base_scan (TurtleBot3). Con
              `relay hmi,tf /vita "" odom,rueda_izq,rueda_der,torre,brazo,pinza,antena,camara` llegan los 8.
  percepcion  gate V10: /camera/color/image_raw/compressed (CompressedImage JPEG 640×480 q85, 10 Hz, escena con
              degradado, rectángulos móviles y ruido), /detections (Detection2DArray, 20 cajas: el relay deja 18),
              /detections_3d (Detection3DArray, 14 cajas en «map»: el relay deja 12) y /points (PointCloud2 xyz
              float32, ≈ 6 000 puntos de paredes y un cilindro en «map», 10 Hz). Con `relay percepcion` (y
              `fuente-visor` para el perfil hmi) se mide /vita/relay_bw ≤ 40 KB/s.

Uso (dentro de la estación): python3 fuente_prueba_v2.py avisos,marcadores,tf [--n 31]
"""
import argparse
import math
import sys

MARCOS_TF = ["odom", "rueda_izq", "rueda_der", "torre", "brazo", "pinza", "antena", "camara"]   # 8 = MAX_TF


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("modos", help="avisos, marcadores, vida, tf, percepcion (separados por comas)")
    ap.add_argument("--n", type=int, default=31, help="sólidos del modo marcadores (defecto 31)")
    a = ap.parse_args()
    modos = [m.strip() for m in a.modos.split(",") if m.strip()]
    malos = [m for m in modos if m not in ("avisos", "marcadores", "vida", "tf", "percepcion")]
    if malos or not modos:
        print(f"modo desconocido: {malos or '(ninguno)'}; válidos: avisos, marcadores, vida, tf, percepcion",
              file=sys.stderr)
        sys.exit(2)

    import rclpy
    from rclpy.node import Node
    from rclpy.qos import QoSProfile, ReliabilityPolicy, DurabilityPolicy

    rclpy.init()
    n = Node("fuente_prueba_v2")
    t0 = n.get_clock().now()
    k = [0]

    def seg():
        return (n.get_clock().now() - t0).nanoseconds * 1e-9

    tics = []                                       # (cada cuántos tics de 50 ms, función)

    # --- avisos (V6) --------------------------------------------------------------------------------------------
    if "avisos" in modos:
        from rcl_interfaces.msg import Log
        from diagnostic_msgs.msg import DiagnosticArray, DiagnosticStatus, KeyValue
        p_log = n.create_publisher(Log, "/rosout", QoSProfile(depth=100, reliability=ReliabilityPolicy.RELIABLE,
                                                               durability=DurabilityPolicy.TRANSIENT_LOCAL))
        p_diag = n.create_publisher(DiagnosticArray, "/diagnostics", 10)
        cuenta = [0]

        def avisos():                               # cada 50 ms: 1 WARN (= 20/s); 1 INFO por segundo
            cuenta[0] += 1
            m = Log(stamp=n.get_clock().now().to_msg(), level=30, name="prueba_avisos",
                    msg=f"aviso {cuenta[0]}: obstaculo a {1 + (cuenta[0] % 50) / 10:.1f} m", file="fuente_prueba_v2.py",
                    function="avisos", line=1)
            p_log.publish(m)
            if cuenta[0] % 20 == 0:
                p_log.publish(Log(stamp=m.stamp, level=20, name="prueba_avisos", msg="info (el relay la filtra)"))

        def diag():                                 # 2 Hz, 6 estados; «bateria» cambia de nivel cada 5 s
            nivel_bat = int(seg() // 5) % 3
            m = DiagnosticArray()
            m.header.stamp = n.get_clock().now().to_msg()
            for i, nombre in enumerate(["bateria", "motores", "lidar", "camara", "imu", "wifi"]):
                lv = nivel_bat if nombre == "bateria" else 0
                m.status.append(DiagnosticStatus(level=bytes([lv]), name=nombre,
                                                 message=["OK", "baja", "critica"][lv] if nombre == "bateria" else "OK",
                                                 hardware_id=f"hw{i}",
                                                 values=[KeyValue(key="t", value=f"{seg():.0f}"),
                                                         KeyValue(key="i", value=str(i))]))
            p_diag.publish(m)

        tics += [(1, avisos), (10, diag)]

    # --- marcadores (V8) ----------------------------------------------------------------------------------------
    if "marcadores" in modos or "vida" in modos:
        from visualization_msgs.msg import Marker, MarkerArray
        from geometry_msgs.msg import Point
        p_marc = n.create_publisher(MarkerArray, "/visualization_marker_array", 10)

        def mk(ns, ident, tipo, x, y, z, s, rgb, accion=Marker.ADD, vida=0.0):
            m = Marker()
            m.header.frame_id = "map"
            m.header.stamp = n.get_clock().now().to_msg()
            m.ns, m.id, m.type, m.action = ns, ident, tipo, accion
            m.pose.position.x, m.pose.position.y, m.pose.position.z = float(x), float(y), float(z)   # rclpy exige float
            m.pose.orientation.w = 1.0
            m.scale.x, m.scale.y, m.scale.z = (float(v) for v in s)
            m.color.r, m.color.g, m.color.b = (float(v) for v in rgb)
            m.color.a = 1.0
            m.lifetime.sec = int(vida)
            m.lifetime.nanosec = int((vida % 1) * 1e9)
            return m

        if "marcadores" in modos:
            solidos = max(0, min(a.n, 31))
            tipos = [Marker.CUBE, Marker.SPHERE, Marker.CYLINDER, Marker.ARROW]
            colores = [(0.9, 0.1, 0.1), (0.1, 0.8, 0.2), (0.15, 0.35, 1.0), (1.0, 1.0, 0.0)]

            def marcadores():                       # 10 Hz
                t = seg()
                arr = MarkerArray()
                for i in range(solidos):
                    ang = t * 0.5 + i * 2 * math.pi / max(solidos, 1)
                    r = 2.0 + 0.5 * (i % 3)
                    s = (0.4, 0.08, 0.08) if tipos[i % 4] == Marker.ARROW else (0.3, 0.3, 0.3)
                    arr.markers.append(mk("solidos", i, tipos[i % 4], r * math.cos(ang), r * math.sin(ang), 0.2, s,
                                          colores[i % 4]))
                linea = mk("linea", 0, Marker.LINE_STRIP, 0.0, 0.0, 0.05, (0.03, 0.0, 0.0), (0.0, 1.0, 1.0))
                linea.points = [Point(x=1.5 * math.cos(j * 2 * math.pi / 49 + t * 0.2),
                                      y=1.5 * math.sin(j * 2 * math.pi / 49 + t * 0.2), z=0.0) for j in range(50)]
                arr.markers.append(linea)
                texto = mk("texto", 0, Marker.TEXT_VIEW_FACING, 0.0, 0.0, 1.0, (0.0, 0.0, 0.3), (1.0, 1.0, 1.0))
                texto.text = f"t={t:.0f}s"
                arr.markers.append(texto)
                p_marc.publish(arr)

            tics.append((2, marcadores))

        if "vida" in modos:
            def vida():                             # 2 Hz: 48 marcadores con lifetime 2 s; DELETEALL de vida_b cada 5 s
                t = seg()
                arr = MarkerArray()
                for i in range(48):
                    ns = "vida_a" if i < 24 else "vida_b"
                    arr.markers.append(mk(ns, i, Marker.CUBE, (i % 8) * 0.5 - 2.0, (i // 8) * 0.5 - 1.5, 0.1,
                                          (0.2, 0.2, 0.2), (1.0, 0.647, 0.0), vida=2.0))
                if int(t) % 5 == 0 and (t % 1) < 0.5:
                    arr.markers.append(mk("vida_b", 0, Marker.CUBE, 0, 0, 0, (1, 1, 1), (1, 1, 1),
                                          accion=Marker.DELETEALL))
                p_marc.publish(arr)

            tics.append((10, vida))

    # --- tf (V9) ------------------------------------------------------------------------------------------------
    if "tf" in modos:
        from tf2_msgs.msg import TFMessage
        from geometry_msgs.msg import TransformStamped
        from nav_msgs.msg import Odometry
        p_tf = n.create_publisher(TFMessage, "/tf", 100)
        p_tfs = n.create_publisher(TFMessage, "/tf_static", QoSProfile(
            depth=1, reliability=ReliabilityPolicy.RELIABLE, durability=DurabilityPolicy.TRANSIENT_LOCAL))
        odom = [None]
        n.create_subscription(Odometry, "/odom", lambda m: odom.__setitem__(0, m), 10)

        def ts(padre, hijo, x, y, z, yaw):
            t = TransformStamped()
            t.header.stamp = n.get_clock().now().to_msg()
            t.header.frame_id, t.child_frame_id = padre, hijo
            t.transform.translation.x, t.transform.translation.y, t.transform.translation.z = float(x), float(y), float(z)
            t.transform.rotation.z, t.transform.rotation.w = math.sin(yaw / 2), math.cos(yaw / 2)
            return t

        # TurtleBot3 burger [I: valores del URDF de TB3]; los mismos que `tf_estaticos` de godot/visor-ros/main.tscn.
        p_tfs.publish(TFMessage(transforms=[ts("base_link", "base_scan", -0.032, 0.0, 0.172, 0.0)]))

        def tf():                                   # 10 Hz: 8 dinámicos (+ odom → base_link de /odom)
            t = seg()
            arbol = [
                ("map", "odom", 0.5 + 0.2 * math.sin(t * 0.1), 0.3, 0.0, 0.1),
                ("base_link", "rueda_izq", 0.0, 0.08, 0.03, 0.0),
                ("base_link", "rueda_der", 0.0, -0.08, 0.03, 0.0),
                ("base_link", "torre", -0.05, 0.0, 0.25, t * 0.5),
                ("torre", "brazo", 0.1, 0.0, 0.05, math.sin(t)),
                ("brazo", "pinza", 0.15, 0.0, 0.0, 0.0),
                ("torre", "antena", 0.0, 0.0, 0.15, 0.0),
                ("base_link", "camara", 0.07, 0.0, 0.12, 0.0),
            ]
            out = [ts(*e) for e in arbol]
            o = odom[0]
            if o is not None:
                p, q = o.pose.pose.position, o.pose.pose.orientation
                e = ts("odom", "base_link", p.x, p.y, 0.0, 0.0)
                e.transform.rotation = q
                out.append(e)
            p_tf.publish(TFMessage(transforms=out))

        tics.append((2, tf))

    # --- percepción (V10) ----------------------------------------------------------------------------------------
    if "percepcion" in modos:
        tics.append((2, fuente_percepcion(n, seg)))

    def tic():
        k[0] += 1
        for cada, f in tics:
            if k[0] % cada == 0:
                f()

    n.create_timer(0.05, tic)
    n.get_logger().info(f"fuente_prueba_v2: {', '.join(modos)}" + (f" (n = {a.n})" if "marcadores" in modos else ""))
    try:
        rclpy.spin(n)
    except (KeyboardInterrupt, rclpy.executors.ExternalShutdownException):
        pass


def fuente_percepcion(n, seg):
    """Gate V10: cámara JPEG, detecciones 2D/3D y nube sintéticas a 10 Hz. Devuelve la función del tic."""
    import numpy as np
    from sensor_msgs.msg import CompressedImage, PointCloud2, PointField
    from vision_msgs.msg import (Detection2D, Detection2DArray, Detection3D, Detection3DArray,
                                 ObjectHypothesisWithPose)
    try:
        import cv2
    except ImportError:
        cv2 = None
    p_img = n.create_publisher(CompressedImage, "/camera/color/image_raw/compressed", 10)
    p_d2 = n.create_publisher(Detection2DArray, "/detections", 10)
    p_d3 = n.create_publisher(Detection3DArray, "/detections_3d", 10)
    p_nube = n.create_publisher(PointCloud2, "/points", 10)
    clases = ["persona", "coche", "perro", "bici"]
    rng = np.random.default_rng(1)
    yy, xx = np.mgrid[0:480, 0:640]
    fondo = np.stack([xx * 255 // 640, yy * 255 // 480, np.full_like(xx, 90)], axis=2).astype(np.int16)
    # Nube fija (paredes de un cuarto de 6 × 4 m y un cilindro), ≈ 6 000 puntos con algo de ruido
    a = np.linspace(0, 1, 500)
    paredes = []
    for z in np.linspace(0.0, 1.5, 3):
        paredes += [np.stack([a * 6 - 3, np.full_like(a, 2.0), np.full_like(a, z)], 1),
                    np.stack([a * 6 - 3, np.full_like(a, -2.0), np.full_like(a, z)], 1),
                    np.stack([np.full_like(a, 3.0), a * 4 - 2, np.full_like(a, z)], 1),
                    np.stack([np.full_like(a, -3.0), a * 4 - 2, np.full_like(a, z)], 1)]
    t = np.linspace(0, 2 * np.pi, 300)
    for z in np.linspace(0.0, 1.0, 4):
        paredes.append(np.stack([1.0 + 0.3 * np.cos(t), 0.5 + 0.3 * np.sin(t), np.full_like(t, z)], 1))
    nube = np.concatenate(paredes).astype(np.float32)

    def hip(clase, score):
        h = ObjectHypothesisWithPose()
        h.hypothesis.class_id = clase
        h.hypothesis.score = float(score)
        return h

    def tic():
        s = seg()
        stamp = n.get_clock().now().to_msg()
        # Cámara: degradado + 6 rectángulos que se mueven + ruido
        img = fondo.copy()
        for i in range(6):
            x0 = int(40 + i * 95 + 30 * math.sin(s + i)) % 560
            y0 = int(60 + (i % 3) * 120 + 20 * math.cos(s * 0.7 + i))
            img[y0:y0 + 80, x0:x0 + 60] = (200 - i * 30, 40 + i * 30, 220 - i * 20)
        img = np.clip(img + rng.integers(-10, 11, size=img.shape, dtype=np.int16), 0, 255).astype(np.uint8)
        m = CompressedImage()
        m.header.stamp, m.header.frame_id = stamp, "camara_optica"
        m.format = "rgb8; jpeg compressed bgr8"
        if cv2 is not None:
            m.data = cv2.imencode(".jpg", img[:, :, ::-1], [cv2.IMWRITE_JPEG_QUALITY, 85])[1].tobytes()
        else:
            import io
            from PIL import Image as PilImage
            b = io.BytesIO()
            PilImage.fromarray(img).save(b, "JPEG", quality=85)
            m.data = b.getvalue()
        p_img.publish(m)
        # Detecciones 2D: 20 cajas (el relay deja las 18 de más score)
        d2 = Detection2DArray()
        d2.header = m.header
        for i in range(20):
            d = Detection2D()
            d.id = f"d{i}"
            d.bbox.center.position.x = 40.0 + (i * 31 + 20 * math.sin(s + i)) % 560
            d.bbox.center.position.y = 60.0 + (i * 23) % 360
            d.bbox.size_x, d.bbox.size_y = 50.0 + (i % 4) * 10, 70.0
            d.results = [hip(clases[i % 4], 0.95 - i * 0.04)]
            d2.detections.append(d)
        p_d2.publish(d2)
        # Detecciones 3D: 14 cajas en «map» girando (el relay deja 12)
        d3 = Detection3DArray()
        d3.header.stamp, d3.header.frame_id = stamp, "map"
        for i in range(14):
            d = Detection3D()
            c = d.bbox.center
            c.position.x = 2.0 * math.cos(s * 0.2 + i * 0.45)
            c.position.y = 2.0 * math.sin(s * 0.2 + i * 0.45)
            c.position.z = 0.4
            c.orientation.z, c.orientation.w = math.sin(s * 0.5 + i), math.cos(s * 0.5 + i)
            d.bbox.size.x, d.bbox.size.y, d.bbox.size.z = 0.5, 0.3, 0.8
            d.results = [hip(clases[i % 4], 0.9 - i * 0.05)]
            d3.detections.append(d)
        p_d3.publish(d3)
        # Nube: la fija + ruido de 1 cm
        xyz = nube + rng.normal(0.0, 0.01, nube.shape).astype(np.float32)
        pc = PointCloud2()
        pc.header.stamp, pc.header.frame_id = stamp, "map"
        pc.height, pc.width = 1, len(xyz)
        pc.fields = [PointField(name=k, offset=4 * j, datatype=PointField.FLOAT32, count=1) for j, k in enumerate("xyz")]
        pc.is_bigendian, pc.point_step, pc.row_step, pc.is_dense = False, 12, 12 * len(xyz), True
        pc.data = xyz.tobytes()
        p_nube.publish(pc)

    return tic


if __name__ == "__main__":
    main()
