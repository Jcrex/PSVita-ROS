extends "res://comun/visor/herramientas/meta.gd"
## 2D Pose Estimate (RViz `initial_pose_tool.cpp`; doc 36a §4.8.10, ficha hmi#17): el mismo gesto que la meta
## (pulsar, arrastrar el rumbo, soltar; en la Vita ✕ confirma) y publica `geometry_msgs/PoseWithCovarianceStamped`
## en `initialpose` (relativo, como RViz; 364 B: cabe en best effort, pero AMCL se suscribe fiable [I]).
##
## Covarianza por defecto de RViz (`initial_pose_tool.cpp:62-70`): x = y = 0,5² = 0,25 y yaw = (π/12)² ≈ 0,0685 en
## los índices [0], [7] y [35] (6·i + i de x, y, rotZ); el resto 0. El array se asigna ENTERO (los arrays se
## copian, `godot/ros2_vita/API_PARITY.md:49`).

@export var cov_x := 0.25                      # 0,5² (initial_pose_tool.cpp:62-64)
@export var cov_y := 0.25
@export var cov_yaw := pow(PI / 12.0, 2.0)     # (π/12)² (initial_pose_tool.cpp:68-70)


static func nombre_herramienta() -> String:
	return "Pose inicial"


func _init() -> void:
	topic = "initialpose"
	tipo = "geometry_msgs/msg/PoseWithCovarianceStamped"


## Covarianza 6×6 por filas (x, y, z, rotX, rotY, rotZ).
func covarianza() -> PackedFloat64Array:
	var cov := PackedFloat64Array()
	cov.resize(36)
	cov.fill(0.0)
	cov[0] = cov_x                             # [6·0 + 0]
	cov[7] = cov_y                             # [6·1 + 1]
	cov[35] = cov_yaw                          # [6·5 + 5]
	return cov


func _publicar(p: Vector3, yaw: float) -> void:
	var m = RosMsg.from_type(tipo)
	cabecera(m)
	_poner_pose(m.pose.pose, p, yaw)
	m.pose.covariance = covarianza()
	publicar(m)
