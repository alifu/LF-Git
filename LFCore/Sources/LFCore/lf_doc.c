#include "lf_internal.h"

#include <stdlib.h>
#include <string.h>

static const uint8_t EMPTY_TEXT[1] = {0};

static char *copy_string(const char *text) {
    const size_t length = strlen(text) + 1;
    char *copy = malloc(length);
    if (copy != NULL) {
        memcpy(copy, text, length);
    }
    return copy;
}

void lf_doc_close(lf_doc *doc) {
    if (doc == NULL) {
        return;
    }
    for (size_t i = 0; i < doc->conflict_count; i++) {
        free(doc->conflicts[i].custom);
    }
    free(doc->conflicts);
    free(doc->line_index);
    free(doc->owned);
    if (doc->map_base != NULL) {
        lf_mapping mapping = {.base = doc->map_base, .length = doc->map_length};
        lf_unmap(&mapping);
    }
    free(doc->path);
    free(doc);
}

/* Points the document at the file's text, transcoding UTF-16 to UTF-8 in memory. */
static lf_status load_text(lf_doc *doc, lf_mapping *mapping, const lf_text_info *kind) {
    doc->encoding = kind->encoding;
    if (kind->encoding == LF_ENCODING_UTF16LE || kind->encoding == LF_ENCODING_UTF16BE) {
        const uint8_t *payload = (const uint8_t *)mapping->base + kind->bom_length;
        size_t decoded_length = 0;
        const lf_status status = lf_utf16_to_utf8(payload, mapping->length - kind->bom_length,
                                                  kind->encoding == LF_ENCODING_UTF16BE, &doc->owned, &decoded_length);
        lf_unmap(mapping);
        if (status != LF_OK) {
            return status;
        }
        doc->data = doc->owned;
        doc->size = decoded_length;
        return LF_OK;
    }
    doc->map_base = mapping->base;
    doc->map_length = mapping->length;
    doc->data = mapping->base != NULL ? (const uint8_t *)mapping->base : EMPTY_TEXT;
    doc->size = mapping->length;
    doc->bom_skip = kind->encoding == LF_ENCODING_UTF8_BOM ? kind->bom_length : 0;
    return LF_OK;
}

lf_status lf_doc_open(const char *path, const lf_open_options *options, lf_doc **out) {
    if (path == NULL || out == NULL) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "lf_doc_open: null argument");
    }
    *out = NULL;
    lf_mapping mapping;
    lf_status status = lf_map_file(path, &mapping);
    if (status != LF_OK) {
        return status;
    }
    const lf_text_info kind = lf_detect_text(mapping.base, mapping.length);
    if (kind.kind == LF_KIND_BINARY) {
        lf_unmap(&mapping);
        return lf_fail(LF_ERR_UNSUPPORTED, "'%s' is a binary file", path);
    }
    lf_doc *doc = calloc(1, sizeof *doc);
    if (doc == NULL) {
        lf_unmap(&mapping);
        return lf_fail(LF_ERR_NO_MEMORY, "out of memory opening '%s'", path);
    }
    doc->mode = mapping.mode;
    doc->source = mapping.info;
    doc->marker_size = (options != NULL && options->marker_size != 0) ? options->marker_size : LF_DEFAULT_MARKER_SIZE;
    doc->path = copy_string(path);
    if (doc->path == NULL) {
        lf_unmap(&mapping);
        free(doc);
        return lf_fail(LF_ERR_NO_MEMORY, "out of memory opening '%s'", path);
    }
    status = load_text(doc, &mapping, &kind);
    if (status == LF_OK) {
        status = lf_doc_scan(doc);
    }
    if (status != LF_OK) {
        lf_doc_close(doc);
        return status;
    }
    *out = doc;
    return LF_OK;
}

lf_status lf_doc_get_info(const lf_doc *doc, lf_doc_info *out) {
    if (doc == NULL || out == NULL) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "lf_doc_get_info: null argument");
    }
    uint64_t unresolved = 0;
    for (size_t i = 0; i < doc->conflict_count; i++) {
        unresolved += doc->conflicts[i].choice == LF_CHOICE_UNRESOLVED;
    }
    out->size = doc->size;
    out->line_count = doc->line_count;
    out->conflict_count = doc->conflict_count;
    out->unresolved_count = unresolved;
    out->encoding = doc->encoding;
    out->eol = doc->eol;
    out->marker_size = doc->marker_size;
    return LF_OK;
}

const uint8_t *lf_doc_data(const lf_doc *doc, uint64_t *length) {
    if (doc == NULL) {
        if (length != NULL) {
            *length = 0;
        }
        return EMPTY_TEXT;
    }
    if (length != NULL) {
        *length = doc->size;
    }
    return doc->data;
}

lf_status lf_doc_line_offset(const lf_doc *doc, uint64_t line, uint64_t *offset) {
    if (doc == NULL || offset == NULL) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "lf_doc_line_offset: null argument");
    }
    if (line == doc->line_count + 1) {
        *offset = doc->size;
        return LF_OK;
    }
    if (line < 1 || line > doc->line_count) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "line %llu is outside 1...%llu", (unsigned long long)line,
                       (unsigned long long)doc->line_count);
    }
    const uint64_t zero_based = line - 1;
    uint64_t position = doc->line_index[zero_based / LF_LINE_INDEX_STRIDE];
    for (uint64_t skip = zero_based % LF_LINE_INDEX_STRIDE; skip > 0; skip--) {
        const uint8_t *newline = memchr(doc->data + position, '\n', (size_t)(doc->size - position));
        position = (uint64_t)(newline - doc->data) + 1;
    }
    *offset = position;
    return LF_OK;
}

static lf_range range_of(uint64_t start, uint64_t end) {
    lf_range range = {start, end - start};
    return range;
}

lf_status lf_doc_get_conflict(const lf_doc *doc, uint64_t index, lf_conflict_info *out) {
    if (doc == NULL || out == NULL) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "lf_doc_get_conflict: null argument");
    }
    if (index >= doc->conflict_count) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "conflict %llu does not exist (%llu in file)",
                       (unsigned long long)index, (unsigned long long)doc->conflict_count);
    }
    const lf_conflict_rec *rec = &doc->conflicts[index];
    memset(out, 0, sizeof *out);
    out->open_line = rec->open_line;
    out->base_line = rec->base_line;
    out->separator_line = rec->sep_line;
    out->close_line = rec->close_line;
    out->region = range_of(rec->marker_start, rec->marker_end);
    out->current = range_of(rec->cur_start, rec->cur_end);
    out->incoming = range_of(rec->inc_start, rec->inc_end);
    if (rec->has_base) {
        out->base = range_of(rec->base_start, rec->base_end);
    }
    out->current_label = rec->cur_label;
    out->incoming_label = rec->inc_label;
    out->choice = (lf_choice)rec->choice;
    out->has_base = rec->has_base;
    out->has_custom = rec->custom != NULL;
    return LF_OK;
}
