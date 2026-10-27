// ¡ESQUELETO SIN VERIFICAR! (Godot 3.x; validar en el PC / en hardware)
//
// RosNode: nodo de Godot que recibe mensajes ROS2 por el ring SPSC y los
// emite como señal en el hilo principal. La parte de red (sesión XRCE,
// suscripciones) sigue pendiente (P4 en docs/12 §8).
#ifndef ROS2_VITA_ROS_NODE_H
#define ROS2_VITA_ROS_NODE_H

#include "scene/main/node.h"

extern "C" {
#include "msg_ring.h"
}

class RosNode : public Node {
	GDCLASS(RosNode, Node);

	// Un mensaje = [uint16 topic_id][payload CDR]. Ver docs/13 §4.
	static const size_t SLOT_SIZE = 512;
	static const size_t SLOT_COUNT = 64; // potencia de 2

	msg_ring *ring = nullptr;

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	// Llamado desde el HILO DE RED (callback de XRCE): único productor.
	// Devuelve el código de msg_ring_push (0 = OK, <0 = descartado).
	int push_from_network(uint16_t topic_id, const uint8_t *cdr, size_t len);

	int get_dropped() const;
	int get_queued() const;

	RosNode();
	~RosNode();
};

#endif
