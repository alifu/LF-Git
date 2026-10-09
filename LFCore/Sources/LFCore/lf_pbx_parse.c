/*
 * lf_pbx_parse.c — splits a project.pbxproj into prefix, sections of object entries, and suffix.
 *
 * The layout is matched exactly as Xcode writes it:
 *     ...objects = {\n
 *     \n/\* Begin <Name> section *\/\n
 *     <tabs><ID> [/\* comment *\/] = {...};\n        (one entry, one or more lines)
 *     /\* End <Name> section *\/\n
 *     ...
 *     \t};\n ... }
 * so re-assembling the parsed pieces reproduces the input byte for byte. Anything else is
 * reported as unsupported and the caller falls back to a line-based merge.
 */
#include "lf_pbx.h"

#include <stdlib.h>
#include <string.h>

static const char BEGIN_PREFIX[] = "\n/* Begin ";
static const char END_PREFIX[] = "/* End ";
static const char SECTION_SUFFIX[] = " section */\n";
#define LITERAL_LENGTH(text) (sizeof(text) - 1)

typedef struct parse_state {
    pbx_file *file;
    const char *side;
    size_t entry_capacity;
    size_t section_capacity;
    lf_span_map ids;
} parse_state;

static int has_text(const pbx_file *file, size_t pos, const char *text, size_t length) {
    return pos <= file->length && file->length - pos >= length && memcmp(file->data + pos, text, length) == 0;
}

static lf_status unsupported(const parse_state *state, size_t pos, const char *what) {
    size_t line = 1;
    for (size_t i = 0; i < pos && i < state->file->length; i++) {
        line += state->file->data[i] == '\n';
    }
    return lf_fail(LF_ERR_UNSUPPORTED, "%s is not an Xcode project file in Xcode's format (line %zu: %s)", state->side,
                   line, what);
}

static lf_status no_memory(void) {
    return lf_fail(LF_ERR_NO_MEMORY, "out of memory reading the project file");
}

static int grow_array(void **items, size_t *capacity, size_t count, size_t item_size) {
    if (count < *capacity) {
        return 1;
    }
    const size_t next = *capacity ? *capacity * 2 : 64;
    void *grown = realloc(*items, next * item_size);
    if (grown == NULL) {
        return 0;
    }
    *items = grown;
    *capacity = next;
    return 1;
}

/* One object entry starting at the beginning of a line. */
static lf_status parse_entry(parse_state *state, size_t pos, size_t section, size_t *next) {
    pbx_file *file = state->file;
    pbx_lexer lexer = {file->data, file->length, pos};
    pbx_entry entry = {0};
    entry.raw_start = pos;
    entry.section = section;

    pbx_tok tok = pbx_lex(&lexer);
    for (size_t p = pos; p < tok.start; p++) {
        if (file->data[p] != '\t' && file->data[p] != ' ') {
            return unsupported(state, pos, "unexpected text before an object");
        }
    }
    if (tok.kind != PBX_TOK_STRING) {
        return unsupported(state, tok.start, "expected an object ID");
    }
    entry.id_start = tok.start;
    entry.id_end = tok.end;
    tok = pbx_lex(&lexer);
    if (tok.kind == PBX_TOK_COMMENT) {
        tok = pbx_lex(&lexer);
    }
    if (tok.kind != PBX_TOK_EQUALS) {
        return unsupported(state, tok.start, "expected '=' after an object ID");
    }
    const size_t value_pos = lexer.pos;
    tok = pbx_lex(&lexer);
    if (tok.kind != PBX_TOK_LBRACE) {
        return unsupported(state, tok.start, "an object must be a dictionary");
    }
    entry.value_start = tok.start;
    lexer.pos = value_pos;
    if (!pbx_skip_value(&lexer, &entry.value_end)) {
        return unsupported(state, entry.value_start, "unbalanced object");
    }
    tok = pbx_lex(&lexer);
    if (tok.kind != PBX_TOK_SEMICOLON || tok.end >= file->length || file->data[tok.end] != '\n') {
        return unsupported(state, tok.start, "expected ';' and a newline after an object");
    }
    entry.raw_end = tok.end + 1;

    switch (lf_map_put(&state->ids, file->data + entry.id_start, entry.id_end - entry.id_start, file->entry_count)) {
    case LF_MAP_NO_MEMORY: return no_memory();
    case LF_MAP_EXISTS: return unsupported(state, entry.id_start, "duplicate object ID");
    default: break;
    }
    if (!grow_array((void **)&file->entries, &state->entry_capacity, file->entry_count, sizeof entry)) {
        return no_memory();
    }
    file->entries[file->entry_count++] = entry;
    *next = entry.raw_end;
    return LF_OK;
}

/* "\n/\* Begin X section *\/\n" ... "/\* End X section *\/\n", repeated. Returns the position after the last. */
static lf_status parse_sections(parse_state *state, size_t pos, size_t *end) {
    pbx_file *file = state->file;
    while (has_text(file, pos, BEGIN_PREFIX, LITERAL_LENGTH(BEGIN_PREFIX))) {
        const size_t name_start = pos + LITERAL_LENGTH(BEGIN_PREFIX);
        const uint8_t *newline = memchr(file->data + name_start, '\n', file->length - name_start);
        const size_t line_end = newline ? (size_t)(newline - file->data) + 1 : file->length;
        if (line_end - name_start < LITERAL_LENGTH(SECTION_SUFFIX) + 1 ||
            !has_text(file, line_end - LITERAL_LENGTH(SECTION_SUFFIX), SECTION_SUFFIX, LITERAL_LENGTH(SECTION_SUFFIX))) {
            return unsupported(state, pos + 1, "malformed section header");
        }
        pbx_section section = {name_start, line_end - LITERAL_LENGTH(SECTION_SUFFIX)};
        const size_t name_length = section.name_end - section.name_start;
        if (!grow_array((void **)&file->sections, &state->section_capacity, file->section_count, sizeof section)) {
            return no_memory();
        }
        const size_t index = file->section_count;
        file->sections[file->section_count++] = section;
        pos = line_end;
        while (!has_text(file, pos, END_PREFIX, LITERAL_LENGTH(END_PREFIX))) {
            if (pos >= file->length) {
                return unsupported(state, pos, "unterminated section");
            }
            const lf_status status = parse_entry(state, pos, index, &pos);
            if (status != LF_OK) {
                return status;
            }
        }
        pos += LITERAL_LENGTH(END_PREFIX);
        if (!has_text(file, pos, (const char *)file->data + section.name_start, name_length) ||
            !has_text(file, pos + name_length, SECTION_SUFFIX, LITERAL_LENGTH(SECTION_SUFFIX))) {
            return unsupported(state, pos, "section end does not match its beginning");
        }
        pos += name_length + LITERAL_LENGTH(SECTION_SUFFIX);
    }
    *end = pos;
    return LF_OK;
}

static int token_is(const pbx_file *file, pbx_tok tok, const char *text) {
    const size_t length = strlen(text);
    return tok.end - tok.start == length && memcmp(file->data + tok.start, text, length) == 0;
}

/* The objects dictionary: "{\n", sections, then the closing line. Leaves the lexer after "};". */
static lf_status parse_objects(parse_state *state, pbx_lexer *lexer) {
    pbx_file *file = state->file;
    const pbx_tok open = pbx_lex(lexer);
    if (open.kind != PBX_TOK_LBRACE || open.end >= file->length || file->data[open.end] != '\n') {
        return unsupported(state, open.start, "objects must start with '{' and a newline");
    }
    file->prefix_end = open.end + 1;
    lf_status status = parse_sections(state, file->prefix_end, &file->suffix_start);
    if (status != LF_OK) {
        return status;
    }
    lexer->pos = file->suffix_start;
    if (pbx_lex(lexer).kind != PBX_TOK_RBRACE || pbx_lex(lexer).kind != PBX_TOK_SEMICOLON) {
        return unsupported(state, file->suffix_start, "unexpected text in the objects dictionary");
    }
    return LF_OK;
}

static lf_status parse_top_level(parse_state *state) {
    pbx_file *file = state->file;
    pbx_lexer lexer = {file->data, file->length, 0};
    int found_objects = 0;
    if (pbx_lex(&lexer).kind != PBX_TOK_LBRACE) {
        return unsupported(state, 0, "expected '{'");
    }
    for (;;) {
        pbx_tok key = pbx_lex(&lexer);
        if (key.kind == PBX_TOK_RBRACE) {
            break;
        }
        if (key.kind != PBX_TOK_STRING || pbx_lex(&lexer).kind != PBX_TOK_EQUALS) {
            return unsupported(state, key.start, "expected 'key = value;'");
        }
        if (token_is(file, key, "objects")) {
            if (found_objects) {
                return unsupported(state, key.start, "a second objects dictionary");
            }
            const lf_status status = parse_objects(state, &lexer);
            if (status != LF_OK) {
                return status;
            }
            found_objects = 1;
            continue;
        }
        size_t end = 0;
        if (!pbx_skip_value(&lexer, &end)) {
            return unsupported(state, key.start, "malformed value");
        }
        pbx_tok tok = pbx_lex(&lexer);
        if (tok.kind == PBX_TOK_COMMENT) {
            tok = pbx_lex(&lexer);
        }
        if (tok.kind != PBX_TOK_SEMICOLON) {
            return unsupported(state, tok.start, "expected ';'");
        }
    }
    if (pbx_lex(&lexer).kind != PBX_TOK_END) {
        return unsupported(state, lexer.pos, "text after the closing '}'");
    }
    return found_objects ? LF_OK : unsupported(state, 0, "no objects dictionary");
}

lf_status pbx_file_parse(const uint8_t *data, size_t length, const char *side, pbx_file *out) {
    memset(out, 0, sizeof *out);
    out->data = data;
    out->length = data != NULL ? length : 0;
    parse_state state = {out, side, 0, 0, {0}};
    if (out->length == 0) {
        return unsupported(&state, 0, "empty");
    }
    if (!lf_map_init(&state.ids, length / 64)) {
        return no_memory();
    }
    const lf_status status = parse_top_level(&state);
    lf_map_free(&state.ids);
    if (status != LF_OK) {
        pbx_file_free(out);
    }
    return status;
}

void pbx_file_free(pbx_file *file) {
    free(file->sections);
    free(file->entries);
    file->sections = NULL;
    file->entries = NULL;
    file->section_count = 0;
    file->entry_count = 0;
}
