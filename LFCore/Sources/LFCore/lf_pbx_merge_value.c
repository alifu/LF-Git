/*
 * lf_pbx_merge_value.c — field-by-field merge of one object changed on both sides.
 *
 * Dictionaries merge key by key (recursively). Arrays of plain tokens outside buildSettings merge
 * as ordered sets: removals and additions from both sides apply, the side that reordered the
 * shared elements (if only one did) provides the order, and the other side's additions go after
 * their nearest preceding element. Elements are identified by (token, occurrence), so lists that
 * already contain duplicates (left behind by older merges) still merge, one copy at a time.
 * Arrays inside buildSettings (compiler/linker flags, where order and duplicates matter) and
 * arrays both sides reordered differently are never merged; the setting becomes a conflict.
 *
 * Untouched items keep their raw text, so the output matches Xcode's formatting.
 */
#include "lf_pbx.h"

#include <stdlib.h>
#include <string.h>

typedef enum part_kind {
    PART_ITEM,     /* an item copied verbatim from `owner` */
    PART_MERGED,   /* ours' key with a merged value from the scratch buffer */
    PART_CONFLICT, /* ours/base/theirs versions of one item between markers */
} part_kind;

typedef struct part {
    part_kind kind;
    const pbx_value *owner;
    const pbx_item *item;
    size_t merged_start, merged_end;
    const pbx_value *ours_owner, *base_owner, *theirs_owner;
    const pbx_item *ours, *base, *theirs;
    const uint8_t *key;
    size_t key_length;
} part;

typedef struct part_list {
    part *items;
    size_t count;
    size_t capacity;
} part_list;

static pbx_merge_status merge_values(const pbx_merge_ctx *ctx, const pbx_value *base, const pbx_value *ours,
                                     const pbx_value *theirs, int in_build_settings, lf_buf *out, uint64_t *conflicts);

/* ---- Small helpers --------------------------------------------------------------------------- */

static int bytes_equal(const uint8_t *a, size_t a_length, const uint8_t *b, size_t b_length) {
    return a_length == b_length && memcmp(a, b, a_length) == 0;
}

static int item_values_equal(const pbx_value *a_owner, const pbx_item *a, const pbx_value *b_owner, const pbx_item *b) {
    if (a == NULL || b == NULL) {
        return a == b;
    }
    return bytes_equal(a_owner->data + a->value_start, a->value_end - a->value_start, b_owner->data + b->value_start,
                       b->value_end - b->value_start);
}

static const pbx_item *find_key(const pbx_value *dict, const uint8_t *key, size_t length) {
    if (dict == NULL) {
        return NULL;
    }
    for (size_t i = 0; i < dict->count; i++) {
        const pbx_item *item = &dict->items[i];
        if (bytes_equal(dict->data + item->key_start, item->key_end - item->key_start, key, length)) {
            return item;
        }
    }
    return NULL;
}

static int key_is(const uint8_t *key, size_t length, const char *name) {
    return bytes_equal(key, length, (const uint8_t *)name, strlen(name));
}

/* Xcode sorts dictionary keys by their unquoted text, with "isa" first. */
static int key_compare(const uint8_t *a, size_t a_length, const uint8_t *b, size_t b_length) {
    if (a_length >= 2 && a[0] == '"') {
        a++, a_length -= 2;
    }
    if (b_length >= 2 && b[0] == '"') {
        b++, b_length -= 2;
    }
    const size_t shorter = a_length < b_length ? a_length : b_length;
    const int order = memcmp(a, b, shorter);
    if (order != 0) {
        return order;
    }
    return a_length < b_length ? -1 : (a_length > b_length ? 1 : 0);
}

static int push_part(part_list *list, const part *item, size_t index) {
    if (list->count == list->capacity) {
        const size_t capacity = list->capacity ? list->capacity * 2 : 16;
        part *grown = realloc(list->items, capacity * sizeof *grown);
        if (grown == NULL) {
            return 0;
        }
        list->items = grown;
        list->capacity = capacity;
    }
    memmove(&list->items[index + 1], &list->items[index], (list->count - index) * sizeof *list->items);
    list->items[index] = *item;
    list->count++;
    return 1;
}

static int append_part(part_list *list, const part *item) {
    return push_part(list, item, list->count);
}

/* Inserts a key that only theirs has at Xcode's sorted position among ours' keys. */
static int insert_sorted(part_list *list, const part *item) {
    size_t index = 0;
    if (list->count > 0 && key_is(list->items[0].key, list->items[0].key_length, "isa")) {
        index = 1;
    }
    while (index < list->count &&
           key_compare(list->items[index].key, list->items[index].key_length, item->key, item->key_length) <= 0) {
        index++;
    }
    return push_part(list, item, index);
}

static part verbatim(const pbx_value *owner, const pbx_item *item) {
    part p = {0};
    p.kind = PART_ITEM;
    p.owner = owner;
    p.item = item;
    p.key = owner->data + item->key_start;
    p.key_length = item->key_end - item->key_start;
    return p;
}

static part conflict_part(const pbx_value *ours_owner, const pbx_item *ours, const pbx_value *base_owner,
                          const pbx_item *base, const pbx_value *theirs_owner, const pbx_item *theirs) {
    part p = {0};
    p.kind = PART_CONFLICT;
    p.ours_owner = ours_owner, p.ours = ours;
    p.base_owner = base_owner, p.base = base;
    p.theirs_owner = theirs_owner, p.theirs = theirs;
    const pbx_value *owner = ours ? ours_owner : theirs_owner;
    const pbx_item *item = ours ? ours : theirs;
    p.key = owner->data + item->key_start;
    p.key_length = item->key_end - item->key_start;
    return p;
}

/* ---- Conflict blocks --------------------------------------------------------------------------- */

static void write_marker(lf_buf *out, uint8_t marker, size_t size, const char *label) {
    lf_buf_append_repeat(out, marker, size);
    if (label != NULL && label[0] != '\0') {
        lf_buf_append(out, " ", 1);
        lf_buf_append_cstr(out, label);
    }
    lf_buf_append(out, "\n", 1);
}

static void write_side(lf_buf *out, const uint8_t *text, size_t length) {
    lf_buf_append(out, text, length);
    if (length > 0 && text[length - 1] != '\n') {
        lf_buf_append(out, "\n", 1);
    }
}

void pbx_write_conflict(lf_buf *out, const pbx_merge_ctx *ctx, const uint8_t *ours, size_t ours_length,
                        const uint8_t *base, size_t base_length, const uint8_t *theirs, size_t theirs_length) {
    write_marker(out, '<', ctx->marker_size, ctx->current_label);
    write_side(out, ours, ours_length);
    if (ctx->include_base) {
        write_marker(out, '|', ctx->marker_size, ctx->base_label);
        write_side(out, base, base_length);
    }
    write_marker(out, '=', ctx->marker_size, NULL);
    write_side(out, theirs, theirs_length);
    write_marker(out, '>', ctx->marker_size, ctx->incoming_label);
}

static void item_text(const pbx_value *owner, const pbx_item *item, const uint8_t **text, size_t *length) {
    *text = item ? owner->data + item->raw_start : NULL;
    *length = item ? item->raw_end - item->raw_start : 0;
}

/* ---- Dictionaries ------------------------------------------------------------------------------ */

static void render_dict(lf_buf *out, const pbx_merge_ctx *ctx, const pbx_value *ours, const part_list *parts,
                        const lf_buf *scratch) {
    lf_buf_append(out, ours->multiline ? "{\n" : "{", ours->multiline ? 2 : 1);
    for (size_t i = 0; i < parts->count; i++) {
        const part *p = &parts->items[i];
        if (p->kind == PART_ITEM) {
            lf_buf_append(out, p->owner->data + p->item->raw_start, p->item->raw_end - p->item->raw_start);
        } else if (p->kind == PART_MERGED) {
            lf_buf_append(out, ours->data + p->item->raw_start, p->item->value_start - p->item->raw_start);
            lf_buf_append(out, scratch->data + p->merged_start, p->merged_end - p->merged_start);
            lf_buf_append(out, ours->data + p->item->value_end, p->item->raw_end - p->item->value_end);
        } else {
            const uint8_t *o, *b, *t;
            size_t ol, bl, tl;
            item_text(p->ours_owner, p->ours, &o, &ol);
            item_text(p->base_owner, p->base, &b, &bl);
            item_text(p->theirs_owner, p->theirs, &t, &tl);
            pbx_write_conflict(out, ctx, o, ol, b, bl, t, tl);
        }
    }
    if (ours->multiline) {
        lf_buf_append(out, ours->data + ours->close_start, ours->end - ours->close_start);
    } else {
        lf_buf_append(out, "}", 1);
    }
}

typedef struct dict_merge {
    const pbx_merge_ctx *ctx;
    const pbx_value *base, *ours, *theirs;
    int in_build_settings;
    part_list parts;
    lf_buf scratch;
    uint64_t conflicts;
    int failed;
} dict_merge;

/* Decides one key that ours has. */
static void merge_ours_key(dict_merge *m, const pbx_item *ours_item) {
    const uint8_t *key = m->ours->data + ours_item->key_start;
    const size_t length = ours_item->key_end - ours_item->key_start;
    const pbx_item *theirs_item = find_key(m->theirs, key, length);
    const pbx_item *base_item = find_key(m->base, key, length);
    part p;
    if (theirs_item == NULL) {
        if (base_item != NULL && item_values_equal(m->ours, ours_item, m->base, base_item)) {
            return; /* deleted by theirs, untouched by ours */
        }
        p = base_item == NULL ? verbatim(m->ours, ours_item)
                              : conflict_part(m->ours, ours_item, m->base, base_item, m->theirs, NULL);
    } else if (item_values_equal(m->ours, ours_item, m->theirs, theirs_item) ||
               (base_item != NULL && item_values_equal(m->theirs, theirs_item, m->base, base_item))) {
        p = verbatim(m->ours, ours_item);
    } else if (base_item != NULL && item_values_equal(m->ours, ours_item, m->base, base_item)) {
        p = verbatim(m->theirs, theirs_item);
    } else {
        const size_t mark = m->scratch.length;
        uint64_t nested = 0;
        const int child_settings = m->in_build_settings || key_is(key, length, "buildSettings");
        const pbx_merge_status status = merge_values(m->ctx, base_item ? base_item->value : NULL, ours_item->value,
                                                     theirs_item->value, child_settings, &m->scratch, &nested);
        if (status == PBX_MERGE_NO_MEMORY) {
            m->failed = 1;
            return;
        }
        if (status == PBX_MERGE_OK) {
            p = verbatim(m->ours, ours_item);
            p.kind = PART_MERGED;
            p.merged_start = mark;
            p.merged_end = m->scratch.length;
            m->conflicts += nested;
        } else {
            lf_buf_truncate(&m->scratch, mark);
            p = conflict_part(m->ours, ours_item, m->base, base_item, m->theirs, theirs_item);
        }
    }
    if (p.kind == PART_CONFLICT) {
        m->conflicts++;
    }
    if (!append_part(&m->parts, &p)) {
        m->failed = 1;
    }
}

/* Decides one key that only theirs has. */
static void merge_theirs_key(dict_merge *m, const pbx_item *theirs_item) {
    const uint8_t *key = m->theirs->data + theirs_item->key_start;
    const size_t length = theirs_item->key_end - theirs_item->key_start;
    if (find_key(m->ours, key, length) != NULL) {
        return;
    }
    const pbx_item *base_item = find_key(m->base, key, length);
    part p;
    if (base_item == NULL) {
        p = verbatim(m->theirs, theirs_item); /* added by theirs */
    } else if (item_values_equal(m->theirs, theirs_item, m->base, base_item)) {
        return; /* deleted by ours, untouched by theirs */
    } else {
        p = conflict_part(m->ours, NULL, m->base, base_item, m->theirs, theirs_item);
        m->conflicts++;
    }
    if (!insert_sorted(&m->parts, &p)) {
        m->failed = 1;
    }
}

static pbx_merge_status merge_dicts(const pbx_merge_ctx *ctx, const pbx_value *base, const pbx_value *ours,
                                    const pbx_value *theirs, int in_build_settings, lf_buf *out, uint64_t *conflicts) {
    if (ours->multiline != theirs->multiline) {
        return PBX_MERGE_CONFLICT;
    }
    dict_merge m = {ctx, base, ours, theirs, in_build_settings, {0}, {0}, 0, 0};
    for (size_t i = 0; i < ours->count && !m.failed; i++) {
        merge_ours_key(&m, &ours->items[i]);
    }
    for (size_t i = 0; i < theirs->count && !m.failed; i++) {
        merge_theirs_key(&m, &theirs->items[i]);
    }
    pbx_merge_status status = PBX_MERGE_OK;
    if (m.failed || m.scratch.failed) {
        status = PBX_MERGE_NO_MEMORY;
    } else if (m.conflicts > 0 && !ours->multiline) {
        status = PBX_MERGE_CONFLICT; /* markers need lines of their own */
    } else {
        render_dict(out, ctx, ours, &m.parts, &m.scratch);
        *conflicts += m.conflicts;
    }
    free(m.parts.items);
    lf_buf_free(&m.scratch);
    return status;
}

/* ---- Arrays ------------------------------------------------------------------------------------ */

#define NO_MATCH SIZE_MAX
/* Duplicate-aware alignment uses an LCS table; bigger middles (after trimming the common prefix
 * and suffix) are not aligned and the list becomes a conflict instead. */
#define LF_MAX_ALIGN_CELLS (4u * 1024u * 1024u)

typedef struct side {
    const pbx_value *value; /* NULL when the side has no such array */
    lf_buf labels;          /* identity of every element: "token\x01<n>" */
    size_t *label_start;
    size_t *label_length;
    size_t *base_match;     /* aligned sides: index of the matching base element, or NO_MATCH */
    lf_span_map index;      /* label -> element index */
    lf_span_map tokens;     /* token -> number of copies */
} side;

typedef struct element {
    const pbx_value *owner;
    const pbx_item *item;
    const uint8_t *label;
    size_t label_length;
    int skeleton_addition; /* added by the side that provides the order */
} element;

static const uint8_t *label_of(const side *s, size_t i, size_t *length) {
    *length = s->label_length[i];
    return s->labels.data + s->label_start[i];
}

static const uint8_t *element_token(const pbx_value *value, size_t i, size_t *length) {
    *length = value->items[i].key_end - value->items[i].key_start;
    return value->data + value->items[i].key_start;
}

static void free_side(side *s) {
    lf_buf_free(&s->labels);
    free(s->label_start);
    free(s->label_length);
    free(s->base_match);
    lf_map_free(&s->index);
    lf_map_free(&s->tokens);
}

static void append_number(lf_buf *buf, size_t number) {
    char digits[24];
    size_t count = 0;
    do {
        digits[count++] = (char)('0' + number % 10);
        number /= 10;
    } while (number > 0);
    while (count > 0) {
        lf_buf_append(buf, &digits[--count], 1);
    }
}

static size_t copies(const side *s, const uint8_t *token, size_t length) {
    size_t count = 0;
    return (s->value != NULL && lf_map_get(&s->tokens, token, length, &count)) ? count : 0;
}

/* Counts the copies of every token. 1: ok (and *duplicates set if any repeats); 0: no memory; -1: nested value. */
static int count_tokens(side *s, int *duplicates) {
    if (s->value == NULL) {
        return 1;
    }
    if (!lf_map_init(&s->tokens, s->value->count)) {
        return 0;
    }
    for (size_t i = 0; i < s->value->count; i++) {
        if (s->value->items[i].value->kind != PBX_STRING) {
            return -1;
        }
        size_t length;
        const uint8_t *token = element_token(s->value, i, &length);
        size_t *count = lf_map_find(&s->tokens, token, length);
        if (count != NULL) {
            ++*count;
            *duplicates = 1;
        } else if (lf_map_put(&s->tokens, token, length, 1) == LF_MAP_NO_MEMORY) {
            return 0;
        }
    }
    return 1;
}

static int tokens_equal(const pbx_value *a, size_t i, const pbx_value *b, size_t j) {
    size_t al, bl;
    const uint8_t *at = element_token(a, i, &al), *bt = element_token(b, j, &bl);
    return bytes_equal(at, al, bt, bl);
}

/* Matches side elements to base elements along a longest common subsequence of tokens, like a diff.
 * 1: ok; 0: no memory; -1: too large to align. */
static int align(const side *base, side *s) {
    const size_t n = base->value->count, m = s->value->count;
    s->base_match = malloc((m + 1) * sizeof *s->base_match);
    if (s->base_match == NULL) {
        return 0;
    }
    for (size_t j = 0; j < m; j++) {
        s->base_match[j] = NO_MATCH;
    }
    size_t prefix = 0, suffix = 0;
    while (prefix < n && prefix < m && tokens_equal(base->value, prefix, s->value, prefix)) {
        s->base_match[prefix] = prefix;
        prefix++;
    }
    while (suffix < n - prefix && suffix < m - prefix &&
           tokens_equal(base->value, n - 1 - suffix, s->value, m - 1 - suffix)) {
        s->base_match[m - 1 - suffix] = n - 1 - suffix;
        suffix++;
    }
    const size_t rows = n - prefix - suffix, cols = m - prefix - suffix;
    if (rows == 0 || cols == 0) {
        return 1;
    }
    if ((rows + 1) > LF_MAX_ALIGN_CELLS / (cols + 1)) {
        return -1;
    }
    const size_t width = cols + 1;
    uint32_t *lcs = calloc((rows + 1) * width, sizeof *lcs); /* lcs[i][j]: LCS of the suffixes from i, j */
    if (lcs == NULL) {
        return 0;
    }
    for (size_t i = rows; i-- > 0;) {
        for (size_t j = cols; j-- > 0;) {
            const uint32_t down = lcs[(i + 1) * width + j], right = lcs[i * width + j + 1];
            lcs[i * width + j] = tokens_equal(base->value, prefix + i, s->value, prefix + j)
                                     ? lcs[(i + 1) * width + j + 1] + 1
                                     : (down >= right ? down : right);
        }
    }
    for (size_t i = 0, j = 0; i < rows && j < cols;) {
        if (tokens_equal(base->value, prefix + i, s->value, prefix + j)) {
            s->base_match[prefix + j] = prefix + i;
            i++, j++;
        } else if (lcs[(i + 1) * width + j] >= lcs[i * width + j + 1]) {
            i++;
        } else {
            j++;
        }
    }
    free(lcs);
    return 1;
}

/* Gives every element its identity label and indexes the side by label. */
static int label_side(side *s, int aligned, int is_base) {
    if (s->value == NULL) {
        return 1;
    }
    const size_t count = s->value->count;
    lf_span_map seen = {0};
    s->label_start = malloc((count + 1) * sizeof *s->label_start);
    s->label_length = malloc((count + 1) * sizeof *s->label_length);
    int ok = s->label_start != NULL && s->label_length != NULL && lf_map_init(&seen, count);
    for (size_t i = 0; ok && i < count; i++) {
        size_t length;
        const uint8_t *token = element_token(s->value, i, &length);
        s->label_start[i] = s->labels.length;
        lf_buf_append(&s->labels, token, length);
        lf_buf_append(&s->labels, "\x01", 1);
        if (aligned && (is_base || s->base_match[i] != NO_MATCH)) {
            append_number(&s->labels, is_base ? i : s->base_match[i]); /* same label as its base element */
        } else {
            size_t *previous = lf_map_find(&seen, token, length); /* nth unmatched copy of this token */
            const size_t occurrence = previous != NULL ? ++*previous : 0;
            ok = previous != NULL || lf_map_put(&seen, token, length, 0) != LF_MAP_NO_MEMORY;
            lf_buf_append(&s->labels, aligned ? "n" : "", aligned ? 1 : 0);
            append_number(&s->labels, occurrence);
        }
        s->label_length[i] = s->labels.length - s->label_start[i];
    }
    lf_map_free(&seen);
    ok = ok && !s->labels.failed && lf_map_init(&s->index, count);
    for (size_t i = 0; ok && i < count; i++) {
        size_t length;
        const uint8_t *label = label_of(s, i, &length);
        ok = lf_map_put(&s->index, label, length, i) == LF_MAP_ADDED;
    }
    return ok;
}

/* 1: ready; 0: no memory; -1: the arrays cannot be merged as ordered sets. */
static int prepare_sides(side *base, side *ours, side *theirs) {
    int duplicates = 0;
    side *sides[3] = {base, ours, theirs};
    for (size_t i = 0; i < 3; i++) {
        const int counted = count_tokens(sides[i], &duplicates);
        if (counted != 1) {
            return counted;
        }
    }
    const int aligned = duplicates;
    if (aligned) {
        if (base->value == NULL) {
            return -1;
        }
        for (size_t i = 1; i < 3; i++) {
            const int result = align(base, sides[i]);
            if (result != 1) {
                return result;
            }
        }
    }
    return label_side(base, aligned, 1) && label_side(ours, aligned, 0) && label_side(theirs, aligned, 0);
}

static const pbx_item *side_item(const side *s, const uint8_t *label, size_t length) {
    size_t index;
    if (s->value == NULL || !lf_map_get(&s->index, label, length, &index)) {
        return NULL;
    }
    return &s->value->items[index];
}

static int in_all(const side *base, const side *ours, const side *theirs, const uint8_t *label, size_t length) {
    return side_item(ours, label, length) && side_item(theirs, label, length) &&
           (base->value == NULL || side_item(base, label, length));
}

/* Next element of `s` at or after *i that all sides share. */
static const uint8_t *next_shared(const side *s, size_t *i, size_t *length, const side *base, const side *ours,
                                  const side *theirs) {
    for (; *i < s->value->count; (*i)++) {
        const uint8_t *label = label_of(s, *i, length);
        if (in_all(base, ours, theirs, label, *length)) {
            return label;
        }
    }
    return NULL;
}

/* Do x and y list the elements that all sides share in the same order? */
static int same_shared_order(const side *x, const side *y, const side *base, const side *ours, const side *theirs) {
    size_t i = 0, j = 0;
    for (;; i++, j++) {
        size_t xl = 0, yl = 0;
        const uint8_t *xt = next_shared(x, &i, &xl, base, ours, theirs);
        const uint8_t *yt = next_shared(y, &j, &yl, base, ours, theirs);
        if (xt == NULL || yt == NULL) {
            return xt == yt;
        }
        if (!bytes_equal(xt, xl, yt, yl)) {
            return 0;
        }
    }
}

typedef struct element_list {
    element *items;
    size_t count;
    lf_span_map present;
} element_list;

static size_t index_in(const element_list *list, const uint8_t *label, size_t length) {
    for (size_t i = 0; i < list->count; i++) {
        if (bytes_equal(list->items[i].label, list->items[i].label_length, label, length)) {
            return i;
        }
    }
    return list->count;
}

static int insert_element(element_list *list, size_t index, const element *e) {
    if (lf_map_put(&list->present, e->label, e->label_length, index) == LF_MAP_NO_MEMORY) {
        return 0;
    }
    memmove(&list->items[index + 1], &list->items[index], (list->count - index) * sizeof *list->items);
    list->items[index] = *e;
    list->count++;
    return 1;
}

/* Is element i of `value` a copy of a token that existed in base but that `opposite` removed completely? */
static int removed_entirely(const pbx_value *value, size_t i, const side *base, const side *opposite) {
    size_t length;
    const uint8_t *token = element_token(value, i, &length);
    return copies(base, token, length) > 0 && copies(opposite, token, length) == 0;
}

/* Builds the merged element list. Returns 0 on allocation failure. */
static int build_elements(element_list *list, const side *skeleton, const side *other, const side *base,
                          const side *ours, const side *theirs) {
    for (size_t i = 0; i < skeleton->value->count; i++) {
        size_t length;
        const uint8_t *label = label_of(skeleton, i, &length);
        const pbx_item *base_item = side_item(base, label, length);
        if (base_item != NULL && side_item(other, label, length) == NULL) {
            continue; /* removed by the other side */
        }
        if (base_item == NULL && removed_entirely(skeleton->value, i, base, other)) {
            continue; /* an extra copy of an element the other side removed */
        }
        element e = {skeleton->value, &skeleton->value->items[i], label, length, base_item == NULL};
        const pbx_item *o = side_item(ours, label, length), *t = side_item(theirs, label, length);
        if (o != NULL && t != NULL) { /* in both: prefer the side that changed its comment */
            const int ours_unchanged = base_item != NULL && item_values_equal(ours->value, o, base->value, base_item);
            e.owner = ours_unchanged ? theirs->value : ours->value;
            e.item = ours_unchanged ? t : o;
        }
        if (!insert_element(list, list->count, &e)) {
            return 0;
        }
    }
    for (size_t k = 0; k < other->value->count; k++) {
        size_t length;
        const uint8_t *label = label_of(other, k, &length);
        if (side_item(base, label, length) != NULL || side_item(skeleton, label, length) != NULL ||
            removed_entirely(other->value, k, base, skeleton)) {
            continue;
        }
        size_t at = 0;
        for (size_t j = k; j-- > 0;) { /* nearest preceding element that made it into the result */
            size_t anchor_length;
            const uint8_t *anchor = label_of(other, j, &anchor_length);
            if (lf_map_get(&list->present, anchor, anchor_length, NULL)) {
                at = index_in(list, anchor, anchor_length) + 1;
                break;
            }
        }
        while (at < list->count && list->items[at].skeleton_addition) {
            at++;
        }
        const element e = {other->value, &other->value->items[k], label, length, 0};
        if (!insert_element(list, at, &e)) {
            return 0;
        }
    }
    return 1;
}

static void render_array(lf_buf *out, const pbx_value *ours, const element_list *list) {
    lf_buf_append(out, ours->multiline ? "(\n" : "(", ours->multiline ? 2 : 1);
    for (size_t i = 0; i < list->count; i++) {
        const pbx_item *item = list->items[i].item;
        lf_buf_append(out, list->items[i].owner->data + item->raw_start, item->raw_end - item->raw_start);
    }
    if (ours->multiline) {
        lf_buf_append(out, ours->data + ours->close_start, ours->end - ours->close_start);
    } else {
        lf_buf_append(out, ")", 1);
    }
}

static pbx_merge_status merge_arrays(const pbx_value *base, const pbx_value *ours, const pbx_value *theirs,
                                     int in_build_settings, lf_buf *out) {
    if (in_build_settings || ours->multiline != theirs->multiline) {
        return PBX_MERGE_CONFLICT;
    }
    side b = {base, {0}, NULL, NULL, NULL, {0}, {0}};
    side o = {ours, {0}, NULL, NULL, NULL, {0}, {0}};
    side t = {theirs, {0}, NULL, NULL, NULL, {0}, {0}};
    element_list list = {0};
    pbx_merge_status status = PBX_MERGE_CONFLICT;
    const int prepared = prepare_sides(&b, &o, &t);
    if (prepared == 0) {
        status = PBX_MERGE_NO_MEMORY;
    } else if (prepared == 1) {
        const int ours_reordered = base != NULL && !same_shared_order(&o, &b, &b, &o, &t);
        const int theirs_reordered = base != NULL && !same_shared_order(&t, &b, &b, &o, &t);
        const int sides_agree = same_shared_order(&o, &t, &b, &o, &t);
        const int conflicting_order = base != NULL ? (ours_reordered && theirs_reordered && !sides_agree) : !sides_agree;
        if (!conflicting_order) {
            const side *skeleton = (theirs_reordered && !ours_reordered) ? &t : &o;
            const side *other = skeleton == &o ? &t : &o;
            list.items = malloc((ours->count + theirs->count + 1) * sizeof *list.items);
            if (list.items == NULL || !lf_map_init(&list.present, ours->count + theirs->count) ||
                !build_elements(&list, skeleton, other, &b, &o, &t)) {
                status = PBX_MERGE_NO_MEMORY;
            } else {
                render_array(out, ours, &list);
                status = PBX_MERGE_OK;
            }
        }
    }
    free(list.items);
    lf_map_free(&list.present);
    free_side(&b);
    free_side(&o);
    free_side(&t);
    return status;
}

/* ---- Entry point ----------------------------------------------------------------------------- */

static pbx_merge_status merge_values(const pbx_merge_ctx *ctx, const pbx_value *base, const pbx_value *ours,
                                     const pbx_value *theirs, int in_build_settings, lf_buf *out, uint64_t *conflicts) {
    if (ours->kind != theirs->kind || (base != NULL && base->kind != ours->kind)) {
        return PBX_MERGE_CONFLICT;
    }
    switch (ours->kind) {
    case PBX_DICT: return merge_dicts(ctx, base, ours, theirs, in_build_settings, out, conflicts);
    case PBX_ARRAY: return merge_arrays(base, ours, theirs, in_build_settings, out);
    default: return PBX_MERGE_CONFLICT; /* two different scalar values */
    }
}

static int same_isa(const pbx_value *ours, const pbx_value *theirs) {
    static const uint8_t isa[] = "isa";
    const pbx_item *o = find_key(ours, isa, 3);
    const pbx_item *t = find_key(theirs, isa, 3);
    return o != NULL && t != NULL && item_values_equal(ours, o, theirs, t);
}

static pbx_value *parse_entry_value(const pbx_file *file, const pbx_entry *entry) {
    pbx_value *value = pbx_value_parse(file->data, file->length, entry->value_start);
    if (value != NULL && (value->kind != PBX_DICT || value->end != entry->value_end)) {
        pbx_value_free(value);
        return NULL;
    }
    return value;
}

pbx_merge_status pbx_merge_entry(const pbx_merge_ctx *ctx, const pbx_file *base_file, const pbx_entry *base,
                                 const pbx_file *ours_file, const pbx_entry *ours, const pbx_file *theirs_file,
                                 const pbx_entry *theirs, lf_buf *out, uint64_t *conflicts) {
    pbx_value *o = parse_entry_value(ours_file, ours);
    pbx_value *t = parse_entry_value(theirs_file, theirs);
    pbx_value *b = base != NULL ? parse_entry_value(base_file, base) : NULL;
    pbx_merge_status status = PBX_MERGE_CONFLICT; /* unknown layout or a changed isa: conflict the whole object */
    if (o != NULL && t != NULL && (base == NULL || b != NULL) && same_isa(o, t)) {
        const size_t mark = out->length;
        uint64_t inner = 0;
        lf_buf_append(out, ours_file->data + ours->raw_start, ours->value_start - ours->raw_start);
        status = merge_values(ctx, b, o, t, 0, out, &inner);
        if (status == PBX_MERGE_OK) {
            lf_buf_append(out, ours_file->data + ours->value_end, ours->raw_end - ours->value_end);
            *conflicts += inner;
        } else {
            lf_buf_truncate(out, mark);
        }
        if (out->failed) {
            status = PBX_MERGE_NO_MEMORY;
        }
    }
    pbx_value_free(o);
    pbx_value_free(t);
    pbx_value_free(b);
    return status;
}
