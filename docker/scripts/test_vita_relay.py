#!/usr/bin/env python3
"""Pruebas de las funciones puras de vita_relay.py (sin ROS): python3 docker/scripts/test_vita_relay.py"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vita_relay as vr  # noqa: E402


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


if __name__ == "__main__":
    test_scan(); test_tesela(); test_path(); test_limites()
    print("TODO OK")
