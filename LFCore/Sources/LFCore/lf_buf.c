#include "lf_pbx.h"

#include <stdlib.h>
#include <string.h>

#define LF_BUF_INITIAL_CAPACITY 4096u

static int reserve(lf_buf *buf, size_t extra) {
    if (buf->failed) {
        return 0;
    }
    if (extra > SIZE_MAX - buf->length) {
        buf->failed = 1;
        return 0;
    }
    const size_t needed = buf->length + extra;
    if (needed <= buf->capacity) {
        return 1;
    }
    size_t capacity = buf->capacity ? buf->capacity : LF_BUF_INITIAL_CAPACITY;
    while (capacity < needed) {
        if (capacity > SIZE_MAX / 2) {
            buf->failed = 1;
            return 0;
        }
        capacity *= 2;
    }
    uint8_t *grown = realloc(buf->data, capacity);
    if (grown == NULL) {
        buf->failed = 1;
        return 0;
    }
    buf->data = grown;
    buf->capacity = capacity;
    return 1;
}

void lf_buf_append(lf_buf *buf, const void *data, size_t length) {
    if (length == 0 || !reserve(buf, length)) {
        return;
    }
    memcpy(buf->data + buf->length, data, length);
    buf->length += length;
}

void lf_buf_append_cstr(lf_buf *buf, const char *text) {
    lf_buf_append(buf, text, strlen(text));
}

void lf_buf_append_repeat(lf_buf *buf, uint8_t byte, size_t count) {
    if (count == 0 || !reserve(buf, count)) {
        return;
    }
    memset(buf->data + buf->length, byte, count);
    buf->length += count;
}

void lf_buf_truncate(lf_buf *buf, size_t length) {
    if (length < buf->length) {
        buf->length = length;
    }
}

void lf_buf_free(lf_buf *buf) {
    free(buf->data);
    buf->data = NULL;
    buf->length = 0;
    buf->capacity = 0;
    buf->failed = 0;
}
