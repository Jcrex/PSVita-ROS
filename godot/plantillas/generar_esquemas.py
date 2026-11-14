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

# Tipos del visor (ADR 0013; sentencia W13 D10; doc 36 §10 V5): lo que la Vita recibe o publica EN DIRECTO (cabe
# en un datagrama de 488 B en el caso típico) y no está ya en TIPOS. Se añaden con `--visor`; las demás apps no
# cambian (un `.rsch` por app, T20). Lo que va por el relay (/vita/*) usa los *MultiArray de TIPOS.
# Los tipos anidados (Point, Vector3, Pose, Quaternion, Polygon, Header…) entran solos por cierre transitivo.
TIPOS_VISOR = [
    # std_msgs: escalares y color (hud/valor.gd, hud/color.gd)
    "std_msgs/msg/Float32",
    "std_msgs/msg/Float64",
    "std_msgs/msg/Int32",
    "std_msgs/msg/UInt8",
    "std_msgs/msg/ColorRGBA",
    # geometry_msgs (fichas doc 36a §4.2)
    "geometry_msgs/msg/PointStamped",
    "geometry_msgs/msg/Vector3Stamped",
    "geometry_msgs/msg/PoseArray",
    "geometry_msgs/msg/PoseWithCovarianceStamped",
    "geometry_msgs/msg/WrenchStamped",
    "geometry_msgs/msg/AccelStamped",
    "geometry_msgs/msg/QuaternionStamped",
    "geometry_msgs/msg/PolygonStamped",
    # sensor_msgs del HUD (medidores y mando, V4)
    "sensor_msgs/msg/Temperature",
    "sensor_msgs/msg/Illuminance",
    "sensor_msgs/msg/RelativeHumidity",
    "sensor_msgs/msg/Joy",
    # nav_msgs: Path no está en D10 pero lo pide V3 (`2d/path.gd` en directo en el PC con ros2_vita; en la Vita
    # suele ir por el relay `path_compacto` porque no cabe: 28 + 72·n B)
    "nav_msgs/msg/Path",
    "nav_msgs/msg/MapMetaData",
    "nav_msgs/msg/GridCells",
    # visualization_msgs: Marker suelto (≤ 10 puntos cabe), ImageMarker y feedback de marcador interactivo
    "visualization_msgs/msg/Marker",
    "visualization_msgs/msg/ImageMarker",
    "visualization_msgs/msg/InteractiveMarkerFeedback",
    # HMI: diagnóstico, consola, lifecycle y estado de acciones
    "diagnostic_msgs/msg/DiagnosticArray",
    "rcl_interfaces/msg/Log",
    "lifecycle_msgs/msg/TransitionEvent",
    "action_msgs/msg/GoalStatusArray",
    # feedback de NavigateToPose (hud/estado_meta.gd): registro manual desde ros/msg/nav2_msgs/action/
    "nav2_msgs/action/NavigateToPose_FeedbackMessage",
]

MSG_LOCALES = pathlib.Path(__file__).parent / "ros/msg"


def registrar_locales(ts):
    """Registra las definiciones .msg de `ros/msg/<paquete>/<msg|action>/` (tipos que rosbags no trae)."""
    for ruta in sorted(MSG_LOCALES.glob("*/*/*.msg")):
        nombre = f"{ruta.parent.parent.name}/{ruta.parent.name}/{ruta.stem}"
        ts.register(get_types_from_msg(ruta.read_text(), nombre))


def main():
    ap = argparse.ArgumentParser(description="Genera el esquema CDR de una plantilla Godot")
    ap.add_argument("--salida", required=True)
    ap.add_argument("--unitree", help="carpeta con unitree_hg, unitree_go y unitree_api")
    ap.add_argument("--visor", action="store_true", help="añade TIPOS_VISOR (apps con el visor de topics, V5)")
    args = ap.parse_args()
    ts = get_typestore(Stores.ROS2_JAZZY)
    tipos = list(TIPOS)
    registrar_locales(ts)
    if args.visor:
        tipos += [t for t in TIPOS_VISOR if t not in tipos]
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
