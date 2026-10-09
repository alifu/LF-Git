/*
 * lf_pbx_value.c — parses one value (dictionary, array or string) in Xcode's exact layout:
 *   multiline dictionary:  "{\n" + "<indent>key = value;\n"... + "<indent>}"
 *   inline dictionary:     "{" + "key = value; "... + "}"
 *   arrays likewise with "(" ")" and "value," / "value, ".
 * Every item keeps its raw text, so untouched items are written back verbatim.
 */
#include "lf_pbx.h"

#include <stdlib.h>
#include <string.h>

#define LF_MAX_VALUE_DEPTH 64

static pbx_value *parse_at(pbx_lexer *lexer, pbx_tok first, int depth);

void pbx_value_free(pbx_value *value) {
    if (value == NULL) {
        return;
    }
    for (size_t i = 0; i < value->count; i++) {
        pbx_value_free(value->items[i].value);
    }
    free(value->items);
    free(value);
}

static pbx_value *new_value(pbx_kind kind, const uint8_t *data, size_t start, size_t end) {
    pbx_value *value = calloc(1, sizeof *value);
    if (value != NULL) {
        value->kind = kind;
        value->data = data;
        value->start = start;
        value->end = end;
    }
    return value;
}

static int push_item(pbx_value *value, const pbx_item *item) {
    if (value->count == value->capacity) {
        const size_t capacity = value->capacity ? value->capacity * 2 : 8;
        pbx_item *grown = realloc(value->items, capacity * sizeof *grown);
        if (grown == NULL) {
            return 0;
        }
        value->items = grown;
        value->capacity = capacity;
    }
    value->items[value->count++] = *item;
    return 1;
}

static size_t skip_blanks(const pbx_lexer *lexer, size_t pos) {
    while (pos < lexer->length && (lexer->data[pos] == ' ' || lexer->data[pos] == '\t')) {
        pos++;
    }
    return pos;
}

/* Parses one item starting exactly at `pos`. Returns 0 if it is not in the expected layout. */
static int parse_item(pbx_lexer *lexer, pbx_value *container, size_t raw_start, size_t pos, int depth) {
    const int is_dict = container->kind == PBX_DICT;
    pbx_item item = {0};
    item.raw_start = raw_start;
    lexer->pos = pos;
    pbx_tok tok = pbx_lex(lexer);
    if (tok.start != pos) {
        return 0;
    }
    if (is_dict) {
        if (tok.kind != PBX_TOK_STRING) {
            return 0;
        }
        item.key_start = tok.start;
        item.key_end = tok.end;
        tok = pbx_lex(lexer);
        if (tok.kind == PBX_TOK_COMMENT) {
            tok = pbx_lex(lexer);
        }
        if (tok.kind != PBX_TOK_EQUALS) {
            return 0;
        }
        tok = pbx_lex(lexer);
    }
    item.value_start = tok.start;
    item.value = parse_at(lexer, tok, depth + 1);
    if (item.value == NULL) {
        return 0;
    }
    if (!is_dict) {
        item.key_start = item.value->start;
        item.key_end = item.value->end;
    }
    item.value_end = item.value->end;
    tok = pbx_lex(lexer);
    if (tok.kind == PBX_TOK_COMMENT) {
        item.value_end = tok.end;
        tok = pbx_lex(lexer);
    }
    const uint8_t separator_after = container->multiline ? '\n' : ' ';
    if (tok.kind != (is_dict ? PBX_TOK_SEMICOLON : PBX_TOK_COMMA) || tok.end >= lexer->length ||
        lexer->data[tok.end] != separator_after) {
        pbx_value_free(item.value);
        return 0;
    }
    item.raw_end = tok.end + 1;
    if (!push_item(container, &item)) {
        pbx_value_free(item.value);
        return 0;
    }
    return 1;
}

static pbx_value *parse_container(pbx_lexer *lexer, size_t open, pbx_kind kind, int depth) {
    pbx_value *value = new_value(kind, lexer->data, open, open + 1);
    if (value == NULL) {
        return NULL;
    }
    const uint8_t close = kind == PBX_DICT ? '}' : ')';
    value->multiline = open + 1 < lexer->length && lexer->data[open + 1] == '\n';
    size_t pos = open + 1 + (value->multiline ? 1 : 0);
    for (;;) {
        const size_t line_start = pos;
        const size_t first = value->multiline ? skip_blanks(lexer, pos) : pos;
        if (first >= lexer->length) {
            break;
        }
        if (lexer->data[first] == close) {
            value->close_start = line_start;
            value->end = first + 1;
            lexer->pos = first + 1;
            return value;
        }
        if (!parse_item(lexer, value, line_start, first, depth)) {
            break;
        }
        pos = value->items[value->count - 1].raw_end;
    }
    pbx_value_free(value);
    return NULL;
}

static pbx_value *parse_at(pbx_lexer *lexer, pbx_tok first, int depth) {
    if (depth > LF_MAX_VALUE_DEPTH) {
        return NULL;
    }
    switch (first.kind) {
    case PBX_TOK_STRING: return new_value(PBX_STRING, lexer->data, first.start, first.end);
    case PBX_TOK_LBRACE: return parse_container(lexer, first.start, PBX_DICT, depth);
    case PBX_TOK_LPAREN: return parse_container(lexer, first.start, PBX_ARRAY, depth);
    default: return NULL;
    }
}

pbx_value *pbx_value_parse(const uint8_t *data, size_t length, size_t start) {
    pbx_lexer lexer = {data, length, start};
    return parse_at(&lexer, pbx_lex(&lexer), 0);
}
