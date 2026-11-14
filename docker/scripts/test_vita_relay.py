#!/usr/bin/env python3
"""Pruebas de las funciones puras del relay (sin ROS): python3 docker/scripts/test_vita_relay.py

VC/1 (scan, tesela, path) y VC/1 rev. 2 (V6, doc 36 §5): cabecera común `trocear` con huellas cruzadas que
`godot/plantillas/pruebas/runner.gd` comprueba con `vc1.gd` (mismos bytes Python = GDScript), presupuesto de red y
perfiles (el relay NO arranca con «todo»), época del mapa, tamaños CDR exactos de Log y DiagnosticArray (contra
rosbags si está instalado, p. ej. con toolchains/rosbags-venv/bin/python), rosout, diagnostics, ritmo y relay_info."""
import math
import os
import random
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vita_relay as vr  # noqa: E402
import vita_relay_formatos as vf  # noqa: E402


def test_scan():
    rng = random.Random(1)
    for n in (180, 360, 720, 1081):
        ranges = [rng.uniform(0.2, 9.0) for _ in range(n)]
        ranges[5] = float("inf"); ranges[7] = float("nan"); ranges[9] = 0.05
        inc = 2 * math.pi / n
        d = vr.empaquetar_scan(ranges, -math.pi, inc, 0.12, 10.0, seq=3)
        assert d[3] <= 180 and len(d) == 4 + d[3]
        assert vr.cdr_multiarray(len(d), 2) <= vr.MAX_BE, (n, vr.cdr_multiarray(len(d), 2))
        pts = vr.desempaquetar_scan(d)
        paso = math.ceil(n / 180)
        for (a, r) in pts[:20]:
            k = round((a + math.pi) / inc)
            assert k % paso == 0
            assert abs(r - ranges[k]) <= 0.006, (r, ranges[k])
            assert abs(a - (-math.pi + k * inc)) < 1e-3
    print("scan ok")


def test_tesela():
    rng = random.Random(2)
    w, h = 70, 45                                # no múltiplos de 32: teselas de borde parciales
    data = [rng.choice([-1, 0, 10, 50, 80, 100]) for _ in range(w * h)]
    for ty in range(math.ceil(h / 32)):
        for tx in range(math.ceil(w / 32)):
            b = vr.empaquetar_tesela(data, w, h, tx, ty, 513)
            assert len(b) == 260 and vr.cdr_multiarray(len(b), 1) <= vr.MAX_BE
            ver, x, y, celdas = vr.desempaquetar_tesela(b)
            assert (ver, x, y) == (513, tx, ty)
            for j in range(32):
                for i in range(32):
                    gx, gy = tx * 32 + i, ty * 32 + j
                    esperado = vr.celda_2bit(data[gy * w + gx]) if gx < w and gy < h else 0
                    assert celdas[j * 32 + i] == esperado
    print("tesela ok")


def test_path():
    pts = [(i * 0.01, math.sin(i * 0.01) * 2) for i in range(2000)]
    d = vr.empaquetar_path(pts)
    n = int(d[0])
    assert n <= 57 and len(d) == 1 + 2 * n and vr.cdr_multiarray(len(d), 4) <= vr.MAX_BE
    assert (d[1], d[2]) == pts[0] and (d[-2], d[-1]) == pts[-1]
    recta = [(i * 0.1, 0.0) for i in range(100)]
    assert int(vr.empaquetar_path(recta)[0]) == 2
    print("path ok")


def test_limites():
    assert vr.cdr_multiarray(118, 4) <= vr.MAX_BE < vr.cdr_multiarray(119, 4)   # joints / Float32MultiArray
    assert vr.cdr_multiarray(6, 4) <= vr.MAX_BE                                 # pose2d
    print("límites ok")


# ============================================================================= VC/1 rev. 2 (V6)

# Huellas cruzadas: los MISMOS vectores y constantes están en godot/plantillas/pruebas/runner.gd (`_probar_vc1`).
# Si cambia el formato en un lado, falla la prueba de ese lado.
HUELLA_TROCEAR_F32 = "5da842991233e493fd04afd2d9c78df6"
HUELLA_TROCEAR_I16 = "e2c81111e76c4b212dd9b5340850a655"


def vector_trocear():
    return [[i * 3 - 50, i % 7, 1000 + i, -i] for i in range(40)]


def test_trocear():
    el = vector_trocear()
    t = vf.trocear(el, 4, (640, 480), seq=40000)
    assert [x[:6] for x in t] == [[40000 & 0x7FFF, 0, 2, 28, 640, 480], [40000 & 0x7FFF, 1, 2, 12, 640, 480]]
    assert len(t[0]) == vf.MAX_F32 and vf.cdr_multiarray(len(t[0]), 4) <= vf.MAX_BE
    assert vf.huella([v for x in t for v in x]) == HUELLA_TROCEAR_F32
    t2 = vf.trocear(el * 3, 4, (), seq=7, max_valores=vf.MAX_I16, max_trozos=3)   # 120 → corta a 3 × 58 = 174
    assert [x[3] for x in t2] == [58, 58, 4] and all(vf.cdr_multiarray(len(x), 2) <= vf.MAX_BE for x in t2)
    assert vf.huella([v for x in t2 for v in x]) == HUELLA_TROCEAR_I16
    t3 = vf.trocear(el * 10, 4, (), seq=1, max_trozos=3)                            # estado completo: ≤ 3 trozos
    assert len(t3) == 3 and sum(x[3] for x in t3) == 3 * 28
    assert vf.trocear([], 8, (), seq=1) == [[1, 0, 1, 0]]                           # vacío = un trozo con n = 0
    # Cuentas del catálogo (doc 36 §5.3): marcadores 11 × 10, puntos 36 × 3 + 4, det. 18 × 6 + 2, det3d 12 × 9,
    # poses 36 × 3, tf 8 × 8, nube 76 × 3 int16.
    for por, extra, n, esperado, tam in ((10, (), 11, 472, 4), (3, (0, 0, 0, 0), 36, 480, 4), (6, (0, 0), 18, 472, 4),
                                         (9, (), 12, 464, 4), (3, (), 36, 464, 4), (8, (), 8, 288, 4),
                                         (3, (), 76, 480, 2)):
        mx = vf.MAX_F32 if tam == 4 else vf.MAX_I16
        x = vf.trocear([[0] * por] * n, por, extra, max_valores=mx)
        assert len(x) == 1 and x[0][3] == n and vf.cdr_multiarray(len(x[0]), tam) == esperado, (por, n, len(x[0]))
    for x in t + t2:
        c = vf.cabecera(x)
        assert c is not None and c["n"] == x[3] and 0 <= c["trozo"] < c["n_trozos"]
    assert vf.cabecera([1, 2, 2, 0]) is None and vf.cabecera([1, 0, 0, 0]) is None and vf.cabecera([1, 0]) is None
    assert vf.cabecera([1, 0, 1, -1]) is None
    print("trocear y cabecera ok")


def test_presupuesto():
    kb, dgr = vf.comprobar_presupuesto(vf.PERFILES["hmi"])
    assert abs(kb - 19.1) < 0.1 and dgr == 108, (kb, dgr)                        # doc 36 §5.4: 19,2 / 108
    kb, dgr = vf.comprobar_presupuesto(vf.PERFILES["viz"])
    assert abs(kb - 35.0) < 0.05 and round(dgr) == 153, (kb, dgr)
    kb, dgr = vf.comprobar_presupuesto(vf.PERFILES["percepcion"])
    assert abs(kb - 40.0) < 0.05 and dgr == 154, (kb, dgr)
    try:
        vf.resolver_modulos(["todo"])
        assert False, "«todo» no debe arrancar"
    except ValueError as e:
        assert "65.9 KB/s" in str(e) and "229" in str(e) and "sobra «ritmo»" in str(e), e
    try:
        vf.resolver_modulos(["hmi", "camara", "nube", "marcadores", "tf", "costmap", "ritmo"])
        assert False
    except ValueError as e:
        assert "sobra" in str(e)
    mods, kb, dgr = vf.resolver_modulos(["hmi"])
    assert mods == ["scan", "pose", "joints", "mapa", "path", "rosout", "diag"] and kb < 20.0
    assert vf.resolver_modulos(["scan,pose"[0:4], "pose", "scan"])[0] == ["scan", "pose"]   # sin repetidos
    for malo in (["viz"], ["costmap"]):                                          # cabe, pero llega con V9–V11
        try:
            vf.resolver_modulos(malo)
            assert False
        except ValueError as e:
            assert "sin implementar" in str(e) and "V11" in str(e), e
    for malo in (["nada"], ["nucleo"], []):
        try:
            vf.resolver_modulos(malo)
            assert False
        except ValueError:
            pass
    # El relay se niega a arrancar con «todo» (sin ROS: modo --comprobar, mismo camino que el nodo).
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vita_relay.py")
    r = subprocess.run([sys.executable, script, "--comprobar", "todo"], capture_output=True, text=True)
    assert r.returncode == 1 and "NO arranca" in r.stdout, (r.returncode, r.stdout)
    r = subprocess.run([sys.executable, script, "--comprobar", "hmi"], capture_output=True, text=True)
    assert r.returncode == 0 and "19.1 KB/s" in r.stdout, r.stdout
    print("presupuesto ok")


def test_relay_info_y_epoca():
    s = vf.relay_info(["nucleo", "scan", "rosout"])
    assert s == "VC/1.2;scan,rosout" and vf.leer_relay_info(s) == ("VC/1.2", ["scan", "rosout"])
    assert vf.leer_relay_info("hola") is None and vf.leer_relay_info("VC/1.2;") == ("VC/1.2", [])
    geo = (0.05, 100, 80, -2.5, -2.0)
    v, nueva = vf.epoca_mapa(None, geo, 0)
    assert (v, nueva) == (1, True)
    assert vf.epoca_mapa(geo, geo, v) == (1, False)                              # mismo mapa: misma época
    assert vf.epoca_mapa(geo, (0.05, 100, 81, -2.5, -2.0), v) == (2, True)       # tamaño
    assert vf.epoca_mapa(geo, (0.05, 100, 80, -2.0, -2.0), v) == (2, True)       # origen
    assert vf.epoca_mapa(geo, (0.1, 100, 80, -2.5, -2.0), 0xFFFF) == (0, True)   # resolución; vuelta a 16 bit
    print("relay_info y época ok")


def test_rosout_y_diag():
    assert vf.compactar_log(20, "nodo", "info") is None
    n, t = vf.compactar_log(30, "n" * 100, "x" * 500)
    assert len(n) == vf.MAX_CAR_NOMBRE_LOG and len(t) == 200 and vf.cdr_log(n, t) <= vf.MAX_BE
    n, t = vf.compactar_log(40, "nodo", "€" * 200)                               # UTF-8 de 3 B: recorta más
    assert vf.cdr_log(n, t) <= vf.MAX_BE and 0 < len(t) < 200
    assert vf.cdr_log("a", "b") == 52                                            # comprobado con rosbags
    e = vf.compactar_estado(2, "d" * 60, "m" * 60, [("k%d" % i, "v" * 50) for i in range(5)])
    assert e[0] == 2 and len(e[1]) == 40 and len(e[2]) == 40 and len(e[3]) == 3 and len(e[3][0][1]) == 40
    assert vf.cdr_diag("", e[1], e[2], "", e[3]) <= vf.MAX_BE
    e = vf.compactar_estado(1, "é" * 40, "ü" * 40, [("ø" * 40, "ß" * 40)] * 3)
    assert vf.cdr_diag("", e[1], e[2], "", e[3]) <= vf.MAX_BE
    assert vf.cdr_diag("", "a", "b", "", []) == 56                               # comprobado con rosbags
    _comparar_con_rosbags()
    plan = vf.PlanDiag(repaso_s=1.0)
    plan.actualizar((0, "motor", "ok", []))
    plan.actualizar((0, "bateria", "ok", []))
    assert plan.siguiente(0.0)[1] == "motor" and plan.siguiente(0.1)[1] == "bateria"
    assert plan.siguiente(0.2) is None                                           # nada cambia y aún no toca repaso
    plan.actualizar((0, "motor", "ok", [("t", "41")]))                           # cambia un valor: no es «cambio»
    assert plan.siguiente(0.3) is None
    plan.actualizar((2, "motor", "caliente", []))                                # cambia el nivel: sale ya
    assert plan.siguiente(0.4)[0] == 2
    assert plan.siguiente(1.15)[1] == "bateria"                                  # repaso a 1 Hz por estado
    assert plan.siguiente(1.2) is None and plan.siguiente(1.45)[1] == "motor"
    print("rosout y diagnostics ok")


def _comparar_con_rosbags():
    try:
        from rosbags.typesys import Stores, get_typestore
    except ImportError:
        print("  (rosbags no instalado: tamaños CDR sin comparar; usar toolchains/rosbags-venv/bin/python)")
        return
    ts = get_typestore(Stores.ROS2_JAZZY)
    T = ts.types
    for nombre, texto in (("a", "b"), ("n" * 60, "ñ" * 200), ("", "")):
        m = T["rcl_interfaces/msg/Log"](stamp=T["builtin_interfaces/msg/Time"](sec=1, nanosec=2), level=30,
                                         name=nombre, msg=texto, file="", function="", line=0)
        assert len(ts.serialize_cdr(m, "rcl_interfaces/msg/Log")) == vf.cdr_log(nombre, texto)
    for fr, nom, msg, pares in (("", "a", "b", []), ("map", "n" * 40, "é" * 40, [("k", "v")] * 3)):
        st = T["diagnostic_msgs/msg/DiagnosticStatus"](level=1, name=nom, message=msg, hardware_id="", values=[
            T["diagnostic_msgs/msg/KeyValue"](key=k, value=v) for k, v in pares])
        m = T["diagnostic_msgs/msg/DiagnosticArray"](header=T["std_msgs/msg/Header"](
            stamp=T["builtin_interfaces/msg/Time"](sec=0, nanosec=0), frame_id=fr), status=[st])
        assert len(ts.serialize_cdr(m, "diagnostic_msgs/msg/DiagnosticArray")) == vf.cdr_diag(fr, nom, msg, "", pares)
    print("  tamaños CDR = rosbags")


# V9 (doc 36 §5.3): huellas de bits float32 que `godot/plantillas/pruebas/visor_tf.gd` comprueba con `vc1.gd`.
HUELLA_POSE_COV = "919121b347346f313e0ec41b5b0132c7"
HUELLA_POSES = "52d3f6f9108908b2abd20f08ce668f4d"
HUELLA_TF = "474c8b147c4b652f59c1959f628dbd40"
HUELLA_TF_ESTATICO = "3b84bb423aeaedebed5039a2aa5ab62e"


def vectores_v9():
    """Los mismos vectores que `_probar_bytes` de pruebas/visor_tf.gd."""
    cov = [i * 0.01 - 0.1 for i in range(36)]
    poses = [(i * 0.25 - 3, (i % 7) * 0.5, (i % 13) * 0.125 - 0.75) for i in range(100)]
    items = [[k, k * 0.5, -k * 0.25, 0.1 * k, 0, 0, 0.6, 0.8] for k in range(10)]
    return cov, poses, items


def test_tf_poses():
    cov, poses, items = vectores_v9()
    pc = vf.empaquetar_pose_cov(1.5, -2.25, 0.3, cov)
    assert len(pc) == 7 and vf.cdr_multiarray(7, 4) == 44 and pc[3] == cov[0] and pc[6] == cov[35]
    assert vf.huella_f32_bits(pc) == HUELLA_POSE_COV
    tp = vf.empaquetar_poses(poses, 40000)
    c = vf.cabecera(tp)
    assert c == {"seq": 7232, "trozo": 0, "n_trozos": 1, "n": 34}            # 100 poses, paso 3 → 34
    assert vf.cdr_multiarray(len(tp), 4) <= vf.cdr_multiarray(4 + 3 * vf.MAX_POSES, 4) == 464 <= vf.MAX_BE
    assert vf.huella_f32_bits(tp) == HUELLA_POSES
    assert vf.leer_poses(tp)[1] == tuple(float(v) for v in poses[3])
    assert len(vf.diezmar(list(range(36)), 36)) == 36 and vf.diezmar(list(range(37)), 36) == list(range(0, 37, 2))
    tt = vf.empaquetar_tf(items, 7)
    assert vf.cabecera(tt)["n"] == 8 and vf.cdr_multiarray(len(tt), 4) == 288 <= vf.MAX_BE
    assert vf.huella_f32_bits(tt) == HUELLA_TF
    te = vf.empaquetar_tf(items * 2, 3, vf.MAX_TF_ESTATICOS)
    assert vf.cabecera(te)["n"] == 16 and vf.cdr_multiarray(len(te), 4) == 544 <= 1100
    assert vf.huella_f32_bits(te) == HUELLA_TF_ESTATICO
    # TablaTf: lista blanca, índices estables, tope de 8 dinámicos y estáticos «al cambiar».
    tabla = vf.TablaTf(["odom", "/base_link"] + [f"f{i}" for i in range(10)])
    assert tabla.dinamico("map", "odom", (1, 2, 0), (0, 0, 0, 1))
    assert not tabla.dinamico("odom", "rueda", (0, 0, 0), (0, 0, 0, 1))            # fuera de la lista blanca
    assert tabla.estatico("base_link", "base_scan", (-0.032, 0, 0.172), (0, 0, 0, 1)) and tabla.cambio_estaticos
    assert tabla.texto_marcos() == "map>odom,base_link>base_scan" and tabla.cambio_marcos
    tabla.cambio_estaticos = False
    assert tabla.estatico("base_link", "base_scan", (-0.032, 0, 0.172), (0, 0, 0, 1)) and not tabla.cambio_estaticos
    for i in range(10):
        tabla.dinamico("odom", f"f{i}", (i, 0, 0), (0, 0, 0, 1))
    assert len(tabla.dinamicos) == 8 and vf.cabecera(tabla.trozo_tf(1))["n"] == 8
    t = tabla.trozo_tf(2)
    assert t[4:12] == [0, 1, 2, 0, 0, 0, 0, 1]                                          # idx 0 = map>odom
    assert vf.cabecera(tabla.trozo_estatico())["n"] == 1 and tabla.trozo_estatico()[4] == 1
    # Presupuesto: perfil viz ya no dice que faltan pose_cov, poses ni tf (los de V8/V11 pueden faltar aún).
    try:
        vf.resolver_modulos(["pose_cov", "poses", "tf"])
    except ValueError as e:
        assert False, e
    print("tf, poses y pose_cov ok")


def test_ritmo():
    r = vf.parsear_ritmo(["imu=/imu/data@20", " temp=/temperature@2.5 ", ""])
    assert r == [("imu", "/imu/data", 20.0), ("temp", "/temperature", 2.5)]
    for malo in (["imu:/imu@20"], ["IMU=/imu@20"], ["imu=/imu@0"], ["imu=/imu@31"], ["a=/a@20", "b=/b@11"],
                 ["a=/a@1", "a=/b@1"], ["a=sin_barra@1"]):
        try:
            vf.parsear_ritmo(malo)
            assert False, malo
        except ValueError:
            pass
    cubo = vf.CuboBytes(1000)
    assert cubo.permitir(600, 0.0) and not cubo.permitir(600, 0.5) and cubo.permitir(400, 0.6)
    assert cubo.permitir(1000, 1.1) and not cubo.permitir(1, 1.2)
    print("ritmo ok")


# ============================================================================= marcadores (V8)

# Huellas cruzadas con godot/plantillas/pruebas/visor_marcadores.gd (`_probar_bytes`): mismos vectores, mismos bytes
# float32 (PackedFloat32Array.to_byte_array().hex_encode().md5_text()) y el mismo texto.
HUELLA_MARCADORES = "a2f417e25439969dec1637dd4cd66bdd"
HUELLA_PUNTOS = "170eed3a87485e2bf9c13e4ccc2e400a"
HUELLA_TEXTO = "32eb49e4a031452af4e90ddeff303c72"
CLAVE_VISOR_3 = 14529283


def vector_marcadores():
    """(ns, id, tipo, x, y, z, yaw, sx, sy, sz, r, g, b, a) × 33: los mismos en visor_marcadores.gd."""
    cols = [(0.9, 0.1, 0.1), (0.1, 0.8, 0.2), (0.15, 0.35, 1.0), (1.0, 1.0, 0.0), (0.5, 0.25, 0.75), (0.3, 0.3, 0.3)]
    out = []
    for i in range(33):
        r, g, b = cols[i % len(cols)]
        out.append(("ns%d" % (i % 4), i * 7 - 20, i % 4, i * 0.25 - 3.0, 1.5 - i * 0.125, 0.0625 * (i % 5),
                    -1.5 + i * 0.09375, 0.5 + (i % 3) * 0.25, 0.25, 0.75, r, g, b, (i % 4) / 3.0))
    return out


def elementos_marcadores():
    return [[vf.clave_marcador(ns, i), t, x, y, z, yaw, sx, sy, sz, vf.color_marcador(vf.indice_paleta(r, g, b), a)]
            for (ns, i, t, x, y, z, yaw, sx, sy, sz, r, g, b, a) in vector_marcadores()]


def puntos_prueba():
    return [(i * 0.5 - 4.0, (i % 6) * 0.25, 0.125 * (i % 3)) for i in range(50)]


def _Ns(**k):
    from types import SimpleNamespace
    return SimpleNamespace(**k)


def marker(ns="a", ident=0, tipo=1, accion=0, frame="map", pos=(0.0, 0.0, 0.0), q=(0.0, 0.0, 0.0, 1.0),
           escala=(1.0, 1.0, 1.0), color=(1.0, 0.0, 0.0, 1.0), puntos=(), texto="", vida=0.0, locked=False):
    P = lambda x, y, z: _Ns(x=x, y=y, z=z)  # noqa: E731
    return _Ns(ns=ns, id=ident, type=tipo, action=accion, header=_Ns(frame_id=frame),
               pose=_Ns(position=P(*pos), orientation=_Ns(x=q[0], y=q[1], z=q[2], w=q[3])), scale=P(*escala),
               color=_Ns(r=color[0], g=color[1], b=color[2], a=color[3]), points=[P(*p) for p in puntos],
               text=texto, lifetime=_Ns(sec=int(vida), nanosec=int((vida % 1) * 1e9)), frame_locked=locked)


def test_marcadores():
    # Formato y tamaños: 33 marcadores = 3 trozos de ≤ 472 B; puntos ≤ 480 B; textos ≤ 80 car.
    el = elementos_marcadores()
    t = vf.empaquetar_marcadores(el, seq=70000)
    assert len(t) == 3 and [x[3] for x in t] == [11, 11, 11] and t[0][0] == 70000 & 0x7FFF
    assert all(vf.cdr_multiarray(len(x), 4) <= 472 for x in t) and vf.cdr_multiarray(len(t[0]), 4) == 472
    assert len(vf.empaquetar_marcadores(el + el, 1)) == 3                        # tope 33 (estado completo)
    assert vf.empaquetar_marcadores([], 5) == [[5, 0, 1, 0]]                     # vacío: borra todo en la Vita
    pts = vf.empaquetar_puntos(vf.clave_marcador("lineas", 2), 4, vf.color_marcador(2, 1.0), 0.05, puntos_prueba(), 9)
    assert [x[3] for x in pts] == [36, 14] and all(vf.cdr_multiarray(len(x), 4) <= 480 for x in pts)
    assert pts[0][4:8] == [vf.clave_marcador("lineas", 2), 4, 2 + 256 * 15, 0.05]
    assert sum(x[3] for x in vf.empaquetar_puntos(1, 8, 0, 0.1, [(0, 0, 0)] * 500, 1)) == 108   # tope 3 trozos
    tx = vf.texto_marcador(vf.clave_marcador("txt", 1), 1.25, -2.5, 0.125, "hola|mundo " + "x" * 100)
    assert len(tx.split("|", 4)[4]) == 80 and vf.leer_texto_marcador(tx)[4].startswith("hola|mundo")
    assert vf.leer_texto_marcador("1|2|3") is None
    # Claves y colores exactos en float32
    assert all(0 <= vf.clave_marcador("n" * k, i) <= 0xFFFFFF for k in range(5) for i in (-5, 0, 2 ** 31 - 1))
    assert vf.clave_marcador("visor", 3) != vf.clave_marcador("visor", 4) != vf.clave_marcador("otro", 3)
    assert vf.color_marcador(255, 1.0) == 4095 and vf.color_marcador(7, 0.0) == 7 and vf.color_marcador(3, 0.5) == 3 + 256 * 8
    assert vf.indice_paleta(1, 1, 1) == 0 and vf.indice_paleta(0.9, 0.1, 0.1) == 2 and vf.indice_paleta(1, 0.647059, 0) == 8
    plano = [v for x in t for v in x]
    plano_p = [v for x in pts for v in x]
    assert vf.huella_f32(plano) == HUELLA_MARCADORES
    assert vf.huella_f32(plano_p) == HUELLA_PUNTOS and _md5(tx) == HUELLA_TEXTO
    assert vf.clave_marcador("visor", 3) == CLAVE_VISOR_3
    # Semántica (marker_common.cpp): ADD/MODIFY, DELETE, DELETEALL por ns, recrear, NaN, lifetime, frame_locked.
    e = vf.EstadoMarcadores()
    fijo = lambda f: vf.IDENTIDAD if f in ("", "map") else None  # noqa: E731
    for i in range(3):
        e.aplicar(marker("a", i, 1, pos=(i, 0, 0)), 0.0)
    e.aplicar(marker("b", 0, 2), 0.0)
    m, p, x = e.ciclo(0.0, fijo)
    assert len(m) == 4 and m[0][2] == 0.0 and m[2][2] == 2.0
    e.aplicar(marker("a", 1, 1, pos=(5, 0, 0)), 0.1)                             # MODIFY: misma entrada
    e.aplicar(marker("a", 1, 3, accion=1, pos=(6, 0, 0)), 0.1)                   # cambia el tipo: se recrea al final
    m, _, _ = e.ciclo(0.1, fijo)
    assert [r[1] for r in m] == [1, 1, 2, 3] and m[-1][2] == 6.0
    e.aplicar(marker("a", 0, accion=2), 0.2)                                     # DELETE
    assert len(e.ciclo(0.2, fijo)[0]) == 3
    e.aplicar(marker("a", accion=3), 0.3)                                        # DELETEALL de «a»
    m, _, _ = e.ciclo(0.3, fijo)
    assert len(m) == 1 and m[0][1] == 2
    e.aplicar(marker("c", 0, 1, pos=(float("nan"), 0, 0)), 0.3)
    assert e.rechazados == 1 and len(e.ciclo(0.3, fijo)[0]) == 1
    e.aplicar(marker("v", 0, 1, vida=0.5), 1.0)
    assert len(e.ciclo(1.4, fijo)[0]) == 2 and len(e.ciclo(1.6, fijo)[0]) == 1    # reloj de recepción
    e.aplicar(marker("", 0, accion=3), 2.0)                                      # DELETEALL sin ns: todo
    assert e.ciclo(2.0, fijo)[0] == []
    # Marco: yaw y TF; sin TF no se manda; frame_locked se resuelve cada ciclo, sin él una sola vez.
    tf = {"base": ((1.0, 2.0, 0.0), (0.0, 0.0, math.sin(math.pi / 4), math.cos(math.pi / 4)))}
    res = lambda f: vf.IDENTIDAD if f == "map" else tf.get(f)  # noqa: E731
    e.aplicar(marker("t", 0, 0, frame="base", pos=(1, 0, 0), escala=(1, 0.1, 0.1)), 3.0)
    e.aplicar(marker("t", 1, 1, frame="base", locked=True), 3.0)
    e.aplicar(marker("t", 2, 1, frame="sin_tf"), 3.0)
    m, _, _ = e.ciclo(3.0, res)
    assert len(m) == 2 and e.sin_tf == 1
    assert abs(m[0][2] - 1.0) < 1e-9 and abs(m[0][3] - 3.0) < 1e-9 and abs(m[0][5] - math.pi / 2) < 1e-9
    tf["base"] = ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0))
    m, _, _ = e.ciclo(3.2, res)
    assert abs(m[0][3] - 3.0) < 1e-9 and abs(m[1][2]) < 1e-9 and abs(m[1][3]) < 1e-9   # sin locked / locked
    # Puntos, listas, textos y flecha por 2 puntos
    e = vf.EstadoMarcadores()
    e.aplicar(marker("l", 0, 4, pos=(1, 0, 0), escala=(0.05, 0, 0), puntos=[(0, 0, 0), (1, 1, 0)]), 0.0)
    e.aplicar(marker("l", 1, 9, pos=(0, 0, 2), texto="hola"), 0.0)
    e.aplicar(marker("l", 2, 0, puntos=[(0, 0, 0), (0, 2, 0)], escala=(0.05, 0.1, 0.0)), 0.0)
    e.aplicar(marker("l", 3, 11, puntos=[(0, 0, 0)] * 3), 0.0)
    m, p, x = e.ciclo(0.0, fijo)
    k0, k1 = vf.clave_marcador("l", 0), vf.clave_marcador("l", 1)
    assert [r[1] for r in m] == [4, 9, 0] and e.ignorados == 1                   # TRIANGLE_LIST no viaja
    assert p[k0] == (4, vf.color_marcador(vf.indice_paleta(1, 0, 0), 1.0), 0.05, [(1, 0, 0), (2, 1, 0)])
    assert x[k1] == (0, 0, 2, "hola")
    assert abs(m[2][5] - math.pi / 2) < 1e-9 and abs(m[2][6] - 2.0) < 1e-9 and abs(m[2][7] - 0.05) < 1e-9
    e = vf.EstadoMarcadores()
    for i in range(40):
        e.aplicar(marker("n", i, 1), 0.0)
    assert len(e.ciclo(0.0, fijo)[0]) == 33 and e.cortados == 7
    # Ronda: primero lo que cambia, después repaso; lo que desaparece se olvida.
    r = vf.PlanRonda()
    r.actualizar({1: "a", 2: "b"})
    assert [r.siguiente()[0] for _ in range(4)] == [1, 2, 1, 2]
    r.actualizar({1: "a", 2: "B", 3: "c"})
    assert [r.siguiente()[0] for _ in range(2)] == [2, 3]
    r.actualizar({3: "c"})
    assert r.siguiente()[0] == 3 and r.siguiente()[0] == 3
    r.actualizar({})
    assert r.siguiente() is None
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vita_relay.py")
    rr = subprocess.run([sys.executable, script, "--comprobar", "hmi,marcadores"], capture_output=True, text=True)
    assert rr.returncode == 0 and "marcadores" in rr.stdout, rr.stdout
    print("marcadores ok")


def _md5(s):
    import hashlib
    return hashlib.md5(s.encode()).hexdigest()


if __name__ == "__main__":
    test_tf_poses()                                                       # V9
    test_scan(); test_tesela(); test_path(); test_limites()
    test_trocear(); test_presupuesto(); test_relay_info_y_epoca(); test_rosout_y_diag(); test_ritmo()
    test_marcadores()
    print("TODO OK")
