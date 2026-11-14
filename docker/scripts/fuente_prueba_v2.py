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

Uso (dentro de la estación): python3 fuente_prueba_v2.py avisos,marcadores,tf [--n 31]
"""
import argparse
import math
import sys

MARCOS_TF = ["odom", "rueda_izq", "rueda_der", "torre", "brazo", "pinza", "antena", "camara"]   # 8 = MAX_TF


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("modos", help="avisos, marcadores, vida, tf (separados por comas)")
    ap.add_argument("--n", type=int, default=31, help="sólidos del modo marcadores (defecto 31)")
    a = ap.parse_args()
    modos = [m.strip() for m in a.modos.split(",") if m.strip()]
    malos = [m for m in modos if m not in ("avisos", "marcadores", "vida", "tf")]
    if malos or not modos:
        print(f"modo desconocido: {malos or '(ninguno)'}; válidos: avisos, marcadores, vida, tf", file=sys.stderr)
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


if __name__ == "__main__":
    main()
