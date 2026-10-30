#!/usr/bin/env python3
"""vita_monitor.py — monitor de la PS Vita en el grafo ROS 2 (estación docker/, ./vita-ros.sh monitor).

Qué hace:
  - escucha lo que publica la Vita: /vita_hello (std_msgs/String) y /cmd_vel (geometry_msgs/Twist)
  - publica /pc_hello (std_msgs/String) a 1 Hz: la app de G5 se pone VERDE al recibirlo
  - cada 2 s imprime una línea de estado: frecuencia real de cada topic, último valor y si la
    Vita está "viva" (ha publicado en los últimos 3 s)

Uso dentro del contenedor:  python3 /scripts/vita_monitor.py [--sin-pc-hello]
"""
import sys
import time

import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node
from std_msgs.msg import String


class Contador:
    """Cuenta mensajes y calcula la frecuencia en la ventana desde el último informe."""

    def __init__(self):
        self.total = 0
        self.ventana = 0
        self.ultimo_t = None
        self.ultimo = ""

    def nuevo(self, texto):
        self.total += 1
        self.ventana += 1
        self.ultimo_t = time.monotonic()
        self.ultimo = texto

    def hz(self, dt):
        h = self.ventana / dt if dt > 0 else 0.0
        self.ventana = 0
        return h

    def vivo(self):
        return self.ultimo_t is not None and time.monotonic() - self.ultimo_t < 3.0


class VitaMonitor(Node):
    def __init__(self, pc_hello=True):
        super().__init__("vita_monitor")
        self.hello = Contador()
        self.cmd = Contador()
        self.create_subscription(String, "/vita_hello", self._on_hello, 10)
        self.create_subscription(Twist, "/cmd_vel", self._on_cmd, 10)
        self.n_pc = 0
        if pc_hello:
            self.pub = self.create_publisher(String, "/pc_hello", 10)
            self.create_timer(1.0, self._pc_hello)
        self.t_informe = time.monotonic()
        self.create_timer(2.0, self._informe)
        self.get_logger().info("escuchando /vita_hello y /cmd_vel%s" % (", publicando /pc_hello" if pc_hello else ""))

    def _on_hello(self, m):
        self.hello.nuevo(m.data)

    def _on_cmd(self, m):
        self.cmd.nuevo("lin.x=%+.2f ang.z=%+.2f" % (m.linear.x, m.angular.z))

    def _pc_hello(self):
        self.n_pc += 1
        self.pub.publish(String(data="hola Vita desde el PC #%d" % self.n_pc))

    def _informe(self):
        ahora = time.monotonic()
        dt = ahora - self.t_informe
        self.t_informe = ahora
        estado = "VITA VIVA" if (self.hello.vivo() or self.cmd.vivo()) else "sin datos de la Vita"
        print(
            "[%s] %-20s | /vita_hello %4.1f Hz (%d) «%s» | /cmd_vel %4.1f Hz (%d) %s"
            % (time.strftime("%H:%M:%S"), estado, self.hello.hz(dt), self.hello.total, self.hello.ultimo,
               self.cmd.hz(dt), self.cmd.total, self.cmd.ultimo),
            flush=True,
        )


def main():
    rclpy.init()
    node = VitaMonitor(pc_hello="--sin-pc-hello" not in sys.argv)
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == "__main__":
    main()
