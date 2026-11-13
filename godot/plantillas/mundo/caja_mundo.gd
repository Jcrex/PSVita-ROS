extends MeshInstance3D
## Caja del terreno o de la casa en `mundo.tscn` (regla de escenas, doc 35: la escena manda en lo que se ve y dónde).
##
## Se edita en el editor de Godot como cualquier MeshInstance3D:
##  - posición y giro: con el gizmo (o Transform en el inspector);
##  - tamaño: mesh → size (en metros, ejes de Godot: x = −Y de ROS, y = arriba, z = −X de ROS);
##  - color: mesh → material → albedo (el material se comparte entre cajas del mismo color; «Make Unique» para
##    cambiar solo una).
## No escales el nodo: cambia el tamaño de la malla (la colisión se calcula con mesh.size).
##
## Al arrancar, `mundo_base.gd` le pone la colisión si `solido` y, en el perfil ligero de la Vita, la funde con las
## demás cajas de su color en una sola malla (28 draws → 11).

## Lleva colisión (choca el robot, la ven el LiDAR y el mapa). Las láminas del suelo (zonas, carreteras) no.
@export var solido := true
