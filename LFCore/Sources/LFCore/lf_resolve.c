#include "lf_internal.h"

#include <stdlib.h>
#include <string.h>

static lf_status validate_choice(const lf_conflict_rec *rec, uint64_t index, lf_choice choice) {
    if (choice == LF_CHOICE_CUSTOM && rec->custom == NULL) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "conflict %llu has no custom text; use lf_doc_set_custom",
                       (unsigned long long)index);
    }
    if (choice == LF_CHOICE_BASE && !rec->has_base) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT,
                       "conflict %llu (line %llu) has no base section; enable merge.conflictStyle=diff3",
                       (unsigned long long)index, (unsigned long long)rec->open_line);
    }
    if ((unsigned)choice > (unsigned)LF_CHOICE_CUSTOM) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "unknown choice %d", (int)choice);
    }
    return LF_OK;
}

lf_status lf_doc_set_choice(lf_doc *doc, uint64_t index, lf_choice choice) {
    if (doc == NULL) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "lf_doc_set_choice: null document");
    }
    if (index >= doc->conflict_count) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "conflict %llu does not exist (%llu in file)",
                       (unsigned long long)index, (unsigned long long)doc->conflict_count);
    }
    lf_conflict_rec *rec = &doc->conflicts[index];
    const lf_status status = validate_choice(rec, index, choice);
    if (status != LF_OK) {
        return status;
    }
    rec->choice = (uint8_t)choice;
    return LF_OK;
}

lf_status lf_doc_set_choice_all(lf_doc *doc, lf_choice choice) {
    if (doc == NULL) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "lf_doc_set_choice_all: null document");
    }
    /* Validate everything first so a failure changes nothing. */
    for (size_t i = 0; i < doc->conflict_count; i++) {
        const lf_status status = validate_choice(&doc->conflicts[i], i, choice);
        if (status != LF_OK) {
            return status;
        }
    }
    for (size_t i = 0; i < doc->conflict_count; i++) {
        doc->conflicts[i].choice = (uint8_t)choice;
    }
    return LF_OK;
}

lf_status lf_doc_set_custom(lf_doc *doc, uint64_t index, const uint8_t *data, size_t length) {
    if (doc == NULL || (data == NULL && length > 0)) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "lf_doc_set_custom: invalid argument");
    }
    if (index >= doc->conflict_count) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "conflict %llu does not exist (%llu in file)",
                       (unsigned long long)index, (unsigned long long)doc->conflict_count);
    }
    uint8_t *copy = malloc(length > 0 ? length : 1);
    if (copy == NULL) {
        return lf_fail(LF_ERR_NO_MEMORY, "out of memory storing custom text");
    }
    if (length > 0) {
        memcpy(copy, data, length);
    }
    lf_conflict_rec *rec = &doc->conflicts[index];
    free(rec->custom);
    rec->custom = copy;
    rec->custom_len = length;
    rec->choice = LF_CHOICE_CUSTOM;
    return LF_OK;
}
