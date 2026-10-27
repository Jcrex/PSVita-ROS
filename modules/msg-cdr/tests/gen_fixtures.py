#!/usr/bin/env python3
"""Genera los binarios CDR de prueba de msg-cdr (tests/fixtures/*.bin).

Fuente de verdad de los DATOS: las definiciones de mensajes de ROS2 Jazzy que
trae el paquete `rosbags` (store ROS2_JAZZY) — no se escribieron de memoria.
Cada .bin es el resultado de `serialize_cdr` (CDR little-endian XCDR1) e
INCLUYE los 4 bytes de encapsulación (00 01 00 00).

Uso (la laptop no instala nada globalmente: usar un venv desechable):
    python3 -m venv /tmp/rbvenv && /tmp/rbvenv/bin/pip install rosbags
    /tmp/rbvenv/bin/python modules/msg-cdr/tests/gen_fixtures.py

Verificación cruzada con ROS2 REAL (hacer en el PC / contenedor robotnik_dev,
docs/10 §D2): serializar los mismos mensajes con rclpy.serialization y
comparar con `cmp`. Mientras eso no se haga, estas fixtures son
"independientes pero no oficiales".
"""
import pathlib

import numpy as np  # dependencia de rosbags

from rosbags.typesys import Stores, get_typestore

ts = get_typestore(Stores.ROS2_JAZZY)
T = ts.types
OUT = pathlib.Path(__file__).parent / "fixtures"
OUT.mkdir(exist_ok=True)


def save(name, msg, typename):
    data = bytes(ts.serialize_cdr(msg, typename))
    assert data[:4] == b"\x00\x01\x00\x00", data[:4]
    (OUT / name).write_bytes(data)
    print(f"{name}: {len(data)} bytes")


def time(sec, nsec):
    return T["builtin_interfaces/msg/Time"](sec=sec, nanosec=nsec)


def header(sec, nsec, frame):
    return T["std_msgs/msg/Header"](stamp=time(sec, nsec), frame_id=frame)


def vec3(x, y, z):
    return T["geometry_msgs/msg/Vector3"](x=x, y=y, z=z)


def point(x, y, z):
    return T["geometry_msgs/msg/Point"](x=x, y=y, z=z)


def quat(x, y, z, w):
    return T["geometry_msgs/msg/Quaternion"](x=x, y=y, z=z, w=w)


def tfs(sec, nsec, parent, child, t, q):
    return T["geometry_msgs/msg/TransformStamped"](
        header=header(sec, nsec, parent),
        child_frame_id=child,
        transform=T["geometry_msgs/msg/Transform"](
            translation=vec3(*t), rotation=quat(*q)
        ),
    )


# ---- TFMessage -------------------------------------------------------------
tf_msg = T["tf2_msgs/msg/TFMessage"]
save(
    "tf_two.bin",
    tf_msg(transforms=[
        tfs(1234, 5678, "odom", "base_link", (1.5, -2.25, 0.5),
            (0.0, 0.0, 0.70710678, 0.70710678)),
        tfs(1234, 5678, "base_link", "laser", (0.1, 0.0, 0.2), (0.0, 0.0, 0.0, 1.0)),
    ]),
    "tf2_msgs/msg/TFMessage",
)
save(
    "tf_long_names.bin",
    tf_msg(transforms=[tfs(1, 2, "p" * 80, "c" * 70, (1.0, 2.0, 3.0), (0, 0, 0, 1.0))]),
    "tf2_msgs/msg/TFMessage",
)
save(
    "tf_many.bin",
    tf_msg(transforms=[
        tfs(i, 0, "world", f"link_{i}", (float(i), 0.0, 0.0), (0, 0, 0, 1.0))
        for i in range(40)
    ]),
    "tf2_msgs/msg/TFMessage",
)
save("tf_empty.bin", tf_msg(transforms=[]), "tf2_msgs/msg/TFMessage")

# ---- JointState --------------------------------------------------------------
js = T["sensor_msgs/msg/JointState"]
save(
    "joints.bin",
    js(header=header(7, 8, ""),
       name=["wheel_left", "wheel_right", "arm_joint_1"],
       position=np.array([0.5, -1.25, 3.0]),
       velocity=np.array([], dtype=np.float64),
       effort=np.array([0.125, 0.25, 0.375])),
    "sensor_msgs/msg/JointState",
)
save(
    "joints_many.bin",
    js(header=header(1, 2, "base"),
       name=[f"j{i}" for i in range(34)],
       position=np.arange(34, dtype=np.float64),
       velocity=np.array([], dtype=np.float64),
       effort=np.array([], dtype=np.float64)),
    "sensor_msgs/msg/JointState",
)

# ---- OccupancyGrid -----------------------------------------------------------
og = T["nav_msgs/msg/OccupancyGrid"]
meta = T["nav_msgs/msg/MapMetaData"](
    map_load_time=time(50, 60),
    resolution=0.5,
    width=4,
    height=4,
    origin=T["geometry_msgs/msg/Pose"](position=point(-1.0, -2.0, 0.0),
                                       orientation=quat(0, 0, 0, 1.0)),
)
save(
    "map_4x4.bin",
    og(header=header(100, 0, "map"), info=meta,
       data=np.array([-1, 0, 100, 50, -1, -1, 0, 0, 100, 100, 25, 75, 0, 1, 2, 99],
                     dtype=np.int8)),
    "nav_msgs/msg/OccupancyGrid",
)

# ---- Marker ------------------------------------------------------------------
mk = T["visualization_msgs/msg/Marker"]
rgba = T["std_msgs/msg/ColorRGBA"]


def marker(**kw):
    base = dict(
        header=header(9, 10, "base_link"),
        ns="robot", id=7, type=1, action=0,
        pose=T["geometry_msgs/msg/Pose"](position=point(1.0, 2.0, 3.0),
                                         orientation=quat(0, 0, 0, 1.0)),
        scale=vec3(0.5, 0.5, 0.5),
        color=rgba(r=1.0, g=0.5, b=0.25, a=1.0),
        lifetime=T["builtin_interfaces/msg/Duration"](sec=3, nanosec=500),
        frame_locked=True,
        points=[], colors=[],
        texture_resource="",
        texture=T["sensor_msgs/msg/CompressedImage"](
            header=header(0, 0, ""), format="", data=np.zeros(0, dtype=np.uint8)),
        uv_coordinates=[],
        text="",
        mesh_resource="",
        mesh_file=T["visualization_msgs/msg/MeshFile"](
            filename="", data=np.zeros(0, dtype=np.uint8)),
        mesh_use_embedded_materials=False,
    )
    base.update(kw)
    return mk(**base)


save("marker_cube.bin", marker(), "visualization_msgs/msg/Marker")
save(
    "marker_line.bin",
    marker(
        type=4, id=8, ns="path", frame_locked=False,
        points=[point(0, 0, 0), point(1.0, 0.5, 0.25), point(2.0, 1.0, 0.5)],
        colors=[rgba(r=1.0, g=0, b=0, a=1.0), rgba(r=0, g=1.0, b=0, a=1.0),
                rgba(r=0, g=0, b=1.0, a=0.5)],
        text="hola",
    ),
    "visualization_msgs/msg/Marker",
)
