/**
 * tf_tree.c — Implementación C11 del contrato include/tf_tree.h.
 */
#include "tf_tree.h"

#include <string.h>

#define ALIGN 8u
#define NO_PARENT (-1)

typedef struct {
    char    name[TF_TREE_NAME_MAX];
    int8_t  parent;  /* índice del padre o NO_PARENT */
    uint8_t used;
    uint8_t pad[2];
    float   t[3];
    float   q[4];    /* x, y, z, w (normalizado) */
} frame_t;

struct tf_tree {
    uint32_t count;
    uint32_t rejected;
    frame_t  frames[TF_TREE_MAX_FRAMES];
};

_Static_assert(sizeof(frame_t) == 96, "layout frame_t");
_Static_assert(sizeof(struct tf_tree) == 8 + 32 * 96, "layout tf_tree");

/* Quita una barra inicial. Devuelve NULL si el nombre es inválido (vacío o
 * de 64+ caracteres tras quitar la barra). */
static const char *norm(const char *s)
{
    if (s == NULL) {
        return NULL;
    }
    if (s[0] == '/') {
        s++;
    }
    size_t n = strlen(s);
    if (n == 0 || n >= TF_TREE_NAME_MAX) {
        return NULL;
    }
    return s;
}

static int find(const tf_tree *tr, const char *name)
{
    for (uint32_t i = 0; i < TF_TREE_MAX_FRAMES; i++) {
        if (tr->frames[i].used && strcmp(tr->frames[i].name, name) == 0) {
            return (int)i;
        }
    }
    return -1;
}

static int add(tf_tree *tr, const char *name)
{
    for (uint32_t i = 0; i < TF_TREE_MAX_FRAMES; i++) {
        if (!tr->frames[i].used) {
            memset(&tr->frames[i], 0, sizeof tr->frames[i]);
            strcpy(tr->frames[i].name, name);
            tr->frames[i].used = 1;
            tr->frames[i].parent = NO_PARENT;
            tr->frames[i].q[3] = 1.0f;
            tr->count++;
            return (int)i;
        }
    }
    return -1;
}

size_t tf_tree_required_size(void)
{
    return sizeof(struct tf_tree);
}

tf_tree *tf_tree_create(void *backing, size_t backing_len)
{
    if (backing == NULL || ((uintptr_t)backing & (ALIGN - 1u)) != 0 ||
        backing_len < sizeof(struct tf_tree)) {
        return NULL;
    }
    tf_tree *tr = (tf_tree *)backing;
    tf_tree_clear(tr);
    return tr;
}

void tf_tree_clear(tf_tree *tree)
{
    if (tree != NULL) {
        memset(tree, 0, sizeof *tree);
    }
}

int tf_tree_update(tf_tree *tree, const char *parent, const char *child,
                   const vizm_vec3 *t, const vizm_quat *q)
{
    if (tree == NULL || t == NULL || q == NULL) {
        return TF_TREE_ERR_INVALID_ARG;
    }
    const char *p = norm(parent);
    const char *c = norm(child);
    if (p == NULL || c == NULL) {
        return TF_TREE_ERR_INVALID_ARG;
    }
    if (strcmp(p, c) == 0) {
        return TF_TREE_ERR_CYCLE;
    }
    int pi = find(tree, p);
    int ci = find(tree, c);

    /* Ciclo: solo posible si ambos existen y el hijo es ancestro del padre. */
    if (pi >= 0 && ci >= 0) {
        int node = pi;
        for (int hops = 0; node != NO_PARENT && hops <= TF_TREE_MAX_FRAMES; hops++) {
            if (node == ci) {
                return TF_TREE_ERR_CYCLE;
            }
            node = tree->frames[node].parent;
        }
    }
    /* Capacidad: huecos que hacen falta (0, 1 o 2) vs. libres. */
    uint32_t missing = (uint32_t)(pi < 0) + (uint32_t)(ci < 0);
    if (tree->count + missing > TF_TREE_MAX_FRAMES) {
        return TF_TREE_ERR_FULL;
    }
    if (pi < 0) {
        pi = add(tree, p);
    }
    if (ci < 0) {
        ci = add(tree, c);
    }
    vizm_quat qn;
    vizm_quat_normalize(&qn, q);
    frame_t *f = &tree->frames[ci];
    f->parent = (int8_t)pi;
    f->t[0] = t->x; f->t[1] = t->y; f->t[2] = t->z;
    f->q[0] = qn.x; f->q[1] = qn.y; f->q[2] = qn.z; f->q[3] = qn.w;
    return TF_TREE_OK;
}

int tf_tree_apply_message(tf_tree *tree, const msg_cdr_tf_message *msg)
{
    if (tree == NULL || msg == NULL) {
        return TF_TREE_ERR_INVALID_ARG;
    }
    int applied = 0;
    for (uint32_t i = 0; i < msg->count && i < MSG_CDR_MAX_TRANSFORMS; i++) {
        const msg_cdr_transform *m = &msg->items[i];
        vizm_vec3 t = { (float)m->translation[0], (float)m->translation[1],
                        (float)m->translation[2] };
        vizm_quat q = { (float)m->rotation[0], (float)m->rotation[1],
                        (float)m->rotation[2], (float)m->rotation[3] };
        if (tf_tree_update(tree, m->frame_id, m->child_frame_id, &t, &q) == TF_TREE_OK) {
            applied++;
        } else {
            tree->rejected++;
        }
    }
    return applied;
}

/* M_root<-frame: compone hacia arriba hasta la raíz. `*root` recibe su índice. */
static void to_root(const tf_tree *tr, int idx, vizm_mat4 *m, int *root)
{
    vizm_mat4_identity(m);
    int node = idx;
    for (int hops = 0; hops <= TF_TREE_MAX_FRAMES; hops++) {
        const frame_t *f = &tr->frames[node];
        if (f->parent == NO_PARENT) {
            break;
        }
        vizm_vec3 t = { f->t[0], f->t[1], f->t[2] };
        vizm_quat q = { f->q[0], f->q[1], f->q[2], f->q[3] };
        vizm_mat4 local;
        vizm_mat4_from_trs(&local, &t, &q);
        vizm_mat4_mul(m, &local, m); /* M = L(node) · M */
        node = f->parent;
    }
    *root = node;
}

int tf_tree_lookup(const tf_tree *tree, const char *target, const char *source,
                   vizm_mat4 *out)
{
    if (tree == NULL || out == NULL) {
        return TF_TREE_ERR_INVALID_ARG;
    }
    const char *tn = norm(target);
    const char *sn = norm(source);
    if (tn == NULL || sn == NULL) {
        return TF_TREE_ERR_INVALID_ARG;
    }
    int ti = find(tree, tn);
    int si = find(tree, sn);
    if (ti < 0 || si < 0) {
        return TF_TREE_ERR_UNKNOWN_FRAME;
    }
    if (ti == si) {
        vizm_mat4_identity(out);
        return TF_TREE_OK;
    }
    vizm_mat4 mt, ms, inv;
    int rt, rs;
    to_root(tree, ti, &mt, &rt);
    to_root(tree, si, &ms, &rs);
    if (rt != rs) {
        return TF_TREE_ERR_NO_PATH;
    }
    vizm_mat4_inverse_rigid(&inv, &mt);
    vizm_mat4_mul(out, &inv, &ms); /* p_target = M_root<-target⁻¹ · M_root<-source · p_source */
    return TF_TREE_OK;
}

size_t tf_tree_frame_count(const tf_tree *tree)
{
    return tree == NULL ? 0 : tree->count;
}

uint32_t tf_tree_rejected(const tf_tree *tree)
{
    return tree == NULL ? 0 : tree->rejected;
}
