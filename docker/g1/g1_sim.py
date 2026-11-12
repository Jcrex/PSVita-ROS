#!/usr/bin/env python3
"""Simulador del Unitree G1 con su control OFICIAL, puenteado a ROS 2 para la PS Vita.

Control: política de marcha de Unitree (unitree_rl_gym, `deploy/pre_train/g1/motion.pt`) sobre el modelo
MuJoCo oficial `g1_12dof.xml`. El bucle replica `deploy/deploy_mujoco/deploy_mujoco.py` (BSD-3,
Copyright Unitree Robotics): física a 500 Hz, PD en las 12 articulaciones de las piernas, política a 50 Hz
con la observación de 47 valores (velocidad angular, gravedad proyectada, orden de velocidad, q, dq, acción
anterior y fase de la marcha de 0,8 s). Aquí va sin ventana y la orden sale de /cmd_vel.

ROS 2 (modo `ros`, por defecto):
  sub  /cmd_vel        geometry_msgs/Twist  linear.x, linear.y, angular.z → orden de la política.
                        Hombre muerto: sin mensajes en 0,5 s → orden cero (el robot marca el paso quieto).
  pub  /g1/estado      std_msgs/Float32MultiArray, BEST_EFFORT, 25 Hz — formato compacto para la Vita
                        (cabe en un datagrama XRCE de 512 B): [x, y, z, qx, qy, qz, qw, q0..q11] en el
                        marco odom (ROS, Z arriba); q en el orden JOINTS_PIERNAS.
  pub  /joint_states   sensor_msgs/JointState (29 nombres del URDF; brazos y cintura a 0), 50 Hz
  pub  /odom + /tf     odom → pelvis (para RViz2)
  robot_state_publisher (subproceso) con el URDF oficial g1_29dof_rev_1_0: /robot_description (latched) y el TF
                       pelvis → todos los links a partir de /joint_states. Mallas con rutas file:// de esta imagen
                       (RViz con modelo: `docker/vita-ros.sh g1-rviz`, que corre en esta misma imagen).
  pub  /map            nav_msgs/OccupancyGrid latched de la casa (con --casa), 5 cm, frame «map»; TF estático
                       map → odom identidad (el odom del simulador es el mundo). Para la Vita: `vita-ros.sh relay`.
Si el robot se cae (pelvis < 0,45 m) se reinicia de pie.

Modo `grabar` (sin ROS): genera los clips de animación de desplazamiento para Godot (JSON), ver --ayuda.
Fase 3: `--casa casa.json` añade las paredes y muebles de la casa como colisiones en MuJoCo.
"""
import argparse
import json
import math
import os
import sys
import time

import mujoco
import numpy as np
import torch
import yaml

RL_GYM = os.environ.get("G1_RL_GYM", "/opt/unitree_rl_gym")
DESC = os.path.join(RL_GYM, "resources/robots/g1_description")
JOINTS_PIERNAS = [f"{l}_{j}_joint" for l in ("left", "right")
                  for j in ("hip_pitch", "hip_roll", "hip_yaw", "knee", "ankle_pitch", "ankle_roll")]
JOINTS_URDF_RESTO = ["waist_yaw_joint", "waist_roll_joint", "waist_pitch_joint"] + [
    f"{l}_{j}_joint" for l in ("left", "right")
    for j in ("shoulder_pitch", "shoulder_roll", "shoulder_yaw", "elbow", "wrist_roll", "wrist_pitch", "wrist_yaw")]
LIM_CMD = np.array([[-0.6, 1.0], [-0.5, 0.5], [-1.0, 1.0]], dtype=np.float32)  # vx, vy, wz


def gravedad(q):  # igual que get_gravity_orientation() de deploy_mujoco.py
    qw, qx, qy, qz = q
    return np.array([2 * (-qz * qx + qw * qy), -2 * (qz * qy + qw * qx), 1 - 2 * (qw * qw + qz * qz)])


class G1:
    def __init__(self, casa=None):
        cfg = yaml.safe_load(open(os.path.join(RL_GYM, "deploy/deploy_mujoco/configs/g1.yaml")))
        self.dt = cfg["simulation_dt"]
        self.dec = cfg["control_decimation"]
        self.kps = np.array(cfg["kps"], np.float32)
        self.kds = np.array(cfg["kds"], np.float32)
        self.q0 = np.array(cfg["default_angles"], np.float32)
        self.esc = dict(ang=cfg["ang_vel_scale"], q=cfg["dof_pos_scale"], dq=cfg["dof_vel_scale"],
                        acc=cfg["action_scale"], cmd=np.array(cfg["cmd_scale"], np.float32))
        self.n = cfg["num_actions"]
        self.obs = np.zeros(cfg["num_obs"], np.float32)
        escena = os.path.join(DESC, "scene.xml")
        if casa:
            import casa as casa_mod
            escena = casa_mod.escribir_mjcf(casa, DESC)
        self.m = mujoco.MjModel.from_xml_path(escena)
        self.d = mujoco.MjData(self.m)
        self.m.opt.timestep = self.dt
        self.pol = torch.jit.load(cfg["policy_path"].replace("{LEGGED_GYM_ROOT_DIR}", RL_GYM))
        nombres = [self.m.joint(i).name for i in range(self.m.njnt)]
        assert nombres[1:] == JOINTS_PIERNAS, nombres
        self.cmd = np.zeros(3, np.float32)
        self.inicio = (0.0, 0.0, 0.0)
        self.reiniciar()

    def reiniciar(self, x=None, y=None, yaw=None):
        if x is not None:
            self.inicio = (x, y, yaw)
        x, y, yaw = self.inicio
        mujoco.mj_resetData(self.m, self.d)
        self.d.qpos[0:3] = [x, y, 0.793]
        self.d.qpos[3:7] = [math.cos(yaw / 2), 0, 0, math.sin(yaw / 2)]
        self.d.qpos[7:] = self.q0
        self.accion = np.zeros(self.n, np.float32)
        self.objetivo = self.q0.copy()
        self.cont = 0
        mujoco.mj_forward(self.m, self.d)

    def paso_politica(self):
        """Avanza 1/50 s: 10 pasos de física con PD y una inferencia de la política."""
        for _ in range(self.dec):
            d = self.d
            d.ctrl[:] = (self.objetivo - d.qpos[7:]) * self.kps - d.qvel[6:] * self.kds
            mujoco.mj_step(self.m, d)
            self.cont += 1
        d, o, n = self.d, self.obs, self.n
        fase = (self.cont * self.dt) % 0.8 / 0.8
        o[:3] = d.qvel[3:6] * self.esc["ang"]
        o[3:6] = gravedad(d.qpos[3:7])
        o[6:9] = self.cmd * self.esc["cmd"]
        o[9:9 + n] = (d.qpos[7:] - self.q0) * self.esc["q"]
        o[9 + n:9 + 2 * n] = d.qvel[6:] * self.esc["dq"]
        o[9 + 2 * n:9 + 3 * n] = self.accion
        o[9 + 3 * n:9 + 3 * n + 2] = [math.sin(2 * math.pi * fase), math.cos(2 * math.pi * fase)]
        with torch.no_grad():
            self.accion = self.pol(torch.from_numpy(o).unsqueeze(0)).numpy().squeeze()
        self.objetivo = self.accion * self.esc["acc"] + self.q0
        if d.qpos[2] < 0.45:
            print("[g1] caída: reinicio", flush=True)
            self.reiniciar()
            return False
        return True

    def estado(self):
        """[x, y, z, qx, qy, qz, qw, q0..q11] (cuaternión de MuJoCo wxyz → ROS xyzw)."""
        p, q = self.d.qpos[0:3], self.d.qpos[3:7]
        return [float(v) for v in (*p, q[1], q[2], q[3], q[0], *self.d.qpos[7:])]


def yaw_de(q_xyzw):
    x, y, z, w = q_xyzw
    return math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))


def grabar(salida, segundos_calentar=4.0, periodos=2):
    """Clips de desplazamiento: para cada orden, calentar y grabar `periodos` ciclos de marcha (0,8 s) a 50 Hz.
    Pose de la base relativa al primer fotograma del clip, en su marco de guiñada (para encadenar el clip)."""
    clips = {
        "quieto": (0.0, 0.0, 0.0), "andar": (0.6, 0.0, 0.0), "correr": (1.0, 0.0, 0.0),
        "atras": (-0.4, 0.0, 0.0), "izquierda": (0.0, 0.4, 0.0), "derecha": (0.0, -0.4, 0.0),
        "girar_izq": (0.0, 0.0, 0.8), "girar_der": (0.0, 0.0, -0.8),
    }
    g = G1()
    res = {"fuente": "unitree_rl_gym motion.pt (BSD-3, Unitree Robotics) en MuJoCo, g1_sim.py --grabar",
           "hz": 50, "joints": JOINTS_PIERNAS, "clips": {}}
    nf = int(round(periodos * 0.8 * 50))
    for nombre, cmd in clips.items():
        g.reiniciar(0, 0, 0)
        g.cmd[:] = cmd
        for _ in range(int(segundos_calentar * 50)):
            g.paso_politica()
        # empezar en el mismo punto de fase en todos los clips (fase 0) para poder mezclarlos
        while (g.cont * g.dt) % 0.8 > 0.019:
            g.paso_politica()
        frames = []
        e0 = g.estado()
        yaw0 = yaw_de(e0[3:7])
        c, s = math.cos(-yaw0), math.sin(-yaw0)
        for _ in range(nf + 1):
            e = g.estado()
            dx, dy = e[0] - e0[0], e[1] - e0[1]
            # cuaternión relativo en guiñada: q_rel = q_yaw0^-1 * q
            qz0 = (0.0, 0.0, math.sin(-yaw0 / 2), math.cos(-yaw0 / 2))
            frames.append([round(v, 5) for v in (c * dx - s * dy, s * dx + c * dy, e[2],
                                                  *mul_q(qz0, e[3:7]), *e[7:])])
            g.paso_politica()
        res["clips"][nombre] = {"cmd": list(cmd), "frames": frames}
        f = frames[-1]
        print(f"[g1] clip {nombre}: {len(frames)} fotogramas, desplazamiento ({f[0]:.2f}, {f[1]:.2f}) m, "
              f"giro {math.degrees(yaw_de(f[3:7])):.0f}°", flush=True)
    json.dump(res, open(salida, "w"), separators=(",", ":"))
    print(f"[g1] escrito {salida}")


def mul_q(a, b):  # xyzw
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


URDF_G1 = os.path.join(DESC, "g1_29dof_rev_1_0.urdf")


def lanzar_robot_state_publisher():
    """robot_state_publisher con el URDF oficial; las mallas pasan a file:// absolutas para RViz."""
    import subprocess
    import tempfile
    urdf = open(URDF_G1).read().replace('filename="meshes/', f'filename="file://{DESC}/meshes/')
    yaml = tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False)
    # YAML con el URDF como bloque literal (indentado) para no pelearse con las comillas.
    yaml.write("robot_state_publisher:\n  ros__parameters:\n    robot_description: |\n")
    yaml.write("".join("      " + ln + "\n" for ln in urdf.splitlines()))
    yaml.close()
    return subprocess.Popen(["ros2", "run", "robot_state_publisher", "robot_state_publisher",
                             "--ros-args", "--params-file", yaml.name])


def modo_ros(casa, x, y, yaw):
    import rclpy
    from rclpy.node import Node
    from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
    from geometry_msgs.msg import Twist, TransformStamped
    from nav_msgs.msg import Odometry
    from sensor_msgs.msg import JointState
    from std_msgs.msg import Float32MultiArray
    from tf2_ros import TransformBroadcaster, StaticTransformBroadcaster
    from nav_msgs.msg import OccupancyGrid
    from rclpy.qos import DurabilityPolicy

    rclpy.init()
    nodo = Node("g1_sim")
    g = G1(casa)
    g.reiniciar(x, y, yaw)
    be = QoSProfile(depth=1, reliability=ReliabilityPolicy.BEST_EFFORT, history=HistoryPolicy.KEEP_LAST)
    p_est = nodo.create_publisher(Float32MultiArray, "/g1/estado", be)
    p_js = nodo.create_publisher(JointState, "/joint_states", 10)
    p_odom = nodo.create_publisher(Odometry, "/odom", 10)
    tf = TransformBroadcaster(nodo)
    rsp = lanzar_robot_state_publisher()
    if casa:
        import casa as casa_mod
        latched = QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE,
                             durability=DurabilityPolicy.TRANSIENT_LOCAL)
        p_map = nodo.create_publisher(OccupancyGrid, "/map", latched)
        datos, w, h, x0, y0 = casa_mod.occupancy_grid(casa)
        mapa = OccupancyGrid()
        mapa.header.frame_id = "map"
        mapa.header.stamp = nodo.get_clock().now().to_msg()
        mapa.info.resolution, mapa.info.width, mapa.info.height = 0.05, w, h
        mapa.info.origin.position.x, mapa.info.origin.position.y = x0, y0
        mapa.info.origin.orientation.w = 1.0
        mapa.data = datos
        p_map.publish(mapa)
        tf_est = StaticTransformBroadcaster(nodo)
        t0 = TransformStamped()
        t0.header.stamp, t0.header.frame_id, t0.child_frame_id = mapa.header.stamp, "map", "odom"
        t0.transform.rotation.w = 1.0
        tf_est.sendTransform(t0)
        nodo.get_logger().info(f"/map de la casa publicado ({w}×{h} a 5 cm) y TF estático map → odom")
    ultimo = [0.0]

    def on_cmd(m):
        g.cmd[:] = np.clip([m.linear.x, m.linear.y, m.angular.z], LIM_CMD[:, 0], LIM_CMD[:, 1])
        ultimo[0] = time.monotonic()

    # Best effort: casa con publicadores best effort (la Vita) y reliable (teleop_twist_keyboard, rqt).
    # Un suscriptor reliable no casaría con la Vita (lección de G7b).
    nodo.create_subscription(Twist, "/cmd_vel", on_cmd, be)
    nodo.get_logger().info("G1 en marcha: /cmd_vel → política de Unitree; publica /g1/estado (25 Hz)")
    t_sig = time.monotonic()
    k = 0
    import atexit
    atexit.register(rsp.terminate)
    while rclpy.ok():
        rclpy.spin_once(nodo, timeout_sec=0)
        if time.monotonic() - ultimo[0] > 0.5:
            g.cmd[:] = 0
        g.paso_politica()
        k += 1
        e = g.estado()
        ahora = nodo.get_clock().now().to_msg()
        if k % 2 == 0:  # 25 Hz para la Vita: 19 float32 = 76 B de datos, cabe en un datagrama XRCE
            p_est.publish(Float32MultiArray(data=e))
        js = JointState()
        js.header.stamp = ahora
        js.name = JOINTS_PIERNAS + JOINTS_URDF_RESTO
        js.position = e[7:] + [0.0] * len(JOINTS_URDF_RESTO)
        p_js.publish(js)
        t = TransformStamped()
        t.header.stamp, t.header.frame_id, t.child_frame_id = ahora, "odom", "pelvis"
        t.transform.translation.x, t.transform.translation.y, t.transform.translation.z = e[0:3]
        (t.transform.rotation.x, t.transform.rotation.y, t.transform.rotation.z, t.transform.rotation.w) = e[3:7]
        tf.sendTransform(t)
        od = Odometry()
        od.header = t.header
        od.child_frame_id = "pelvis"
        od.pose.pose.position.x, od.pose.pose.position.y, od.pose.pose.position.z = e[0:3]
        od.pose.pose.orientation = t.transform.rotation
        od.twist.twist.linear.x, od.twist.twist.linear.y, od.twist.twist.angular.z = (float(v) for v in g.cmd)
        p_odom.publish(od)
        t_sig += 0.02
        espera = t_sig - time.monotonic()
        if espera > 0:
            time.sleep(espera)
        else:
            t_sig = time.monotonic()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--grabar", metavar="SALIDA.json", help="generar clips de animación y salir")
    ap.add_argument("--casa", metavar="casa.json", help="añadir la casa (fase 3) como colisiones")
    ap.add_argument("--inicio", default="0,0,0", help="x,y,yaw iniciales en odom (m, m, rad)")
    a = ap.parse_args()
    if a.grabar:
        grabar(a.grabar)
    else:
        x, y, yaw = (float(v) for v in a.inicio.split(","))
        modo_ros(a.casa, x, y, yaw)


if __name__ == "__main__":
    main()
