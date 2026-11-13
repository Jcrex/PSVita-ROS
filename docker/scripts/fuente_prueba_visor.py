#!/usr/bin/env python3
"""Fuente sintética para probar el visor (godot/visor-ros, ADR 0013 / doc 36 §10 V1–V4) sin robot.

Publica lo que consumen los displays de `godot/visor-ros/main.tscn`, directamente (PC) o a través de
`vita_relay.py` (Vita, topics compactos `/vita/*`):

  /map            OccupancyGrid 100×80 a 5 cm, borde ocupado (fiable + TRANSIENT_LOCAL, una vez)
  /scan           LaserScan 360 rayos que ondulan (base_scan), 20 Hz
  /odom           Odometry en círculo de 1 m (odom), 20 Hz
  /joint_states   JointState de dos ruedas, 20 Hz
  /plan           Path de 100 poses (map), 1 Hz
  /battery_state  BatteryState que se descarga, 1 Hz        (widget Bateria; esquema ya en la Vita)
  /barometer      FluidPressure ≈ 1013 hPa, 2 Hz             (medidor Presion; esquema ya en la Vita)
  /temperature    Temperature ≈ 30 °C, 2 Hz                  (medidor Temperatura; en la Vita: «sin esquema» hasta V5)

Es la fuente que usó la tarea V3 en el host (revisión V1, 2026-11-13: antes vivía fuera del repo).
Uso (en la estación): `docker/vita-ros.sh fuente-visor`   o   `python3 /scripts/fuente_prueba_visor.py`
"""
import math

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, DurabilityPolicy
from geometry_msgs.msg import PoseStamped
from nav_msgs.msg import OccupancyGrid, Odometry, Path
from sensor_msgs.msg import BatteryState, FluidPressure, JointState, LaserScan, Temperature


def main():
    rclpy.init()
    n = Node("fuente_prueba_visor")
    lat = QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE, durability=DurabilityPolicy.TRANSIENT_LOCAL)
    pm = n.create_publisher(OccupancyGrid, "/map", lat)
    ps = n.create_publisher(LaserScan, "/scan", 10)
    po = n.create_publisher(Odometry, "/odom", 10)
    pj = n.create_publisher(JointState, "/joint_states", 10)
    pp = n.create_publisher(Path, "/plan", 10)
    pb = n.create_publisher(BatteryState, "/battery_state", 10)
    pf = n.create_publisher(FluidPressure, "/barometer", 10)
    pt = n.create_publisher(Temperature, "/temperature", 10)

    m = OccupancyGrid()
    m.header.frame_id = "map"
    m.info.resolution, m.info.width, m.info.height = 0.05, 100, 80
    m.info.origin.position.x, m.info.origin.position.y = -2.5, -2.0
    m.info.origin.orientation.w = 1.0
    m.data = [100 if (x in (0, 99) or y in (0, 79)) else (-1 if x > 70 and y > 50 else 0)
              for y in range(80) for x in range(100)]
    pm.publish(m)
    n.get_logger().info("/map 100×80 publicado (latched); scan/odom/joints a 20 Hz, plan 1 Hz, HUD 1-2 Hz")
    t = [0.0]
    k = [0]

    def ahora():
        return n.get_clock().now().to_msg()

    def tic():
        t[0] += 0.05
        k[0] += 1
        s = LaserScan()
        s.header.frame_id = "base_scan"
        s.header.stamp = ahora()
        s.angle_min, s.angle_max = -math.pi, math.pi
        s.angle_increment = 2 * math.pi / 360
        s.range_min, s.range_max = 0.1, 10.0
        s.ranges = [2.0 + 0.5 * math.sin(i * 0.1 + t[0]) for i in range(360)]
        ps.publish(s)
        o = Odometry()
        o.header.frame_id, o.child_frame_id = "odom", "base_link"
        o.header.stamp = ahora()
        o.pose.pose.position.x = math.cos(t[0] * 0.3)
        o.pose.pose.position.y = math.sin(t[0] * 0.3)
        o.pose.pose.orientation.z = math.sin(t[0] * 0.15 + math.pi / 4)
        o.pose.pose.orientation.w = math.cos(t[0] * 0.15 + math.pi / 4)
        po.publish(o)
        j = JointState()
        j.header.stamp = ahora()
        j.name = ["rueda_izq", "rueda_der"]
        j.position = [t[0], -t[0]]
        pj.publish(j)
        if k[0] % 10 == 0:                          # 2 Hz
            f = FluidPressure()
            f.header.stamp = ahora()
            f.fluid_pressure = 101325.0 + 300.0 * math.sin(t[0] * 0.2)
            pf.publish(f)
            te = Temperature()
            te.header.stamp = ahora()
            te.temperature = 30.0 + 20.0 * math.sin(t[0] * 0.1)
            pt.publish(te)
        if k[0] % 20 == 0:                          # 1 Hz
            p = Path()
            p.header.frame_id = "map"
            p.header.stamp = ahora()
            for i in range(100):
                q = PoseStamped()
                q.header.frame_id = "map"
                q.pose.position.x = -2.0 + i * 0.04
                q.pose.position.y = math.sin(i * 0.1 + t[0] * 0.1)
                q.pose.orientation.w = 1.0
                p.poses.append(q)
            pp.publish(p)
            b = BatteryState()
            b.header.stamp = ahora()
            b.voltage = 12.6
            b.current = -1.2
            b.percentage = (1.0 - (t[0] / 120.0) % 1.0)
            b.power_supply_status = BatteryState.POWER_SUPPLY_STATUS_DISCHARGING
            b.power_supply_health = BatteryState.POWER_SUPPLY_HEALTH_GOOD
            b.present = True
            pb.publish(b)

    n.create_timer(0.05, tic)
    rclpy.spin(n)


if __name__ == "__main__":
    main()
