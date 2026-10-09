/* lf_pbx.h — private building blocks of the project.pbxproj merge. */
#ifndef LF_PBX_H
#define LF_PBX_H

#include "lf_internal.h"

/* ---- Growable byte buffer (lf_buf.c). On allocation failure `failed` is set and appends stop. */

typedef struct lf_buf {
    uint8_t *data;
    size_t length;
    size_t capacity;
    int failed;
} lf_buf;

void lf_buf_append(lf_buf *buf, const void *data, size_t length);
void lf_buf_append_cstr(lf_buf *buf, const char *text);
void lf_buf_append_repeat(lf_buf *buf, uint8_t byte, size_t count);
void lf_buf_truncate(lf_buf *buf, size_t length);
void lf_buf_free(lf_buf *buf);

/* ---- Hash map from byte strings (not copied: they must outlive the map) to indexes (lf_map.c). */

typedef struct lf_map_slot {
    const uint8_t *key;
    size_t length;
    uint64_t hash;
    size_t value;
    int used;
} lf_map_slot;

typedef struct lf_span_map {
    lf_map_slot *slots;
    size_t capacity;
    size_t count;
} lf_span_map;

enum { LF_MAP_NO_MEMORY = 0, LF_MAP_ADDED = 1, LF_MAP_EXISTS = 2 };

int lf_map_init(lf_span_map *map, size_t expected);
int lf_map_put(lf_span_map *map, const uint8_t *key, size_t length, size_t value);
int lf_map_get(const lf_span_map *map, const uint8_t *key, size_t length, size_t *value);
/* Pointer to the stored value, for in-place updates; NULL if the key is absent. */
size_t *lf_map_find(lf_span_map *map, const uint8_t *key, size_t length);
void lf_map_free(lf_span_map *map);

/* ---- Lexer for Xcode's OpenStep plist dialect (lf_pbx_lexer.c). */

typedef enum pbx_tok_kind {
    PBX_TOK_END,
    PBX_TOK_ERROR,
    PBX_TOK_STRING, /* bare word or "quoted string" (quotes included) */
    PBX_TOK_COMMENT, /* block comment, delimiters included */
    PBX_TOK_LBRACE,
    PBX_TOK_RBRACE,
    PBX_TOK_LPAREN,
    PBX_TOK_RPAREN,
    PBX_TOK_EQUALS,
    PBX_TOK_SEMICOLON,
    PBX_TOK_COMMA,
} pbx_tok_kind;

typedef struct pbx_tok {
    pbx_tok_kind kind;
    size_t start;
    size_t end;
} pbx_tok;

typedef struct pbx_lexer {
    const uint8_t *data;
    size_t length;
    size_t pos;
} pbx_lexer;

/* Next token; skips whitespace and line comments. */
pbx_tok pbx_lex(pbx_lexer *lexer);

/* Skips one value (string, or balanced braces/parentheses); sets *end past it. Returns 0 if malformed. */
int pbx_skip_value(pbx_lexer *lexer, size_t *end);

/* ---- Parsed file: the objects dictionary split into sections and entries (lf_pbx_parse.c). */

typedef struct pbx_entry {
    size_t raw_start, raw_end;     /* whole entry, from the start of its line to after its newline */
    size_t id_start, id_end;
    size_t value_start, value_end; /* the object's dictionary, braces included */
    size_t section;
} pbx_entry;

typedef struct pbx_section {
    size_t name_start, name_end;
} pbx_section;

typedef struct pbx_file {
    const uint8_t *data;
    size_t length;
    size_t prefix_end;   /* text before the first section, through "objects = {\n" */
    size_t suffix_start; /* text after the last section, from the "\t};" that closes objects */
    pbx_section *sections;
    size_t section_count;
    pbx_entry *entries;
    size_t entry_count;
} pbx_file;

/* Parses Xcode's layout strictly; anything else is LF_ERR_UNSUPPORTED. `side` names the input in messages. */
lf_status pbx_file_parse(const uint8_t *data, size_t length, const char *side, pbx_file *out);
void pbx_file_free(pbx_file *file);

/* ---- Parsed values, for objects that need a field-by-field merge (lf_pbx_value.c). */

typedef enum pbx_kind {
    PBX_STRING,
    PBX_DICT,
    PBX_ARRAY,
} pbx_kind;

typedef struct pbx_value pbx_value;

typedef struct pbx_item {
    size_t raw_start, raw_end;     /* multiline: whole line(s) incl. indent and newline; inline: "x; " or "x, " */
    size_t key_start, key_end;     /* dictionary key, or the element's own token for arrays */
    size_t value_start, value_end; /* value plus its trailing comment */
    pbx_value *value;
} pbx_item;

struct pbx_value {
    pbx_kind kind;
    const uint8_t *data;
    size_t start, end;   /* braces/parentheses included, or the string token */
    int multiline;
    size_t close_start;  /* multiline: start of the line holding the closing brace */
    pbx_item *items;
    size_t count;
    size_t capacity;
};

/* Parses the value starting at `start`. NULL if it is not in Xcode's layout (or out of memory). */
pbx_value *pbx_value_parse(const uint8_t *data, size_t length, size_t start);
void pbx_value_free(pbx_value *value);

/* ---- Value merge (lf_pbx_merge_value.c). */

typedef struct pbx_merge_ctx {
    uint32_t marker_size;
    int include_base;
    const char *current_label;
    const char *base_label;
    const char *incoming_label;
} pbx_merge_ctx;

typedef enum pbx_merge_status {
    PBX_MERGE_OK,
    PBX_MERGE_CONFLICT, /* cannot be merged here; the caller marks a larger region as a conflict */
    PBX_MERGE_NO_MEMORY,
} pbx_merge_status;

/* Writes one conflict block: markers around each side's text (whole lines). */
void pbx_write_conflict(lf_buf *out, const pbx_merge_ctx *ctx, const uint8_t *ours, size_t ours_length,
                        const uint8_t *base, size_t base_length, const uint8_t *theirs, size_t theirs_length);

/*
 * Merges one object entry changed on both sides (base may be NULL when both sides added it).
 * On PBX_MERGE_OK the merged entry text is appended to `out` and *conflicts counts the
 * conflict blocks inside it; otherwise `out` is left unchanged.
 */
pbx_merge_status pbx_merge_entry(const pbx_merge_ctx *ctx, const pbx_file *base_file, const pbx_entry *base,
                                 const pbx_file *ours_file, const pbx_entry *ours, const pbx_file *theirs_file,
                                 const pbx_entry *theirs, lf_buf *out, uint64_t *conflicts);

#endif /* LF_PBX_H */
