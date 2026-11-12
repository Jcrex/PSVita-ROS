#!/usr/bin/env python3
import argparse
import pathlib
import sys

from rosbags.typesys import Stores, get_typestore, get_types_from_msg

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import gen_msg_schema

TIPOS = [
    "std_msgs/msg/String",
    "std_msgs/msg/Bool",
    "std_msgs/msg/Float32MultiArray",
    "std_msgs/msg/Int16MultiArray",
    "std_msgs/msg/UInt8MultiArray",
    "geometry_msgs/msg/Twist",
    "geometry_msgs/msg/TwistStamped",
    "geometry_msgs/msg/PoseStamped",
    "geometry_msgs/msg/TransformStamped",
    "sensor_msgs/msg/Imu",
    "sensor_msgs/msg/NavSatFix",
    "sensor_msgs/msg/LaserScan",
    "sensor_msgs/msg/Image",
    "sensor_msgs/msg/CompressedImage",
    "sensor_msgs/msg/CameraInfo",
    "sensor_msgs/msg/PointCloud2",
    "sensor_msgs/msg/JointState",
    "sensor_msgs/msg/BatteryState",
    "sensor_msgs/msg/Range",
    "sensor_msgs/msg/FluidPressure",
    "sensor_msgs/msg/MagneticField",
    "nav_msgs/msg/Odometry",
    "nav_msgs/msg/OccupancyGrid",
    "tf2_msgs/msg/TFMessage",
    "trajectory_msgs/msg/JointTrajectory",
    "control_msgs/msg/JointTrajectoryControllerState",
]


def main():
    ap = argparse.ArgumentParser(description="Genera el esquema CDR de una plantilla Godot")
    ap.add_argument("--salida", required=True)
    ap.add_argument("--unitree", help="carpeta con unitree_hg, unitree_go y unitree_api")
    args = ap.parse_args()
    ts = get_typestore(Stores.ROS2_JAZZY)
    tipos = list(TIPOS)
    control = pathlib.Path(__file__).parent / "ros/msg/control_msgs/msg/JointTrajectoryControllerState.msg"
    if control.exists():
        ts.register(get_types_from_msg(control.read_text(), "control_msgs/msg/JointTrajectoryControllerState"))
    if args.unitree:
        base = pathlib.Path(args.unitree)
        for paquete in ("unitree_hg", "unitree_go", "unitree_api"):
            for ruta in sorted((base / paquete / "msg").glob("*.msg")):
                nombre = f"{paquete}/msg/{ruta.stem}"
                ts.register(get_types_from_msg(ruta.read_text(), nombre))
                tipos.append(nombre)
    blob, orden = gen_msg_schema.build_blob(ts, tipos)
    salida = pathlib.Path(args.salida)
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_bytes(blob)
    print(f"{salida}: {len(blob)} bytes, {len(orden)} tipos")
    faltantes = sorted(set(tipos) - set(orden))
    if faltantes:
        raise SystemExit(f"Tipos no incluidos: {faltantes}")


if __name__ == "__main__":
    main()
