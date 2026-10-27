// ¡ESQUELETO SIN VERIFICAR! (Godot 3.x; validar en el PC / en hardware)
#include "ros_node.h"

#include "core/os/memory.h"

#include <string.h>

RosNode::RosNode() {
	size_t need = msg_ring_required_size(SLOT_SIZE, SLOT_COUNT);
	// memalloc de Godot devuelve memoria alineada para cualquier tipo
	// (>= 8 bytes), requisito de msg_ring_create. Se libera en el destructor.
	uint8_t *mem = (uint8_t *)memalloc(need);
	ring = msg_ring_create(mem, need, SLOT_SIZE, SLOT_COUNT);
	if (!ring) {
		memfree(mem);
		ERR_PRINT("ros2_vita: msg_ring_create fallo");
	}
}

RosNode::~RosNode() {
	// El ring vive al inicio del bloque reservado en el constructor.
	if (ring) {
		memfree(ring);
		ring = nullptr;
	}
}

void RosNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_dropped"), &RosNode::get_dropped);
	ClassDB::bind_method(D_METHOD("get_queued"), &RosNode::get_queued);
	ADD_SIGNAL(MethodInfo("message_received",
			PropertyInfo(Variant::INT, "topic_id"),
			PropertyInfo(Variant::POOL_BYTE_ARRAY, "cdr")));
}

void RosNode::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY:
			set_process(true);
			break;
		case NOTIFICATION_PROCESS: {
			// Hilo principal: único consumidor del ring.
			if (!ring) {
				break;
			}
			uint8_t buf[SLOT_SIZE];
			size_t n = 0;
			// Tope por frame para no monopolizar el hilo si hay ráfaga.
			for (int i = 0; i < 32 && msg_ring_pop(ring, buf, sizeof buf, &n) == MSG_RING_OK; i++) {
				if (n < 2) {
					continue; // mensaje corrupto: sin topic_id
				}
				int topic_id = buf[0] | (buf[1] << 8);
				PoolByteArray payload;
				payload.resize(n - 2);
				if (n > 2) {
					PoolByteArray::Write w = payload.write();
					memcpy(w.ptr(), buf + 2, n - 2);
				}
				emit_signal("message_received", topic_id, payload);
			}
		} break;
	}
}

int RosNode::push_from_network(uint16_t topic_id, const uint8_t *cdr, size_t len) {
	if (!ring || len + 2 > SLOT_SIZE) {
		return MSG_RING_ERR_TOO_BIG;
	}
	uint8_t buf[SLOT_SIZE];
	buf[0] = topic_id & 0xFF;
	buf[1] = topic_id >> 8;
	memcpy(buf + 2, cdr, len);
	return msg_ring_push(ring, buf, len + 2);
}

int RosNode::get_dropped() const {
	return (int)msg_ring_dropped(ring);
}

int RosNode::get_queued() const {
	return (int)msg_ring_count(ring);
}
