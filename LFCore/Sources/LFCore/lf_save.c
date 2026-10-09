/*
 * lf_save.c — streams the resolved document to a temporary file next to the
 * destination, fsyncs it, restores the permission bits and renames it into
 * place. The destination is never left half-written.
 */
#include "lf_internal.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define LF_WRITE_BUFFER_BYTES (1u << 20)
#define LF_TEMP_NAME ".lfgit-XXXXXX"

/* Output sink: buffered file writes, or growing memory when the encoding needs a second pass. */
typedef struct lf_sink {
    int fd;
    int to_memory;
    uint8_t *buffer;
    size_t length;
    size_t capacity;
    const char *path; /* for error messages */
} lf_sink;

static lf_status write_all(int fd, const uint8_t *data, size_t length, const char *path) {
    while (length > 0) {
        const ssize_t written = write(fd, data, length);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            return lf_fail_errno(LF_ERR_IO, "write", path);
        }
        data += written;
        length -= (size_t)written;
    }
    return LF_OK;
}

static lf_status sink_flush(lf_sink *sink) {
    if (sink->to_memory || sink->length == 0) {
        return LF_OK;
    }
    const lf_status status = write_all(sink->fd, sink->buffer, sink->length, sink->path);
    sink->length = 0;
    return status;
}

static lf_status sink_grow(lf_sink *sink, size_t needed) {
    size_t capacity = sink->capacity ? sink->capacity : LF_WRITE_BUFFER_BYTES;
    while (capacity < needed) {
        if (capacity > SIZE_MAX / 2) {
            return lf_fail(LF_ERR_NO_MEMORY, "output too large");
        }
        capacity *= 2;
    }
    uint8_t *grown = realloc(sink->buffer, capacity);
    if (grown == NULL) {
        return lf_fail(LF_ERR_NO_MEMORY, "out of memory while saving");
    }
    sink->buffer = grown;
    sink->capacity = capacity;
    return LF_OK;
}

static lf_status sink_write(lf_sink *sink, const uint8_t *data, uint64_t length) {
    if (length == 0) {
        return LF_OK;
    }
    if (!sink->to_memory && length >= LF_WRITE_BUFFER_BYTES) {
        const lf_status status = sink_flush(sink);
        return status != LF_OK ? status : write_all(sink->fd, data, (size_t)length, sink->path);
    }
    if (sink->length + length > sink->capacity || sink->buffer == NULL) {
        lf_status status = LF_OK;
        if (!sink->to_memory) {
            status = sink_flush(sink);
        }
        if (status == LF_OK && sink->length + length > sink->capacity) {
            status = sink_grow(sink, sink->length + (size_t)length);
        }
        if (status == LF_OK && sink->buffer == NULL) {
            status = sink_grow(sink, (size_t)length);
        }
        if (status != LF_OK) {
            return status;
        }
    }
    memcpy(sink->buffer + sink->length, data, (size_t)length);
    sink->length += (size_t)length;
    return LF_OK;
}

static lf_status emit_pair(lf_sink *sink, const lf_doc *doc, lf_range first, lf_range second) {
    const lf_status status = sink_write(sink, doc->data + first.offset, first.length);
    return status != LF_OK ? status : sink_write(sink, doc->data + second.offset, second.length);
}

static lf_status emit_resolution(lf_sink *sink, const lf_doc *doc, const lf_conflict_rec *rec) {
    const lf_range current = {rec->cur_start, rec->cur_end - rec->cur_start};
    const lf_range incoming = {rec->inc_start, rec->inc_end - rec->inc_start};
    switch ((lf_choice)rec->choice) {
    case LF_CHOICE_CURRENT:
        return sink_write(sink, doc->data + current.offset, current.length);
    case LF_CHOICE_INCOMING:
        return sink_write(sink, doc->data + incoming.offset, incoming.length);
    case LF_CHOICE_BOTH_CURRENT_FIRST:
        return emit_pair(sink, doc, current, incoming);
    case LF_CHOICE_BOTH_INCOMING_FIRST:
        return emit_pair(sink, doc, incoming, current);
    case LF_CHOICE_BASE:
        return sink_write(sink, doc->data + rec->base_start, rec->base_end - rec->base_start);
    case LF_CHOICE_CUSTOM:
        return sink_write(sink, rec->custom, rec->custom_len);
    case LF_CHOICE_UNRESOLVED:
        break;
    }
    /* Unresolved with LF_SAVE_FORCE: keep the conflict exactly as it was. */
    return sink_write(sink, doc->data + rec->marker_start, rec->marker_end - rec->marker_start);
}

/* Streams the whole resolved document: untouched text between conflicts, resolutions in place of them. */
static lf_status emit_document(lf_sink *sink, const lf_doc *doc) {
    uint64_t cursor = 0;
    for (size_t i = 0; i < doc->conflict_count; i++) {
        const lf_conflict_rec *rec = &doc->conflicts[i];
        lf_status status = sink_write(sink, doc->data + cursor, rec->marker_start - cursor);
        if (status == LF_OK) {
            status = emit_resolution(sink, doc, rec);
        }
        if (status != LF_OK) {
            return status;
        }
        cursor = rec->marker_end;
    }
    return sink_write(sink, doc->data + cursor, doc->size - cursor);
}

static lf_status write_encoded(int fd, const lf_doc *doc, lf_sink *memory, const char *path) {
    uint8_t *encoded = NULL;
    size_t encoded_length = 0;
    const int big_endian = doc->encoding == LF_ENCODING_UTF16BE;
    lf_status status = lf_utf8_to_utf16(memory->buffer, memory->length, big_endian, &encoded, &encoded_length);
    if (status == LF_OK) {
        status = write_all(fd, encoded, encoded_length, path);
    }
    free(encoded);
    return status;
}

static lf_status unresolved_error(const lf_doc *doc) {
    uint64_t unresolved = 0;
    uint64_t first_line = 0;
    for (size_t i = 0; i < doc->conflict_count; i++) {
        if (doc->conflicts[i].choice == LF_CHOICE_UNRESOLVED) {
            first_line = unresolved == 0 ? doc->conflicts[i].open_line : first_line;
            unresolved++;
        }
    }
    if (unresolved == 0) {
        return LF_OK;
    }
    return lf_fail(LF_ERR_UNRESOLVED, "%llu unresolved conflict(s), first at line %llu", (unsigned long long)unresolved,
                   (unsigned long long)first_line);
}

static char *temp_path_for(const char *destination) {
    const char *slash = strrchr(destination, '/');
    const int directory_length = slash ? (int)(slash - destination) + 1 : 0;
    const size_t capacity = (size_t)directory_length + sizeof LF_TEMP_NAME;
    char *path = malloc(capacity);
    if (path != NULL) {
        snprintf(path, capacity, "%.*s%s", directory_length, destination, LF_TEMP_NAME);
    }
    return path;
}

static lf_status finish_temp_file(int fd, const char *temp, const char *destination, mode_t mode) {
    if (fsync(fd) != 0) {
        return lf_fail_errno(LF_ERR_IO, "sync", temp);
    }
    if (fchmod(fd, mode) != 0) {
        return lf_fail_errno(LF_ERR_IO, "set permissions on", temp);
    }
    if (close(fd) != 0) {
        return lf_fail_errno(LF_ERR_IO, "close", temp);
    }
    if (rename(temp, destination) != 0) {
        return lf_fail_errno(LF_ERR_IO, "replace", destination);
    }
    return LF_OK;
}

lf_status lf_doc_save(const lf_doc *doc, const char *dest_path, uint32_t flags) {
    if (doc == NULL) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "lf_doc_save: null document");
    }
    if (!(flags & LF_SAVE_FORCE)) {
        const lf_status unresolved = unresolved_error(doc);
        if (unresolved != LF_OK) {
            return unresolved;
        }
    }
    const char *destination = dest_path != NULL ? dest_path : doc->path;
    char *temp = temp_path_for(destination);
    if (temp == NULL) {
        return lf_fail(LF_ERR_NO_MEMORY, "out of memory while saving");
    }
    const int fd = mkstemp(temp);
    if (fd < 0) {
        const lf_status status = lf_fail_errno(LF_ERR_IO, "create a temporary file for", destination);
        free(temp);
        return status;
    }
    struct stat existing;
    const mode_t mode = stat(destination, &existing) == 0 ? (existing.st_mode & 07777) : (mode_t)doc->mode;

    const int needs_reencoding = doc->encoding == LF_ENCODING_UTF16LE || doc->encoding == LF_ENCODING_UTF16BE;
    lf_sink sink = {fd, needs_reencoding, NULL, 0, 0, temp};
    lf_status status = emit_document(&sink, doc);
    if (status == LF_OK) {
        status = needs_reencoding ? write_encoded(fd, doc, &sink, temp) : sink_flush(&sink);
    }
    if (status == LF_OK) {
        status = finish_temp_file(fd, temp, destination, mode);
    } else {
        close(fd);
    }
    if (status != LF_OK) {
        unlink(temp);
    }
    free(sink.buffer);
    free(temp);
    return status;
}
