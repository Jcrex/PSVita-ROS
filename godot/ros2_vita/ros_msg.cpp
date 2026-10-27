// ros_msg.cpp — ¡SIN COMPILAR! (Godot 4.x in-tree; validar en el host del PC, puerta G1)
#include "ros_msg.h"

#include "core/object/class_db.h"
#include "core/string/print_string.h"

#include <string.h>

Vector<uint8_t> RosMsg::schema_blob;
msg_schema RosMsg::schema;
bool RosMsg::schema_loaded = false;

// ------------------------------------------------------------------ esquema
Error RosMsg::load_schema_bytes(const Vector<uint8_t> &p_blob) {
	ERR_FAIL_COND_V_MSG(p_blob.is_empty(), ERR_INVALID_PARAMETER, "RosMsg: esquema vacío.");
	schema_blob = p_blob; // copia: el blob debe vivir mientras exista `schema`
	msg_schema tmp;
	if (msg_schema_init(&tmp, schema_blob.ptr(), schema_blob.size()) != MSG_SCHEMA_OK) {
		schema_blob.clear();
		schema_loaded = false;
		ERR_FAIL_V_MSG(ERR_FILE_CORRUPT, "RosMsg: esquema .rsch inválido.");
	}
	schema = tmp;
	schema_loaded = true;
	return OK;
}

Error RosMsg::load_schema_file(const String &p_path) {
	Error err = OK;
	Vector<uint8_t> bytes = FileAccess::get_file_as_bytes(p_path, &err);
	ERR_FAIL_COND_V_MSG(err != OK, err, vformat("RosMsg: no se pudo leer el esquema '%s'.", p_path));
	return load_schema_bytes(bytes);
}

PackedStringArray RosMsg::list_types() {
	PackedStringArray out;
	if (!schema_loaded) {
		return out;
	}
	for (uint32_t i = 0; i < msg_schema_type_count(&schema); i++) {
		const char *name = nullptr;
		if (msg_schema_type_name(&schema, i, &name) == MSG_SCHEMA_OK) {
			out.push_back(String::utf8(name));
		}
	}
	return out;
}

// ------------------------------------------------------------- por defecto
static Variant _zero_packed(int p_prim, int p_n) {
	switch (p_prim) {
		case MSG_PRIM_U8: {
			PackedByteArray a;
			a.resize(p_n);
			a.fill(0);
			return a;
		}
		case MSG_PRIM_F32: {
			PackedFloat32Array a;
			a.resize(p_n);
			a.fill(0.0f);
			return a;
		}
		case MSG_PRIM_F64: {
			PackedFloat64Array a;
			a.resize(p_n);
			a.fill(0.0);
			return a;
		}
		case MSG_PRIM_I64:
		case MSG_PRIM_U32:
		case MSG_PRIM_U64: {
			PackedInt64Array a;
			a.resize(p_n);
			a.fill(0);
			return a;
		}
		case MSG_PRIM_BOOL: {
			Array a;
			a.resize(p_n);
			for (int i = 0; i < p_n; i++) {
				a[i] = false;
			}
			return a;
		}
		default: { // I8, I16, U16, I32
			PackedInt32Array a;
			a.resize(p_n);
			a.fill(0);
			return a;
		}
	}
}

Variant RosMsg::_default_for(const msg_field_info &f) {
	int fixed = f.array == MSG_ARRAY_FIXED ? (int)f.array_len : 0;
	if (f.array == MSG_ARRAY_NONE) {
		if (f.kind == MSG_KIND_PRIM) {
			if (f.prim == MSG_PRIM_BOOL) {
				return false;
			}
			if (f.prim == MSG_PRIM_F32 || f.prim == MSG_PRIM_F64) {
				return 0.0;
			}
			return (int64_t)0;
		}
		if (f.kind == MSG_KIND_STRING) {
			return String();
		}
		Ref<RosMsg> child;
		child.instantiate();
		child->init_idx(f.type_idx);
		return child;
	}
	if (f.kind == MSG_KIND_PRIM) {
		return _zero_packed(f.prim, fixed);
	}
	if (f.kind == MSG_KIND_STRING) {
		PackedStringArray a;
		a.resize(fixed);
		return a;
	}
	Array arr;
	arr.resize(fixed);
	for (int i = 0; i < fixed; i++) {
		Ref<RosMsg> child;
		child.instantiate();
		child->init_idx(f.type_idx);
		arr[i] = child;
	}
	return arr;
}

void RosMsg::init_idx(uint32_t p_type_idx) {
	ERR_FAIL_COND_MSG(!schema_loaded, "RosMsg: carga primero un esquema (RosMsg.load_schema_file).");
	const char *name = nullptr;
	ERR_FAIL_COND_MSG(msg_schema_type_name(&schema, p_type_idx, &name) != MSG_SCHEMA_OK, "RosMsg: tipo fuera del esquema.");
	type_idx = p_type_idx;
	ros_name = String::utf8(name);
	members.clear();
	uint32_t nf = 0;
	msg_schema_field_count(&schema, type_idx, &nf);
	for (uint32_t i = 0; i < nf; i++) {
		msg_field_info f;
		msg_schema_field(&schema, type_idx, i, &f);
		members[StringName(String::utf8(f.name))] = _default_for(f);
	}
}

void RosMsg::init(const String &p_ros_type) {
	if (type_idx != MSG_SCHEMA_NO_TYPE) {
		return; // ya inicializado (re-entrada benigna, como en rclgd)
	}
	ERR_FAIL_COND_MSG(!schema_loaded, "RosMsg: carga primero un esquema (RosMsg.load_schema_file).");
	uint32_t idx = 0;
	CharString cs = p_ros_type.utf8();
	ERR_FAIL_COND_MSG(msg_schema_find_type(&schema, cs.get_data(), &idx) != MSG_SCHEMA_OK,
			vformat("RosMsg: tipo '%s' no está en el esquema.", p_ros_type));
	init_idx(idx);
}

Ref<RosMsg> RosMsg::from_type(const String &p_ros_type) {
	Ref<RosMsg> msg;
	msg.instantiate();
	msg->init(p_ros_type);
	if (msg->type_idx == MSG_SCHEMA_NO_TYPE) {
		return Ref<RosMsg>(); // null si el tipo no existe (igual que rclgd)
	}
	return msg;
}

// ------------------------------------------------------------------ acceso
bool RosMsg::_find_field(const StringName &p_name, msg_field_info &r_info) const {
	if (type_idx == MSG_SCHEMA_NO_TYPE) {
		return false;
	}
	CharString want = String(p_name).utf8();
	uint32_t nf = 0;
	msg_schema_field_count(&schema, type_idx, &nf);
	for (uint32_t i = 0; i < nf; i++) {
		msg_field_info f;
		msg_schema_field(&schema, type_idx, i, &f);
		if (strcmp(f.name, want.get_data()) == 0) {
			r_info = f;
			return true;
		}
	}
	return false;
}

static int64_t _to_int(const Variant &v) {
	return v.get_type() == Variant::FLOAT ? (int64_t)(double)v : (int64_t)v;
}

Variant RosMsg::_coerce(const msg_field_info &f, const Variant &v, bool &r_ok) const {
	r_ok = true;
	if (f.array == MSG_ARRAY_NONE) {
		if (f.kind == MSG_KIND_PRIM) {
			if (f.prim == MSG_PRIM_BOOL) {
				return (bool)v;
			}
			if (f.prim == MSG_PRIM_F32 || f.prim == MSG_PRIM_F64) {
				return (double)v;
			}
			return _to_int(v);
		}
		if (f.kind == MSG_KIND_STRING) {
			return String(v);
		}
		Ref<RosMsg> m = v;
		r_ok = m.is_valid() && m->type_idx == f.type_idx;
		return m;
	}
	// arrays: se admiten Packed*Array o Array; se normaliza al tipo canónico
	Array src = v;
	int n = src.size();
	if (f.array == MSG_ARRAY_FIXED && n != (int)f.array_len) {
		r_ok = false;
		return Variant();
	}
	if (f.kind == MSG_KIND_PRIM) {
		Variant out = _zero_packed(f.prim, n);
		switch (f.prim) {
			case MSG_PRIM_U8: {
				PackedByteArray a = out;
				for (int i = 0; i < n; i++) a.write[i] = (uint8_t)_to_int(src[i]);
				return a;
			}
			case MSG_PRIM_F32: {
				PackedFloat32Array a = out;
				for (int i = 0; i < n; i++) a.write[i] = (float)(double)src[i];
				return a;
			}
			case MSG_PRIM_F64: {
				PackedFloat64Array a = out;
				for (int i = 0; i < n; i++) a.write[i] = (double)src[i];
				return a;
			}
			case MSG_PRIM_I64:
			case MSG_PRIM_U32:
			case MSG_PRIM_U64: {
				PackedInt64Array a = out;
				for (int i = 0; i < n; i++) a.write[i] = _to_int(src[i]);
				return a;
			}
			case MSG_PRIM_BOOL: {
				Array a = out;
				for (int i = 0; i < n; i++) a[i] = (bool)src[i];
				return a;
			}
			default: {
				PackedInt32Array a = out;
				for (int i = 0; i < n; i++) a.write[i] = (int32_t)_to_int(src[i]);
				return a;
			}
		}
	}
	if (f.kind == MSG_KIND_STRING) {
		PackedStringArray a;
		a.resize(n);
		for (int i = 0; i < n; i++) a.write[i] = String(src[i]);
		return a;
	}
	Array out;
	out.resize(n);
	for (int i = 0; i < n; i++) {
		Ref<RosMsg> m = src[i];
		if (m.is_null() || m->type_idx != f.type_idx) {
			r_ok = false;
			return Variant();
		}
		out[i] = m;
	}
	return out;
}

bool RosMsg::_set(const StringName &p_name, const Variant &p_value) {
	msg_field_info f;
	if (!_find_field(p_name, f)) {
		return false;
	}
	bool ok = true;
	Variant v = _coerce(f, p_value, ok);
	if (!ok) {
		ERR_PRINT(vformat("RosMsg: valor no válido para el campo '%s' de %s.", String(p_name), ros_name));
		return false;
	}
	members[p_name] = v;
	return true;
}

bool RosMsg::_get(const StringName &p_name, Variant &r_ret) const {
	const Variant *v = members.getptr(p_name);
	if (!v) {
		return false;
	}
	r_ret = *v;
	return true;
}

void RosMsg::_get_property_list(List<PropertyInfo> *p_list) const {
	if (type_idx == MSG_SCHEMA_NO_TYPE) {
		return;
	}
	uint32_t nf = 0;
	msg_schema_field_count(&schema, type_idx, &nf);
	for (uint32_t i = 0; i < nf; i++) {
		msg_field_info f;
		msg_schema_field(&schema, type_idx, i, &f);
		StringName key(String::utf8(f.name));
		const Variant *v = members.getptr(key);
		p_list->push_back(PropertyInfo(v ? v->get_type() : Variant::NIL, key));
	}
}

Variant RosMsg::get_member(const StringName &p_name) const {
	Variant v;
	_get(p_name, v);
	return v;
}

void RosMsg::set_member(const StringName &p_name, const Variant &p_value) {
	_set(p_name, p_value);
}

String RosMsg::get_type_name() const {
	// "geometry_msgs/msg/Twist" -> "RosGeometryMsgsTwist" (igual que rclgd)
	if (type_idx == MSG_SCHEMA_NO_TYPE) {
		return "RosUnknownType";
	}
	return "Ros" + ros_name.replace("/msg/", " ").replace("/", " ").to_pascal_case();
}

// ---------------------------------------------------------------- CDR: decode
namespace {

struct DFrame {
	Ref<RosMsg> msg;
	String arr_name;
	Array arr; // elementos struct
	PackedStringArray sarr; // elementos string
	bool arr_is_string = false;
};

struct DecCtx {
	Vector<DFrame> stack;
	Ref<RosMsg> root;
};

static uint64_t _ld(const uint8_t *p, int size) {
	uint64_t v = 0;
	for (int i = size - 1; i >= 0; i--) {
		v = (v << 8) | p[i];
	}
	return v;
}

static Variant _prim_variant(int prim, uint64_t raw) {
	switch (prim) {
		case MSG_PRIM_BOOL: return raw != 0;
		case MSG_PRIM_I8: return (int64_t)(int8_t)raw;
		case MSG_PRIM_I16: return (int64_t)(int16_t)raw;
		case MSG_PRIM_I32: return (int64_t)(int32_t)raw;
		case MSG_PRIM_I64: return (int64_t)raw;
		case MSG_PRIM_F32: {
			uint32_t u = (uint32_t)raw;
			float f;
			memcpy(&f, &u, 4);
			return (double)f;
		}
		case MSG_PRIM_F64: {
			double d;
			memcpy(&d, &raw, 8);
			return d;
		}
		default: return (int64_t)raw; // U8, U16, U32, U64
	}
}

}; // namespace

// Los callbacks son funciones C estáticas (los llama msg-schema)
extern "C" {

static int d_begin_struct(void *c, const char *name, uint32_t type_idx) {
	DecCtx *d = (DecCtx *)c;
	Ref<RosMsg> m;
	m.instantiate();
	m->init_idx(type_idx);
	if (d->stack.is_empty()) {
		d->root = m;
	} else {
		DFrame &parent = d->stack.write[d->stack.size() - 1];
		if (name) {
			parent.msg->set_member(StringName(String::utf8(name)), m);
		} else {
			parent.arr.push_back(m);
		}
	}
	DFrame fr;
	fr.msg = m;
	d->stack.push_back(fr);
	return 0;
}

static int d_end_struct(void *c) {
	DecCtx *d = (DecCtx *)c;
	d->stack.resize(d->stack.size() - 1);
	return 0;
}

static int d_prim(void *c, const char *name, int prim, uint64_t raw) {
	DecCtx *d = (DecCtx *)c;
	d->stack.write[d->stack.size() - 1].msg->set_member(StringName(String::utf8(name)), _prim_variant(prim, raw));
	return 0;
}

static int d_string(void *c, const char *name, const uint8_t *s, uint32_t len) {
	DecCtx *d = (DecCtx *)c;
	DFrame &fr = d->stack.write[d->stack.size() - 1];
	String str = String::utf8((const char *)s, (int)len);
	if (name) {
		fr.msg->set_member(StringName(String::utf8(name)), str);
	} else {
		fr.sarr.push_back(str);
	}
	return 0;
}

static int d_prim_array(void *c, const char *name, int prim, const uint8_t *data, uint32_t count) {
	DecCtx *d = (DecCtx *)c;
	Variant out;
	int n = (int)count;
	switch (prim) {
		case MSG_PRIM_U8: {
			PackedByteArray a;
			a.resize(n);
			if (n) memcpy(a.ptrw(), data, n);
			out = a;
		} break;
		case MSG_PRIM_F32: {
			PackedFloat32Array a;
			a.resize(n);
			if (n) memcpy(a.ptrw(), data, (size_t)n * 4);
			out = a;
		} break;
		case MSG_PRIM_F64: {
			PackedFloat64Array a;
			a.resize(n);
			if (n) memcpy(a.ptrw(), data, (size_t)n * 8);
			out = a;
		} break;
		case MSG_PRIM_I32: {
			PackedInt32Array a;
			a.resize(n);
			if (n) memcpy(a.ptrw(), data, (size_t)n * 4);
			out = a;
		} break;
		case MSG_PRIM_I64:
		case MSG_PRIM_U64:
		case MSG_PRIM_U32: {
			int sz = prim == MSG_PRIM_U32 ? 4 : 8;
			PackedInt64Array a;
			a.resize(n);
			for (int i = 0; i < n; i++) a.write[i] = (int64_t)_ld(data + (size_t)i * sz, sz);
			out = a;
		} break;
		case MSG_PRIM_BOOL: {
			Array a;
			for (int i = 0; i < n; i++) a.push_back(data[i] != 0);
			out = a;
		} break;
		default: { // I8, U16, I16
			int sz = msg_prim_size((msg_prim)prim);
			PackedInt32Array a;
			a.resize(n);
			for (int i = 0; i < n; i++) {
				uint64_t raw = _ld(data + (size_t)i * sz, sz);
				a.write[i] = prim == MSG_PRIM_I8 ? (int8_t)raw : prim == MSG_PRIM_I16 ? (int16_t)raw : (int32_t)(uint16_t)raw;
			}
			out = a;
		} break;
	}
	d->stack.write[d->stack.size() - 1].msg->set_member(StringName(String::utf8(name)), out);
	return 0;
}

static int d_begin_array(void *c, const char *name, uint32_t count, uint32_t elem_type) {
	DecCtx *d = (DecCtx *)c;
	(void)count;
	DFrame &fr = d->stack.write[d->stack.size() - 1];
	fr.arr_name = String::utf8(name);
	fr.arr.clear();
	fr.sarr.clear();
	fr.arr_is_string = elem_type == MSG_SCHEMA_NO_TYPE;
	return 0;
}

static int d_end_array(void *c) {
	DecCtx *d = (DecCtx *)c;
	DFrame &fr = d->stack.write[d->stack.size() - 1];
	if (fr.arr_is_string) {
		fr.msg->set_member(StringName(fr.arr_name), fr.sarr);
	} else {
		fr.msg->set_member(StringName(fr.arr_name), fr.arr);
	}
	return 0;
}

} // extern "C"

Error RosMsg::deserialize(const PackedByteArray &p_payload) {
	ERR_FAIL_COND_V_MSG(type_idx == MSG_SCHEMA_NO_TYPE, ERR_UNCONFIGURED, "RosMsg: sin tipo.");
	DecCtx ctx;
	msg_visitor vis = { d_begin_struct, d_end_struct, d_prim, d_string, d_prim_array, d_begin_array, d_end_array };
	int rc = msg_schema_decode(&schema, type_idx, p_payload.ptr(), p_payload.size(), &vis, &ctx, nullptr);
	if (rc != MSG_SCHEMA_OK || ctx.root.is_null()) {
		return rc == MSG_SCHEMA_ERR_TRUNCATED ? ERR_FILE_EOF : ERR_PARSE_ERROR;
	}
	// El decoder construyó un árbol nuevo: se adopta su contenido (el RosMsg actual
	// conserva su identidad, como exige el patrón "reutilizar el mensaje" de rclgd).
	members = ctx.root->members;
	return OK;
}

// ---------------------------------------------------------------- CDR: encode
namespace {

struct EFrame {
	Ref<RosMsg> msg;
	Variant arr; // array activo de este struct (Array o PackedStringArray)
	int idx = 0;
};

struct EncCtx {
	Vector<EFrame> stack;
	Ref<RosMsg> root;
	CharString tmp_str; // vida: hasta la siguiente llamada (el encoder copia al instante)
	Vector<uint8_t> scratch; // conversiones de arrays
};

static void _store_le(uint8_t *p, uint64_t v, int size) {
	for (int i = 0; i < size; i++) {
		p[i] = (uint8_t)(v >> (8 * i));
	}
}

}; // namespace

extern "C" {

static int e_begin_struct(void *c, const char *name, uint32_t type_idx) {
	EncCtx *e = (EncCtx *)c;
	(void)type_idx;
	Ref<RosMsg> m;
	if (e->stack.is_empty()) {
		m = e->root;
	} else {
		EFrame &top = e->stack.write[e->stack.size() - 1];
		if (name) {
			m = top.msg->get_member(StringName(String::utf8(name)));
		} else {
			Array a = top.arr;
			if (top.idx >= a.size()) return 1;
			m = a[top.idx++];
		}
	}
	if (m.is_null()) return 1;
	EFrame fr;
	fr.msg = m;
	e->stack.push_back(fr);
	return 0;
}

static int e_end_struct(void *c) {
	EncCtx *e = (EncCtx *)c;
	e->stack.resize(e->stack.size() - 1);
	return 0;
}

static int e_prim(void *c, const char *name, int prim, uint64_t *raw) {
	EncCtx *e = (EncCtx *)c;
	Variant v = e->stack[e->stack.size() - 1].msg->get_member(StringName(String::utf8(name)));
	switch (prim) {
		case MSG_PRIM_BOOL: *raw = (bool)v ? 1 : 0; break;
		case MSG_PRIM_F32: {
			float f = (float)(double)v;
			uint32_t u;
			memcpy(&u, &f, 4);
			*raw = u;
		} break;
		case MSG_PRIM_F64: {
			double d = (double)v;
			memcpy(raw, &d, 8);
		} break;
		default: *raw = (uint64_t)_to_int(v); break;
	}
	return 0;
}

static int e_string(void *c, const char *name, const uint8_t **s, uint32_t *len) {
	EncCtx *e = (EncCtx *)c;
	EFrame &top = e->stack.write[e->stack.size() - 1];
	String str;
	if (name) {
		str = top.msg->get_member(StringName(String::utf8(name)));
	} else {
		PackedStringArray a = top.arr;
		if (top.idx >= a.size()) return 1;
		str = a[top.idx++];
	}
	e->tmp_str = str.utf8();
	*s = (const uint8_t *)e->tmp_str.get_data();
	*len = (uint32_t)e->tmp_str.length();
	return 0;
}

static int e_prim_array(void *c, const char *name, int prim, uint32_t fixed, const uint8_t **data, uint32_t *count) {
	EncCtx *e = (EncCtx *)c;
	(void)fixed;
	Variant v = e->stack[e->stack.size() - 1].msg->get_member(StringName(String::utf8(name)));
	// Rutas directas (sin copia): el packed ya tiene el layout little-endian del CDR
	if (prim == MSG_PRIM_U8 && v.get_type() == Variant::PACKED_BYTE_ARRAY) {
		PackedByteArray a = v;
		e->scratch.resize(a.size());
		if (a.size()) memcpy(e->scratch.ptrw(), a.ptr(), a.size());
		*data = e->scratch.ptr();
		*count = (uint32_t)a.size();
		return 0;
	}
	// General: se serializa elemento a elemento en `scratch`
	Array a = v;
	int sz = msg_prim_size((msg_prim)prim);
	e->scratch.resize((size_t)a.size() * sz);
	for (int i = 0; i < a.size(); i++) {
		uint8_t *p = e->scratch.ptrw() + (size_t)i * sz;
		if (prim == MSG_PRIM_F32) {
			float f = (float)(double)a[i];
			uint32_t u;
			memcpy(&u, &f, 4);
			_store_le(p, u, 4);
		} else if (prim == MSG_PRIM_F64) {
			double d = (double)a[i];
			uint64_t u;
			memcpy(&u, &d, 8);
			_store_le(p, u, 8);
		} else if (prim == MSG_PRIM_BOOL) {
			p[0] = (bool)a[i] ? 1 : 0;
		} else {
			_store_le(p, (uint64_t)_to_int(a[i]), sz);
		}
	}
	*data = e->scratch.ptr();
	*count = (uint32_t)a.size();
	return 0;
}

static int e_array_len(void *c, const char *name, uint32_t fixed, uint32_t *count) {
	EncCtx *e = (EncCtx *)c;
	(void)fixed;
	EFrame &top = e->stack.write[e->stack.size() - 1];
	top.arr = top.msg->get_member(StringName(String::utf8(name)));
	top.idx = 0;
	if (top.arr.get_type() == Variant::PACKED_STRING_ARRAY) {
		*count = (uint32_t)PackedStringArray(top.arr).size();
	} else {
		*count = (uint32_t)Array(top.arr).size();
	}
	return 0;
}

} // extern "C"

PackedByteArray RosMsg::serialize() const {
	PackedByteArray out;
	ERR_FAIL_COND_V_MSG(type_idx == MSG_SCHEMA_NO_TYPE, out, "RosMsg: sin tipo.");
	EncCtx ctx;
	ctx.root = Ref<RosMsg>(const_cast<RosMsg *>(this));
	msg_source src = { e_begin_struct, e_end_struct, e_prim, e_string, e_prim_array, e_array_len };
	size_t cap = 1024;
	const size_t max_cap = 8 * 1024 * 1024; // tope de seguridad (Image grande)
	while (cap <= max_cap) {
		out.resize(cap);
		ctx.stack.clear();
		size_t written = 0;
		int rc = msg_schema_encode(&schema, type_idx, &src, &ctx, out.ptrw(), cap, &written);
		if (rc == MSG_SCHEMA_OK) {
			out.resize(written);
			return out;
		}
		if (rc != MSG_SCHEMA_ERR_NO_SPACE) {
			ERR_PRINT(vformat("RosMsg: serialize falló (código %d) para %s.", rc, ros_name));
			return PackedByteArray();
		}
		cap *= 2;
	}
	ERR_PRINT("RosMsg: mensaje demasiado grande para serializar.");
	return PackedByteArray();
}

// ---------------------------------------------------------------- texto
String RosMsg::to_string() {
	String out = get_type_name() + " {\n";
	uint32_t nf = 0;
	if (type_idx != MSG_SCHEMA_NO_TYPE) {
		msg_schema_field_count(&schema, type_idx, &nf);
	}
	for (uint32_t i = 0; i < nf; i++) {
		msg_field_info f;
		msg_schema_field(&schema, type_idx, i, &f);
		out += "  \"" + String::utf8(f.name) + "\": " + get_member(StringName(String::utf8(f.name))).stringify() + "\n";
	}
	return out + "}";
}

void RosMsg::_bind_methods() {
	ClassDB::bind_static_method("RosMsg", D_METHOD("from_type", "ros_type_name"), &RosMsg::from_type);
	ClassDB::bind_static_method("RosMsg", D_METHOD("load_schema_file", "path"), &RosMsg::load_schema_file);
	ClassDB::bind_static_method("RosMsg", D_METHOD("has_schema"), &RosMsg::has_schema);
	ClassDB::bind_static_method("RosMsg", D_METHOD("list_types"), &RosMsg::list_types);
	ClassDB::bind_method(D_METHOD("init", "ros_type_name"), &RosMsg::init);
	ClassDB::bind_method(D_METHOD("get_member", "name"), &RosMsg::get_member);
	ClassDB::bind_method(D_METHOD("set_member", "name", "value"), &RosMsg::set_member);
	ClassDB::bind_method(D_METHOD("get_type_name"), &RosMsg::get_type_name);
	ClassDB::bind_method(D_METHOD("get_ros_interface_name"), &RosMsg::get_ros_interface_name);
	ClassDB::bind_method(D_METHOD("serialize"), &RosMsg::serialize);
	ClassDB::bind_method(D_METHOD("deserialize", "payload"), &RosMsg::deserialize);
}
