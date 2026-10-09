/*
 * lf_scan.c — single pass over the document: counts lines, builds the sparse
 * line index, detects line endings and extracts conflict regions.
 *
 * Marker rules (same as git's conflict style, strict on purpose):
 *   <<<<<<< [label]      opens a conflict; only valid outside a conflict
 *   ||||||| [label]      optional diff3 base; only valid in the current side
 *   =======              separator (nothing may follow it); current/base side only
 *   >>>>>>> [label]      closes a conflict; only valid in the incoming side
 * The run must be exactly marker_size long and start the line. Anything else,
 * including "=======" outside a conflict (a Markdown heading), is plain content.
 */
#include "lf_internal.h"

#include <stdlib.h>
#include <string.h>

typedef enum scan_state {
    STATE_OUTSIDE,
    STATE_CURRENT,
    STATE_BASE,
    STATE_INCOMING,
} scan_state;

typedef struct scan_ctx {
    scan_state state;
    uint64_t line;       /* 1-based number of the line being scanned */
    uint64_t lf_count;   /* lines ended by "\n" */
    uint64_t crlf_count; /* lines ended by "\r\n" */
} scan_ctx;

static const size_t INITIAL_CAPACITY = 64;

/* A marker is `size` copies of `ch`, then end of line or (if allowed) a space and a label. */
static int is_marker(const uint8_t *start, const uint8_t *content_end, uint8_t ch, uint32_t size, int allow_label) {
    const size_t available = (size_t)(content_end - start);
    if (available < size) {
        return 0;
    }
    for (uint32_t i = 0; i < size; i++) {
        if (start[i] != ch) {
            return 0;
        }
    }
    if (available == size) {
        return 1;
    }
    return allow_label && start[size] == ' ';
}

static lf_range label_range(const lf_doc *doc, const uint8_t *start, const uint8_t *content_end) {
    const size_t prefix = doc->marker_size + 1;
    lf_range range = {0, 0};
    if ((size_t)(content_end - start) > prefix) {
        range.offset = (uint64_t)(start + prefix - doc->data);
        range.length = (uint64_t)(content_end - start) - prefix;
    }
    return range;
}

static lf_status push_line_index(lf_doc *doc, uint64_t offset) {
    if (doc->line_index_len == doc->line_index_cap) {
        const size_t capacity = doc->line_index_cap ? doc->line_index_cap * 2 : INITIAL_CAPACITY;
        uint64_t *grown = realloc(doc->line_index, capacity * sizeof *grown);
        if (grown == NULL) {
            return lf_fail(LF_ERR_NO_MEMORY, "out of memory building the line index");
        }
        doc->line_index = grown;
        doc->line_index_cap = capacity;
    }
    doc->line_index[doc->line_index_len++] = offset;
    return LF_OK;
}

static lf_conflict_rec *push_conflict(lf_doc *doc) {
    if (doc->conflict_count == doc->conflict_cap) {
        const size_t capacity = doc->conflict_cap ? doc->conflict_cap * 2 : INITIAL_CAPACITY;
        lf_conflict_rec *grown = realloc(doc->conflicts, capacity * sizeof *grown);
        if (grown == NULL) {
            return NULL;
        }
        doc->conflicts = grown;
        doc->conflict_cap = capacity;
    }
    lf_conflict_rec *rec = &doc->conflicts[doc->conflict_count++];
    memset(rec, 0, sizeof *rec);
    return rec;
}

static unsigned long long as_ull(uint64_t value) {
    return (unsigned long long)value;
}

/* Handles a line that starts with a marker character. */
static lf_status handle_marker(lf_doc *doc, scan_ctx *ctx, const uint8_t *content, const uint8_t *content_end,
                               uint64_t next_offset) {
    const uint32_t size = doc->marker_size;
    const uint64_t line_start = (uint64_t)(content - doc->data);
    lf_conflict_rec *rec = doc->conflict_count ? &doc->conflicts[doc->conflict_count - 1] : NULL;

    switch (*content) {
    case '<':
        if (!is_marker(content, content_end, '<', size, 1)) {
            return LF_OK;
        }
        if (ctx->state != STATE_OUTSIDE) {
            return lf_fail(LF_ERR_MALFORMED, "line %llu: conflict start inside the conflict opened at line %llu",
                           as_ull(ctx->line), as_ull(rec->open_line));
        }
        rec = push_conflict(doc);
        if (rec == NULL) {
            return lf_fail(LF_ERR_NO_MEMORY, "out of memory recording conflicts");
        }
        rec->marker_start = line_start;
        rec->cur_start = next_offset;
        rec->open_line = ctx->line;
        rec->cur_label = label_range(doc, content, content_end);
        ctx->state = STATE_CURRENT;
        break;
    case '|':
        if (ctx->state == STATE_CURRENT && is_marker(content, content_end, '|', size, 1)) {
            rec->cur_end = line_start;
            rec->base_start = next_offset;
            rec->base_line = ctx->line;
            rec->has_base = 1;
            ctx->state = STATE_BASE;
        }
        break;
    case '=':
        if ((ctx->state == STATE_CURRENT || ctx->state == STATE_BASE) &&
            is_marker(content, content_end, '=', size, 0)) {
            if (ctx->state == STATE_CURRENT) {
                rec->cur_end = line_start;
            } else {
                rec->base_end = line_start;
            }
            rec->inc_start = next_offset;
            rec->sep_line = ctx->line;
            ctx->state = STATE_INCOMING;
        }
        break;
    case '>':
        if (ctx->state == STATE_OUTSIDE || !is_marker(content, content_end, '>', size, 1)) {
            return LF_OK;
        }
        if (ctx->state != STATE_INCOMING) {
            return lf_fail(LF_ERR_MALFORMED, "line %llu: closing marker before '=======' (conflict opened at line %llu)",
                           as_ull(ctx->line), as_ull(rec->open_line));
        }
        rec->inc_end = line_start;
        rec->marker_end = next_offset;
        rec->close_line = ctx->line;
        rec->inc_label = label_range(doc, content, content_end);
        ctx->state = STATE_OUTSIDE;
        break;
    default:
        break;
    }
    return LF_OK;
}

static lf_eol classify_eol(const scan_ctx *ctx) {
    if (ctx->lf_count == 0 && ctx->crlf_count == 0) {
        return LF_EOL_NONE;
    }
    if (ctx->crlf_count == 0) {
        return LF_EOL_LF;
    }
    return ctx->lf_count == 0 ? LF_EOL_CRLF : LF_EOL_MIXED;
}

lf_status lf_doc_scan(lf_doc *doc) {
    scan_ctx ctx = {STATE_OUTSIDE, 1, 0, 0};
    const uint8_t *const base = doc->data;
    const uint8_t *const end = base + doc->size;
    const uint8_t *p = base;

    while (p < end) {
        const uint8_t *newline = memchr(p, '\n', (size_t)(end - p));
        const uint8_t *line_end = newline ? newline : end;
        const uint8_t *next = newline ? newline + 1 : end;

        if (((ctx.line - 1) & (LF_LINE_INDEX_STRIDE - 1)) == 0) {
            const lf_status status = push_line_index(doc, (uint64_t)(p - base));
            if (status != LF_OK) {
                return status;
            }
        }
        if (newline != NULL) {
            if (newline > p && newline[-1] == '\r') {
                ctx.crlf_count++;
            } else {
                ctx.lf_count++;
            }
        }

        const uint8_t *content = ctx.line == 1 ? p + doc->bom_skip : p;
        if (content < line_end) {
            const uint8_t first = *content;
            if (first == '<' || first == '|' || first == '=' || first == '>') {
                const uint8_t *content_end = line_end[-1] == '\r' ? line_end - 1 : line_end;
                const lf_status status = handle_marker(doc, &ctx, content, content_end, (uint64_t)(next - base));
                if (status != LF_OK) {
                    return status;
                }
            }
        }
        ctx.line++;
        p = next;
    }

    if (ctx.state != STATE_OUTSIDE) {
        return lf_fail(LF_ERR_MALFORMED, "unterminated conflict starting at line %llu",
                       as_ull(doc->conflicts[doc->conflict_count - 1].open_line));
    }
    doc->line_count = ctx.line - 1;
    doc->eol = classify_eol(&ctx);
    return LF_OK;
}
