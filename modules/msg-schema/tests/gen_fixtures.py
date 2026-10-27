#!/usr/bin/env python3
"""Genera schema.rsch + casos (.bin/.type/.dump) del test de msg-schema.

Cada caso es un mensaje construido con `rosbags` (definiciones reales de ROS2
Jazzy). `<caso>.bin` = serialize_cdr (con encapsulación de 4 bytes),
`<caso>.dump` = volcado canónico del OBJETO Python (independiente del CDR) y
`<caso>.type` = nombre del tipo. Los tests de C y Rust deben reproducir el
volcado al decodificar y los mismos bytes al codificar.

Uso:  /tmp/rbvenv/bin/python modules/msg-schema/tests/gen_fixtures.py
"""
import importlib.util
import pathlib

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location("gen_msg_schema", ROOT / "tools" / "gen_msg_schema.py")
gms = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gms)

ts = gms.typestore()
T = ts.types
OUT = HERE / "fixtures"
OUT.mkdir(exist_ok=True)
cases = {}


def time(s, ns):
    return T["builtin_interfaces/msg/Time"](sec=s, nanosec=ns)


def header(s, ns, frame):
    return T["std_msgs/msg/Header"](stamp=time(s, ns), frame_id=frame)


def v3(x, y, z):
    return T["geometry_msgs/msg/Vector3"](x=x, y=y, z=z)


def pt(x, y, z):
    return T["geometry_msgs/msg/Point"](x=x, y=y, z=z)


def q(x, y, z, w):
    return T["geometry_msgs/msg/Quaternion"](x=x, y=y, z=z, w=w)


def pose(p, o):
    return T["geometry_msgs/msg/Pose"](position=p, orientation=o)


def add(name, typename, msg):
    cases[name] = (typename, msg)


# --- std_msgs ---------------------------------------------------------------
add("string", "std_msgs/msg/String", T["std_msgs/msg/String"](data="hola Vita"))
add("string_empty", "std_msgs/msg/String", T["std_msgs/msg/String"](data=""))
add("bool", "std_msgs/msg/Bool", T["std_msgs/msg/Bool"](data=True))
add("int16", "std_msgs/msg/Int16", T["std_msgs/msg/Int16"](data=-1234))
add("uint64", "std_msgs/msg/UInt64", T["std_msgs/msg/UInt64"](data=2**63 + 5))
add("int8", "std_msgs/msg/Int8", T["std_msgs/msg/Int8"](data=-7))
add("float32", "std_msgs/msg/Float32", T["std_msgs/msg/Float32"](data=-2.5))
add("empty", "std_msgs/msg/Empty", T["std_msgs/msg/Empty"](structure_needs_at_least_one_member=0))
add("f64_array", "std_msgs/msg/Float64MultiArray", T["std_msgs/msg/Float64MultiArray"](
    layout=T["std_msgs/msg/MultiArrayLayout"](
        dim=[T["std_msgs/msg/MultiArrayDimension"](label="rows", size=2, stride=6),
             T["std_msgs/msg/MultiArrayDimension"](label="cols", size=3, stride=3)],
        data_offset=0),
    data=np.array([1.5, -2.0, 3.25, 4.0, 5.0, 6.5])))
# --- geometry ---------------------------------------------------------------
add("twist", "geometry_msgs/msg/Twist", T["geometry_msgs/msg/Twist"](
    linear=v3(0.5, 0.0, -0.25), angular=v3(0.0, 0.125, 1.5)))
add("pose_stamped", "geometry_msgs/msg/PoseStamped", T["geometry_msgs/msg/PoseStamped"](
    header=header(10, 20, "map"), pose=pose(pt(1.0, 2.0, 3.0), q(0, 0, 0.5, 0.5))))
# --- sensor_msgs ------------------------------------------------------------
cov = np.arange(9, dtype=np.float64) * 0.5
add("imu", "sensor_msgs/msg/Imu", T["sensor_msgs/msg/Imu"](
    header=header(100, 200, "imu_link"), orientation=q(0, 0, 0, 1.0),
    orientation_covariance=cov, angular_velocity=v3(0.01, 0.02, 0.03),
    angular_velocity_covariance=cov * 2, linear_acceleration=v3(0.0, 0.0, 9.81),
    linear_acceleration_covariance=cov * 3))
add("joy", "sensor_msgs/msg/Joy", T["sensor_msgs/msg/Joy"](
    header=header(1, 2, "joy"), axes=np.array([0.0, -1.0, 0.5, 0.25], dtype=np.float32),
    buttons=np.array([1, 0, 0, 1, 1], dtype=np.int32)))
add("laser", "sensor_msgs/msg/LaserScan", T["sensor_msgs/msg/LaserScan"](
    header=header(5, 6, "laser"), angle_min=-1.5, angle_max=1.5, angle_increment=0.5,
    time_increment=0.001, scan_time=0.1, range_min=0.15, range_max=12.0,
    ranges=np.array([1.0, 2.5, 3.0, 4.5, 5.0, 6.5, 7.0], dtype=np.float32),
    intensities=np.array([], dtype=np.float32)))
add("image", "sensor_msgs/msg/Image", T["sensor_msgs/msg/Image"](
    header=header(7, 8, "camera"), height=4, width=5, encoding="rgba8", is_bigendian=0,
    step=20, data=np.arange(80, dtype=np.uint8)))
add("compressed", "sensor_msgs/msg/CompressedImage", T["sensor_msgs/msg/CompressedImage"](
    header=header(9, 9, "cam"), format="jpeg", data=np.array([255, 216, 255, 224, 0, 16], dtype=np.uint8)))
add("navsat", "sensor_msgs/msg/NavSatFix", T["sensor_msgs/msg/NavSatFix"](
    header=header(1, 1, "gps"),
    status=T["sensor_msgs/msg/NavSatStatus"](status=0, service=1),
    latitude=42.8125, longitude=-1.6458, altitude=450.5,
    position_covariance=np.array([0.25, 0, 0, 0, 0.25, 0, 0, 0, 1.44]), position_covariance_type=2))
add("joint_state", "sensor_msgs/msg/JointState", T["sensor_msgs/msg/JointState"](
    header=header(7, 8, ""), name=["wheel_left", "wheel_right", "arm_joint_1"],
    position=np.array([0.5, -1.25, 3.0]), velocity=np.array([], dtype=np.float64),
    effort=np.array([0.125, 0.25, 0.375])))
add("battery", "sensor_msgs/msg/BatteryState", T["sensor_msgs/msg/BatteryState"](
    header=header(1, 2, "bat"), voltage=12.5, temperature=30.0, current=-1.5, charge=2.0,
    capacity=3.0, design_capacity=3.5, percentage=0.75, power_supply_status=2,
    power_supply_health=1, power_supply_technology=3, present=True,
    cell_voltage=np.array([4.1, 4.2, 4.15], dtype=np.float32), cell_temperature=np.array([], dtype=np.float32),
    location="slot1", serial_number="SN-0042"))
# --- nav / tf / viz ---------------------------------------------------------
cov36 = np.arange(36, dtype=np.float64) * 0.01
add("odometry", "nav_msgs/msg/Odometry", T["nav_msgs/msg/Odometry"](
    header=header(11, 12, "odom"), child_frame_id="base_link",
    pose=T["geometry_msgs/msg/PoseWithCovariance"](pose=pose(pt(1.5, -2.25, 0.0), q(0, 0, 0.7071, 0.7071)), covariance=cov36),
    twist=T["geometry_msgs/msg/TwistWithCovariance"](
        twist=T["geometry_msgs/msg/Twist"](linear=v3(0.3, 0, 0), angular=v3(0, 0, 0.1)), covariance=cov36 * 2)))


def tfs(parent, child, t):
    return T["geometry_msgs/msg/TransformStamped"](
        header=header(1234, 5678, parent), child_frame_id=child,
        transform=T["geometry_msgs/msg/Transform"](translation=v3(*t), rotation=q(0, 0, 0, 1.0)))


add("tf", "tf2_msgs/msg/TFMessage", T["tf2_msgs/msg/TFMessage"](transforms=[
    tfs("odom", "base_link", (1.5, -2.25, 0.5)), tfs("base_link", "laser", (0.1, 0.0, 0.2))]))
add("tf_empty", "tf2_msgs/msg/TFMessage", T["tf2_msgs/msg/TFMessage"](transforms=[]))
rgba = T["std_msgs/msg/ColorRGBA"]
add("marker", "visualization_msgs/msg/Marker", T["visualization_msgs/msg/Marker"](
    header=header(9, 10, "base_link"), ns="path", id=8, type=4, action=0,
    pose=pose(pt(0, 0, 0), q(0, 0, 0, 1.0)), scale=v3(0.1, 0.1, 0.1),
    color=rgba(r=1.0, g=0.5, b=0.25, a=1.0),
    lifetime=T["builtin_interfaces/msg/Duration"](sec=3, nanosec=500), frame_locked=True,
    points=[pt(0, 0, 0), pt(1.0, 0.5, 0.25)], colors=[rgba(r=1.0, g=0, b=0, a=1.0), rgba(r=0, g=1.0, b=0, a=0.5)],
    texture_resource="", texture=T["sensor_msgs/msg/CompressedImage"](
        header=header(0, 0, ""), format="", data=np.zeros(0, dtype=np.uint8)),
    uv_coordinates=[], text="hola", mesh_resource="",
    mesh_file=T["visualization_msgs/msg/MeshFile"](filename="", data=np.zeros(0, dtype=np.uint8)),
    mesh_use_embedded_materials=False))
add("occupancy", "nav_msgs/msg/OccupancyGrid", T["nav_msgs/msg/OccupancyGrid"](
    header=header(100, 0, "map"),
    info=T["nav_msgs/msg/MapMetaData"](map_load_time=time(50, 60), resolution=0.5, width=4, height=4,
                                       origin=pose(pt(-1.0, -2.0, 0.0), q(0, 0, 0, 1.0))),
    data=np.array([-1, 0, 100, 50, -1, -1, 0, 0, 100, 100, 25, 75, 0, 1, 2, 99], dtype=np.int8)))

# --- salida -----------------------------------------------------------------
blob, order = gms.build_blob(ts, sorted({t for t, _ in cases.values()}))
(OUT / "schema.rsch").write_bytes(blob)
print(f"schema.rsch: {len(blob)} bytes, {len(order)} tipos")
for name, (typename, msg) in cases.items():
    data = bytes(ts.serialize_cdr(msg, typename))
    assert data[:4] == b"\x00\x01\x00\x00"
    (OUT / f"{name}.bin").write_bytes(data)
    (OUT / f"{name}.type").write_text(typename + "\n")
    (OUT / f"{name}.dump").write_text("\n".join(gms.dump_message(ts, typename, msg)) + "\n")
(OUT / "cases.txt").write_text("\n".join(cases) + "\n")
print(len(cases), "casos")
