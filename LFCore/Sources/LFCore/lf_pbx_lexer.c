/* lf_pbx_lexer.c — tokens of Xcode's OpenStep property-list dialect. */
#include "lf_pbx.h"

#define LF_MAX_NESTING 64

static int is_space(uint8_t c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

static int is_delimiter(uint8_t c) {
    return is_space(c) || c == '{' || c == '}' || c == '(' || c == ')' || c == '=' || c == ';' || c == ',' || c == '"';
}

static int starts_comment(const uint8_t *data, size_t length, size_t pos) {
    return pos + 1 < length && data[pos] == '/' && (data[pos + 1] == '*' || data[pos + 1] == '/');
}

static pbx_tok make(pbx_lexer *lexer, pbx_tok_kind kind, size_t start, size_t end) {
    pbx_tok tok = {kind, start, end};
    lexer->pos = end;
    return tok;
}

static pbx_tok lex_block_comment(pbx_lexer *lexer, size_t start) {
    for (size_t p = start + 2; p + 1 < lexer->length; p++) {
        if (lexer->data[p] == '*' && lexer->data[p + 1] == '/') {
            return make(lexer, PBX_TOK_COMMENT, start, p + 2);
        }
    }
    return make(lexer, PBX_TOK_ERROR, start, lexer->length);
}

static pbx_tok lex_quoted(pbx_lexer *lexer, size_t start) {
    size_t p = start + 1;
    while (p < lexer->length && lexer->data[p] != '"') {
        p += lexer->data[p] == '\\' ? 2 : 1;
    }
    if (p >= lexer->length) {
        return make(lexer, PBX_TOK_ERROR, start, lexer->length);
    }
    return make(lexer, PBX_TOK_STRING, start, p + 1);
}

pbx_tok pbx_lex(pbx_lexer *lexer) {
    const uint8_t *data = lexer->data;
    const size_t length = lexer->length;
    size_t p = lexer->pos;
    for (;;) {
        while (p < length && is_space(data[p])) {
            p++;
        }
        if (p + 1 < length && data[p] == '/' && data[p + 1] == '/') {
            while (p < length && data[p] != '\n') {
                p++;
            }
            continue;
        }
        break;
    }
    if (p >= length) {
        return make(lexer, PBX_TOK_END, p, p);
    }
    switch (data[p]) {
    case '{': return make(lexer, PBX_TOK_LBRACE, p, p + 1);
    case '}': return make(lexer, PBX_TOK_RBRACE, p, p + 1);
    case '(': return make(lexer, PBX_TOK_LPAREN, p, p + 1);
    case ')': return make(lexer, PBX_TOK_RPAREN, p, p + 1);
    case '=': return make(lexer, PBX_TOK_EQUALS, p, p + 1);
    case ';': return make(lexer, PBX_TOK_SEMICOLON, p, p + 1);
    case ',': return make(lexer, PBX_TOK_COMMA, p, p + 1);
    case '"': return lex_quoted(lexer, p);
    default: break;
    }
    if (starts_comment(data, length, p)) {
        return lex_block_comment(lexer, p);
    }
    size_t q = p;
    while (q < length && !is_delimiter(data[q]) && !starts_comment(data, length, q)) {
        q++;
    }
    return make(lexer, q > p ? PBX_TOK_STRING : PBX_TOK_ERROR, p, q > p ? q : p + 1);
}

int pbx_skip_value(pbx_lexer *lexer, size_t *end) {
    pbx_tok tok = pbx_lex(lexer);
    if (tok.kind == PBX_TOK_STRING) {
        *end = tok.end;
        return 1;
    }
    if (tok.kind != PBX_TOK_LBRACE && tok.kind != PBX_TOK_LPAREN) {
        return 0;
    }
    pbx_tok_kind open[LF_MAX_NESTING];
    size_t depth = 0;
    open[depth++] = tok.kind;
    while (depth > 0) {
        tok = pbx_lex(lexer);
        switch (tok.kind) {
        case PBX_TOK_LBRACE:
        case PBX_TOK_LPAREN:
            if (depth == LF_MAX_NESTING) {
                return 0;
            }
            open[depth++] = tok.kind;
            break;
        case PBX_TOK_RBRACE:
        case PBX_TOK_RPAREN:
            if (open[--depth] != (tok.kind == PBX_TOK_RBRACE ? PBX_TOK_LBRACE : PBX_TOK_LPAREN)) {
                return 0;
            }
            break;
        case PBX_TOK_END:
        case PBX_TOK_ERROR:
            return 0;
        default:
            break;
        }
    }
    *end = tok.end;
    return 1;
}
