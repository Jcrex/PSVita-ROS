// xrce_transport.h — transporte micro-ROS (XRCE-DDS sobre UDP) de ros2_vita. Puerta G5 (docs/18 §8).
// Probado en host contra el agente micro-ROS en docker; en la Vita: validar en hardware.
//
// Cadena (la misma que vita-app y la app Godot 3.5, ya probadas en hardware):
//   XrceTransport -> uxr (microxrcedds_client) -> vita-app/src/uxr_glue.c
//     -> modules/microros-transport -> modules/net-udp -> sceNet (Vita) / sockets POSIX (host)
//
// Solo se compila si SCsub encuentra las libs XRCE de la plataforma (define ROS2_VITA_XRCE).
#pragma once

#include "ros_runtime.h"

// Crea el transporte XRCE (lo usa rclgd::init cuando transport == "xrce").
RosTransport *ros2_vita_create_xrce_transport();
