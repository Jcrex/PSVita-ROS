#!/usr/bin/env python3
"""turtle_odom.py — convierte la pose de turtlesim en nav_msgs/Odometry (estación docker/, `vita-ros.sh sim`).

turtlesim publica /turtle1/pose (turtlesim/msg/Pose: x, y, theta, velocidades) y no /odom. La HMI de la
Vita (godot/g6-hmi, puerta G6) se suscribe a /odom, que es lo que publica un robot real o TurtleBot3; con
este adaptador la misma app vale con la tortuga (ligera, sin GPU) y con Gazebo.

La pose se publica relativa a la posición inicial de la tortuga (5.54, 5.54 en su mundo de 11x11 m),
para que el robot empiece en el origen como un robot real al arrancar su odometría.
"""
import math

import rclpy
from nav_msgs.msg import Odometry
from rclpy.node import Node
from turtlesim.msg import Pose


class TurtleOdom(Node):
    def __init__(self):
        super().__init__("turtle_odom")
        self.origen = None
        self.pub = self.create_publisher(Odometry, "/odom", 10)
        self.create_subscription(Pose, "/turtle1/pose", self._on_pose, 10)
        self.get_logger().info("/turtle1/pose -> /odom (frame odom, hijo base_link)")

    def _on_pose(self, p):
        if self.origen is None:
            self.origen = (p.x, p.y)
        o = Odometry()
        o.header.stamp = self.get_clock().now().to_msg()
        o.header.frame_id = "odom"
        o.child_frame_id = "base_link"
        o.pose.pose.position.x = p.x - self.origen[0]
        o.pose.pose.position.y = p.y - self.origen[1]
        # yaw -> cuaternión (rotación solo en z)
        o.pose.pose.orientation.z = math.sin(p.theta / 2.0)
        o.pose.pose.orientation.w = math.cos(p.theta / 2.0)
        o.twist.twist.linear.x = p.linear_velocity
        o.twist.twist.angular.z = p.angular_velocity
        self.pub.publish(o)


def main():
    rclpy.init()
    node = TurtleOdom()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == "__main__":
    main()
