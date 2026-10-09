/*
 * lf_pbx_merge.c — three-way merge of whole project.pbxproj files.
 *
 * 1. Parse base, ours and theirs (strictly; otherwise unsupported -> caller uses a text merge).
 * 2. Match objects by ID and decide each one: unchanged, one side's version, a field-by-field
 *    merge, dropped, or a conflict.
 * 3. Safety: an object dropped by one side but still referenced by the merged text becomes a
 *    conflict (keep / delete), so the merge never creates a dangling reference. Objects needed
 *    only by one side of a conflict block are simply kept, so either pick stays valid. A
 *    reference that the deleting side already had while the object was missing (a project that
 *    was broken before the merge) is left as it was.
 * 4. Re-assemble: ours' section and object order, new objects inserted at their sorted position,
 *    exactly as Xcode would write them.
 */
#include "lf_pbx.h"

#include <stdlib.h>
#include <string.h>

typedef enum decision_kind {
    DECISION_DROP,
    DECISION_OURS,
    DECISION_THEIRS,
    DECISION_MERGED,
    DECISION_CONFLICT,
    DECISION_KEPT, /* dropped by one side, but kept because a conflict side refers to it */
} decision_kind;

typedef struct decision {
    decision_kind kind;
    const pbx_entry *base, *ours, *theirs;
    size_t merged_start, merged_end; /* DECISION_MERGED: text in the scratch buffer */
    uint64_t conflicts;              /* DECISION_MERGED: conflict blocks inside the object */
    size_t section;                  /* index in the output section list */
    int queued;                      /* already scanned (or waiting) for references */
    int dangling;                    /* dropped by both sides yet referenced */
    int dangling_in_ours;            /* ours refers to it although ours has no such object */
    int dangling_in_theirs;
    int placed;
} decision;

typedef enum text_choice {
    TAKE_OURS,
    TAKE_THEIRS,
    TAKE_CONFLICT,
} text_choice;

typedef struct out_section {
    const uint8_t *name;
    size_t length;
} out_section;

typedef struct merge_job {
    pbx_merge_ctx ctx;
    pbx_file base, ours, theirs;
    lf_span_map ids;
    decision *decisions;
    size_t count;
    size_t *ours_decision; /* ours entry index -> decision index */
    lf_buf scratch;
    size_t max_id_length;
    text_choice prefix, suffix;
    out_section *sections;
    size_t section_count;
    uint64_t conflicts;
    uint64_t merged_objects;
} merge_job;

static lf_status no_memory(void) {
    return lf_fail(LF_ERR_NO_MEMORY, "out of memory merging the project file");
}

static int bytes_equal(const uint8_t *a, size_t a_length, const uint8_t *b, size_t b_length) {
    return a_length == b_length && memcmp(a, b, a_length) == 0;
}

static int entries_equal(const pbx_file *a_file, const pbx_entry *a, const pbx_file *b_file, const pbx_entry *b) {
    if (a == NULL || b == NULL) {
        return a == b;
    }
    return bytes_equal(a_file->data + a->raw_start, a->raw_end - a->raw_start, b_file->data + b->raw_start,
                       b->raw_end - b->raw_start);
}

/* ---- 1. Match objects by ID ------------------------------------------------------------------- */

typedef enum which_side { SIDE_BASE, SIDE_OURS, SIDE_THEIRS } which_side;

static lf_status add_side(merge_job *job, const pbx_file *file, which_side which) {
    for (size_t i = 0; i < file->entry_count; i++) {
        const pbx_entry *entry = &file->entries[i];
        const size_t length = entry->id_end - entry->id_start;
        size_t index = job->count;
        const int put = lf_map_put(&job->ids, file->data + entry->id_start, length, index);
        if (put == LF_MAP_NO_MEMORY) {
            return no_memory();
        }
        if (put == LF_MAP_EXISTS) {
            lf_map_get(&job->ids, file->data + entry->id_start, length, &index);
        } else {
            job->count++;
        }
        decision *d = &job->decisions[index];
        if (which == SIDE_OURS) {
            d->ours = entry;
            job->ours_decision[i] = index;
        } else {
            *(which == SIDE_BASE ? &d->base : &d->theirs) = entry;
        }
        if (length > job->max_id_length) {
            job->max_id_length = length;
        }
    }
    return LF_OK;
}

/* ---- 2. Decide each object ---------------------------------------------------------------------- */

static lf_status decide(merge_job *job, decision *d) {
    if (entries_equal(&job->ours, d->ours, &job->theirs, d->theirs)) {
        d->kind = d->ours ? DECISION_OURS : DECISION_DROP;
    } else if (entries_equal(&job->ours, d->ours, &job->base, d->base)) {
        d->kind = d->theirs ? DECISION_THEIRS : DECISION_DROP;
    } else if (entries_equal(&job->theirs, d->theirs, &job->base, d->base)) {
        d->kind = d->ours ? DECISION_OURS : DECISION_DROP;
    } else if (d->ours == NULL || d->theirs == NULL) {
        d->kind = DECISION_CONFLICT; /* deleted on one side, changed on the other */
    } else {
        const size_t mark = job->scratch.length;
        uint64_t inner = 0;
        switch (pbx_merge_entry(&job->ctx, &job->base, d->base, &job->ours, d->ours, &job->theirs, d->theirs,
                                &job->scratch, &inner)) {
        case PBX_MERGE_OK:
            d->kind = DECISION_MERGED;
            d->merged_start = mark;
            d->merged_end = job->scratch.length;
            d->conflicts = inner;
            job->merged_objects += inner == 0;
            break;
        case PBX_MERGE_CONFLICT:
            d->kind = DECISION_CONFLICT;
            break;
        case PBX_MERGE_NO_MEMORY:
            return no_memory();
        }
    }
    return LF_OK;
}

static text_choice choose_text(const pbx_file *base, size_t base_start, size_t base_end, const pbx_file *ours,
                               size_t ours_start, size_t ours_end, const pbx_file *theirs, size_t theirs_start,
                               size_t theirs_end) {
    const uint8_t *b = base->data + base_start, *o = ours->data + ours_start, *t = theirs->data + theirs_start;
    const size_t bl = base_end - base_start, ol = ours_end - ours_start, tl = theirs_end - theirs_start;
    if (bytes_equal(o, ol, t, tl) || bytes_equal(t, tl, b, bl)) {
        return TAKE_OURS;
    }
    return bytes_equal(o, ol, b, bl) ? TAKE_THEIRS : TAKE_CONFLICT;
}

/* ---- 3. References: nothing in the result may point at a dropped object ---------------------------- */

typedef struct ref_scan {
    merge_job *job;
    size_t *queue;
    size_t queue_length;
} ref_scan;

static void enqueue(ref_scan *scan, size_t index) {
    decision *d = &scan->job->decisions[index];
    if (!d->queued) {
        d->queued = 1;
        scan->queue[scan->queue_length++] = index;
    }
}

/* `clean`: the reference comes from merged text, not from one side of a conflict block. */
static void reference_found(ref_scan *scan, size_t index, int clean) {
    decision *d = &scan->job->decisions[index];
    if (d->kind == DECISION_KEPT && clean) {
        d->kind = DECISION_CONFLICT; /* now the merged text itself needs it: keep-or-delete is the user's call */
        return;
    }
    if (d->kind != DECISION_DROP) {
        return;
    }
    if (d->ours == NULL && d->theirs == NULL) {
        d->dangling = 1; /* deleted by both sides; checked against the inputs later */
        return;
    }
    /* The deleting side already referred to it while it was missing: follow that side, as git would. */
    if ((d->ours == NULL && d->dangling_in_ours) || (d->theirs == NULL && d->dangling_in_theirs)) {
        return;
    }
    d->kind = clean ? DECISION_CONFLICT : DECISION_KEPT;
    enqueue(scan, index);
}

/* Every bare token that names an object counts as a reference. `skip_first` skips an entry's own ID. */
static void scan_text(ref_scan *scan, const uint8_t *data, size_t start, size_t end, int skip_first, int clean) {
    pbx_lexer lexer = {data, end, start};
    for (;;) {
        const pbx_tok tok = pbx_lex(&lexer);
        if (tok.kind == PBX_TOK_END || tok.kind == PBX_TOK_ERROR) {
            return;
        }
        if (tok.kind != PBX_TOK_STRING) {
            continue;
        }
        if (skip_first) {
            skip_first = 0;
            continue;
        }
        size_t index;
        const size_t length = tok.end - tok.start;
        if (length <= scan->job->max_id_length && lf_map_get(&scan->job->ids, data + tok.start, length, &index)) {
            reference_found(scan, index, clean);
        }
    }
}

static void scan_entry(ref_scan *scan, const pbx_file *file, const pbx_entry *entry, int clean) {
    if (entry != NULL) {
        scan_text(scan, file->data, entry->raw_start, entry->raw_end, 1, clean);
    }
}

static void scan_decision(ref_scan *scan, const decision *d) {
    merge_job *job = scan->job;
    switch (d->kind) {
    case DECISION_OURS: scan_entry(scan, &job->ours, d->ours, 1); break;
    case DECISION_THEIRS: scan_entry(scan, &job->theirs, d->theirs, 1); break;
    case DECISION_MERGED: scan_text(scan, job->scratch.data, d->merged_start, d->merged_end, 1, 1); break;
    case DECISION_CONFLICT:
    case DECISION_KEPT:
        scan_entry(scan, &job->ours, d->ours, 0);
        scan_entry(scan, &job->theirs, d->theirs, 0);
        break;
    case DECISION_DROP: break;
    }
}

static void scan_choice(ref_scan *scan, text_choice choice, size_t ours_start, size_t ours_end, size_t theirs_start,
                        size_t theirs_end) {
    const int clean = choice != TAKE_CONFLICT;
    if (choice != TAKE_THEIRS) {
        scan_text(scan, scan->job->ours.data, ours_start, ours_end, 0, clean);
    }
    if (choice != TAKE_OURS) {
        scan_text(scan, scan->job->theirs.data, theirs_start, theirs_end, 0, clean);
    }
}

/* Flags objects that a side refers to without defining them (projects broken before the merge). */
static void mark_input_danglings(merge_job *job, const pbx_file *file, which_side which) {
    for (size_t i = 0; i < file->entry_count; i++) {
        pbx_lexer lexer = {file->data, file->entries[i].raw_end, file->entries[i].raw_start};
        int first = 1; /* the entry's own ID is a definition, not a reference */
        for (pbx_tok tok = pbx_lex(&lexer); tok.kind != PBX_TOK_END && tok.kind != PBX_TOK_ERROR; tok = pbx_lex(&lexer)) {
            if (tok.kind != PBX_TOK_STRING) {
                continue;
            }
            if (first) {
                first = 0;
                continue;
            }
            size_t index;
            const size_t length = tok.end - tok.start;
            if (length > job->max_id_length || !lf_map_get(&job->ids, file->data + tok.start, length, &index)) {
                continue;
            }
            decision *d = &job->decisions[index];
            if (which == SIDE_OURS && d->ours == NULL) {
                d->dangling_in_ours = 1;
            } else if (which == SIDE_THEIRS && d->theirs == NULL) {
                d->dangling_in_theirs = 1;
            }
        }
    }
}

static lf_status resolve_references(merge_job *job) {
    mark_input_danglings(job, &job->ours, SIDE_OURS);
    mark_input_danglings(job, &job->theirs, SIDE_THEIRS);
    ref_scan scan = {job, malloc((job->count + 1) * sizeof(size_t)), 0};
    if (scan.queue == NULL) {
        return no_memory();
    }
    for (size_t i = 0; i < job->count; i++) {
        if (job->decisions[i].kind != DECISION_DROP) {
            enqueue(&scan, i);
        }
    }
    scan_choice(&scan, job->prefix, 0, job->ours.prefix_end, 0, job->theirs.prefix_end);
    scan_choice(&scan, job->suffix, job->ours.suffix_start, job->ours.length, job->theirs.suffix_start,
                job->theirs.length);
    while (scan.queue_length > 0) {
        scan_decision(&scan, &job->decisions[scan.queue[--scan.queue_length]]);
    }
    free(scan.queue);
    for (size_t i = 0; i < job->count; i++) {
        const decision *d = &job->decisions[i];
        if (d->dangling && !d->dangling_in_ours && !d->dangling_in_theirs) {
            return lf_fail(LF_ERR_UNSUPPORTED, "the merged project would reference objects that both sides deleted");
        }
    }
    return LF_OK;
}

/* ---- 4. Assemble ------------------------------------------------------------------------------- */

static const pbx_file *home_file(const merge_job *job, const decision *d, const pbx_entry **entry) {
    const int use_ours = d->kind == DECISION_OURS || d->kind == DECISION_MERGED ||
                         ((d->kind == DECISION_CONFLICT || d->kind == DECISION_KEPT) && d->ours != NULL);
    *entry = use_ours ? d->ours : d->theirs;
    return use_ours ? &job->ours : &job->theirs;
}

static out_section section_name(const pbx_file *file, const pbx_entry *entry) {
    const pbx_section *section = &file->sections[entry->section];
    out_section name = {file->data + section->name_start, section->name_end - section->name_start};
    return name;
}

static size_t find_section(const merge_job *job, out_section name) {
    for (size_t i = 0; i < job->section_count; i++) {
        if (bytes_equal(job->sections[i].name, job->sections[i].length, name.name, name.length)) {
            return i;
        }
    }
    return job->section_count;
}

static int name_compare(out_section a, out_section b) {
    const size_t shorter = a.length < b.length ? a.length : b.length;
    const int order = memcmp(a.name, b.name, shorter);
    return order != 0 ? order : (a.length > b.length) - (a.length < b.length);
}

static lf_status plan_sections(merge_job *job) {
    job->sections = malloc((job->ours.section_count + job->theirs.section_count + 1) * sizeof *job->sections);
    if (job->sections == NULL) {
        return no_memory();
    }
    for (size_t i = 0; i < job->ours.section_count; i++) {
        const pbx_section *s = &job->ours.sections[i];
        job->sections[job->section_count++] = (out_section){job->ours.data + s->name_start, s->name_end - s->name_start};
    }
    for (size_t i = 0; i < job->count; i++) { /* sections only theirs has, at their sorted position */
        const decision *d = &job->decisions[i];
        if (d->kind == DECISION_DROP) {
            continue;
        }
        const pbx_entry *entry;
        const out_section name = section_name(home_file(job, d, &entry), entry);
        if (find_section(job, name) < job->section_count) {
            continue;
        }
        size_t at = 0;
        while (at < job->section_count && name_compare(job->sections[at], name) < 0) {
            at++;
        }
        memmove(&job->sections[at + 1], &job->sections[at], (job->section_count - at) * sizeof *job->sections);
        job->sections[at] = name;
        job->section_count++;
    }
    for (size_t i = 0; i < job->count; i++) {
        decision *d = &job->decisions[i];
        if (d->kind != DECISION_DROP) {
            const pbx_entry *entry;
            d->section = find_section(job, section_name(home_file(job, d, &entry), entry));
        }
    }
    return LF_OK;
}

static void entry_text(const pbx_file *file, const pbx_entry *entry, const uint8_t **text, size_t *length) {
    *text = entry ? file->data + entry->raw_start : NULL;
    *length = entry ? entry->raw_end - entry->raw_start : 0;
}

static void emit_decision(merge_job *job, const decision *d, lf_buf *out) {
    const uint8_t *o, *b, *t;
    size_t ol, bl, tl;
    switch (d->kind) {
    case DECISION_OURS:
        entry_text(&job->ours, d->ours, &o, &ol);
        lf_buf_append(out, o, ol);
        break;
    case DECISION_THEIRS:
        entry_text(&job->theirs, d->theirs, &t, &tl);
        lf_buf_append(out, t, tl);
        break;
    case DECISION_MERGED:
        lf_buf_append(out, job->scratch.data + d->merged_start, d->merged_end - d->merged_start);
        job->conflicts += d->conflicts;
        break;
    case DECISION_CONFLICT:
        entry_text(&job->ours, d->ours, &o, &ol);
        entry_text(&job->base, d->base, &b, &bl);
        entry_text(&job->theirs, d->theirs, &t, &tl);
        pbx_write_conflict(out, &job->ctx, o, ol, b, bl, t, tl);
        job->conflicts++;
        break;
    case DECISION_KEPT:
        if (d->ours != NULL) {
            entry_text(&job->ours, d->ours, &o, &ol);
            lf_buf_append(out, o, ol);
        } else {
            entry_text(&job->theirs, d->theirs, &t, &tl);
            lf_buf_append(out, t, tl);
        }
        break;
    case DECISION_DROP:
        break;
    }
}

static const uint8_t *decision_id(const merge_job *job, const decision *d, size_t *length) {
    const pbx_entry *entry;
    const pbx_file *file = home_file(job, d, &entry);
    *length = entry->id_end - entry->id_start;
    return file->data + entry->id_start;
}

static void open_section(const merge_job *job, size_t section, int *opened, lf_buf *out) {
    if (*opened) {
        return;
    }
    *opened = 1;
    lf_buf_append_cstr(out, "\n/* Begin ");
    lf_buf_append(out, job->sections[section].name, job->sections[section].length);
    lf_buf_append_cstr(out, " section */\n");
}

typedef struct sorted_id {
    const uint8_t *id;
    size_t length;
    size_t index;
} sorted_id;

static int compare_ids(const void *a, const void *b) {
    const sorted_id *x = a, *y = b;
    return name_compare((out_section){x->id, x->length}, (out_section){y->id, y->length});
}

/* Objects of one section: ours' order, with objects new to it merged in at their sorted position. */
static lf_status emit_section(merge_job *job, size_t section, sorted_id *added, lf_buf *out) {
    size_t added_count = 0;
    for (size_t i = 0; i < job->count; i++) {
        const decision *d = &job->decisions[i];
        if (d->kind == DECISION_DROP || d->section != section || d->placed) {
            continue;
        }
        added[added_count].id = decision_id(job, d, &added[added_count].length);
        added[added_count++].index = i;
    }
    qsort(added, added_count, sizeof *added, compare_ids);
    size_t next = 0;
    int opened = 0;
    for (size_t i = 0; i < job->ours.entry_count; i++) {
        const size_t index = job->ours_decision[i];
        const decision *d = &job->decisions[index];
        if (!d->placed || d->section != section) {
            continue;
        }
        size_t own_length;
        const uint8_t *own = decision_id(job, d, &own_length);
        while (next < added_count && name_compare((out_section){added[next].id, added[next].length},
                                                  (out_section){own, own_length}) < 0) {
            open_section(job, section, &opened, out);
            emit_decision(job, &job->decisions[added[next++].index], out);
        }
        open_section(job, section, &opened, out);
        emit_decision(job, d, out);
    }
    while (next < added_count) {
        open_section(job, section, &opened, out);
        emit_decision(job, &job->decisions[added[next++].index], out);
    }
    if (opened) {
        lf_buf_append_cstr(out, "/* End ");
        lf_buf_append(out, job->sections[section].name, job->sections[section].length);
        lf_buf_append_cstr(out, " section */\n");
    }
    return out->failed ? no_memory() : LF_OK;
}

static void emit_choice(merge_job *job, text_choice choice, size_t base_start, size_t base_end, size_t ours_start,
                        size_t ours_end, size_t theirs_start, size_t theirs_end, lf_buf *out) {
    const uint8_t *o = job->ours.data + ours_start, *t = job->theirs.data + theirs_start;
    if (choice == TAKE_OURS) {
        lf_buf_append(out, o, ours_end - ours_start);
    } else if (choice == TAKE_THEIRS) {
        lf_buf_append(out, t, theirs_end - theirs_start);
    } else {
        pbx_write_conflict(out, &job->ctx, o, ours_end - ours_start, job->base.data + base_start, base_end - base_start,
                           t, theirs_end - theirs_start);
        job->conflicts++;
    }
}

static lf_status assemble(merge_job *job, lf_buf *out) {
    lf_status status = plan_sections(job);
    if (status != LF_OK) {
        return status;
    }
    /* Mark ours' objects that stay in ours' section: they keep ours' order. */
    for (size_t i = 0; i < job->ours.entry_count; i++) {
        decision *d = &job->decisions[job->ours_decision[i]];
        if (d->kind != DECISION_DROP &&
            name_compare(job->sections[d->section], section_name(&job->ours, &job->ours.entries[i])) == 0) {
            d->placed = 1;
        }
    }
    sorted_id *added = malloc((job->count + 1) * sizeof *added);
    if (added == NULL) {
        return no_memory();
    }
    emit_choice(job, job->prefix, 0, job->base.prefix_end, 0, job->ours.prefix_end, 0, job->theirs.prefix_end, out);
    for (size_t s = 0; s < job->section_count && status == LF_OK; s++) {
        status = emit_section(job, s, added, out);
    }
    free(added);
    emit_choice(job, job->suffix, job->base.suffix_start, job->base.length, job->ours.suffix_start, job->ours.length,
                job->theirs.suffix_start, job->theirs.length, out);
    return status == LF_OK && out->failed ? no_memory() : status;
}

/* ---- Public entry point ------------------------------------------------------------------------- */

static void free_job(merge_job *job) {
    pbx_file_free(&job->base);
    pbx_file_free(&job->ours);
    pbx_file_free(&job->theirs);
    lf_map_free(&job->ids);
    free(job->decisions);
    free(job->ours_decision);
    free(job->sections);
    lf_buf_free(&job->scratch);
}

static lf_status prepare(merge_job *job, const uint8_t *base, size_t base_length, const uint8_t *ours,
                         size_t ours_length, const uint8_t *theirs, size_t theirs_length) {
    lf_status status = pbx_file_parse(base, base_length, "base", &job->base);
    if (status == LF_OK) {
        status = pbx_file_parse(ours, ours_length, "ours", &job->ours);
    }
    if (status == LF_OK) {
        status = pbx_file_parse(theirs, theirs_length, "theirs", &job->theirs);
    }
    if (status != LF_OK) {
        return status;
    }
    const size_t total = job->base.entry_count + job->ours.entry_count + job->theirs.entry_count;
    job->decisions = calloc(total + 1, sizeof *job->decisions);
    job->ours_decision = calloc(job->ours.entry_count + 1, sizeof *job->ours_decision);
    if (job->decisions == NULL || job->ours_decision == NULL || !lf_map_init(&job->ids, total)) {
        return no_memory();
    }
    status = add_side(job, &job->ours, SIDE_OURS);
    if (status == LF_OK) {
        status = add_side(job, &job->theirs, SIDE_THEIRS);
    }
    return status == LF_OK ? add_side(job, &job->base, SIDE_BASE) : status;
}

lf_status lf_pbx_merge(const uint8_t *base, size_t base_length, const uint8_t *ours, size_t ours_length,
                       const uint8_t *theirs, size_t theirs_length, const lf_merge_options *options,
                       lf_merge_result *out) {
    if (out == NULL) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "lf_pbx_merge: null result");
    }
    memset(out, 0, sizeof *out);
    merge_job job;
    memset(&job, 0, sizeof job);
    job.ctx.marker_size = (options != NULL && options->marker_size != 0) ? options->marker_size : LF_DEFAULT_MARKER_SIZE;
    job.ctx.include_base = options != NULL ? options->include_base : 1;
    job.ctx.current_label = (options != NULL && options->current_label != NULL) ? options->current_label : "HEAD";
    job.ctx.base_label = (options != NULL && options->base_label != NULL) ? options->base_label : "base";
    job.ctx.incoming_label = (options != NULL && options->incoming_label != NULL) ? options->incoming_label : "incoming";

    lf_status status = prepare(&job, base, base_length, ours, ours_length, theirs, theirs_length);
    for (size_t i = 0; i < job.count && status == LF_OK; i++) {
        status = decide(&job, &job.decisions[i]);
    }
    lf_buf result = {0};
    if (status == LF_OK) {
        job.prefix = choose_text(&job.base, 0, job.base.prefix_end, &job.ours, 0, job.ours.prefix_end, &job.theirs, 0,
                                 job.theirs.prefix_end);
        job.suffix = choose_text(&job.base, job.base.suffix_start, job.base.length, &job.ours, job.ours.suffix_start,
                                 job.ours.length, &job.theirs, job.theirs.suffix_start, job.theirs.length);
        status = resolve_references(&job);
    }
    if (status == LF_OK) {
        status = assemble(&job, &result);
    }
    if (status == LF_OK) {
        out->data = result.data;
        out->length = result.length;
        out->conflict_count = job.conflicts;
        out->merged_object_count = job.merged_objects;
    } else {
        lf_buf_free(&result);
    }
    free_job(&job);
    return status;
}

void lf_merge_result_free(lf_merge_result *result) {
    if (result == NULL) {
        return;
    }
    free(result->data);
    result->data = NULL;
    result->length = 0;
}
