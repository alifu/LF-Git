/* lf_internal.h — private declarations shared by the engine's C files. */
#ifndef LF_INTERNAL_H
#define LF_INTERNAL_H

#include "lfcore.h"

#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>

/* One line offset is stored per this many lines; must be a power of two. */
#define LF_LINE_INDEX_STRIDE 1024u
#define LF_BINARY_SNIFF_BYTES 8000u
#define LF_UTF8_BOM_LENGTH 3u
#define LF_UTF16_BOM_LENGTH 2u

typedef struct lf_conflict_rec {
    uint64_t marker_start; /* start of the "<<<<<<<" line */
    uint64_t marker_end;   /* just past the ">>>>>>>" line, including its terminator */
    uint64_t cur_start, cur_end;
    uint64_t base_start, base_end;
    uint64_t inc_start, inc_end;
    uint64_t open_line, base_line, sep_line, close_line;
    lf_range cur_label, inc_label;
    uint8_t *custom;
    size_t custom_len;
    uint8_t choice;
    uint8_t has_base;
} lf_conflict_rec;

struct lf_doc {
    char *path;
    const uint8_t *data; /* active text: the mapping, or `owned` for transcoded files */
    uint64_t size;
    void *map_base;
    size_t map_length;
    uint8_t *owned;
    uint32_t mode; /* permission bits of the source file */
    struct stat source; /* identity of the source file when it was opened */
    uint32_t marker_size;
    uint32_t bom_skip; /* bytes at the start of `data` that are not part of line 1's content */
    lf_encoding encoding;
    lf_eol eol;
    uint64_t line_count;
    uint64_t *line_index;
    size_t line_index_len, line_index_cap;
    lf_conflict_rec *conflicts;
    size_t conflict_count, conflict_cap;
};

typedef struct lf_mapping {
    void *base; /* NULL for empty files */
    size_t length;
    uint32_t mode;
    struct stat info;
} lf_mapping;

/* lf_error.c */
lf_status lf_fail(lf_status status, const char *format, ...) __attribute__((format(printf, 2, 3)));
lf_status lf_fail_errno(lf_status status, const char *action, const char *path);

/* lf_mmap.c */
lf_status lf_map_file(const char *path, lf_mapping *out);
void lf_unmap(lf_mapping *mapping);

/* lf_textinfo.c */
lf_status lf_utf16_to_utf8(const uint8_t *in, size_t in_len, int big_endian, uint8_t **out, size_t *out_len);
lf_status lf_utf8_to_utf16(const uint8_t *in, size_t in_len, int big_endian, uint8_t **out, size_t *out_len);

/* lf_scan.c */
lf_status lf_doc_scan(struct lf_doc *doc);

#endif /* LF_INTERNAL_H */
