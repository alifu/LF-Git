#include "lf_internal.h"

#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define LF_MAX_CODE_POINT 0x10FFFFu
#define LF_SURROGATE_HIGH_FIRST 0xD800u
#define LF_SURROGATE_HIGH_LAST 0xDBFFu
#define LF_SURROGATE_LOW_FIRST 0xDC00u
#define LF_SURROGATE_LOW_LAST 0xDFFFu
#define LF_SUPPLEMENTARY_BASE 0x10000u

/* ---- Detection ---------------------------------------------------------- */

static int starts_with(const uint8_t *data, size_t length, const uint8_t *prefix, size_t prefix_length) {
    return length >= prefix_length && memcmp(data, prefix, prefix_length) == 0;
}

lf_text_info lf_detect_text(const uint8_t *data, size_t length) {
    static const uint8_t utf32le_bom[] = {0xFF, 0xFE, 0x00, 0x00};
    static const uint8_t utf32be_bom[] = {0x00, 0x00, 0xFE, 0xFF};
    static const uint8_t utf16le_bom[] = {0xFF, 0xFE};
    static const uint8_t utf16be_bom[] = {0xFE, 0xFF};
    static const uint8_t utf8_bom[] = {0xEF, 0xBB, 0xBF};

    lf_text_info info = {LF_KIND_TEXT, LF_ENCODING_UTF8, 0};
    if (starts_with(data, length, utf32le_bom, sizeof utf32le_bom) ||
        starts_with(data, length, utf32be_bom, sizeof utf32be_bom)) {
        info.kind = LF_KIND_BINARY;
    } else if (starts_with(data, length, utf16le_bom, sizeof utf16le_bom)) {
        info.encoding = LF_ENCODING_UTF16LE;
        info.bom_length = LF_UTF16_BOM_LENGTH;
    } else if (starts_with(data, length, utf16be_bom, sizeof utf16be_bom)) {
        info.encoding = LF_ENCODING_UTF16BE;
        info.bom_length = LF_UTF16_BOM_LENGTH;
    } else {
        if (starts_with(data, length, utf8_bom, sizeof utf8_bom)) {
            info.encoding = LF_ENCODING_UTF8_BOM;
            info.bom_length = LF_UTF8_BOM_LENGTH;
        }
        const size_t sniff = length < LF_BINARY_SNIFF_BYTES ? length : LF_BINARY_SNIFF_BYTES;
        if (sniff > 0 && memchr(data, 0, sniff) != NULL) {
            info.kind = LF_KIND_BINARY;
        }
    }
    return info;
}

lf_status lf_probe_file(const char *path, lf_text_info *out) {
    if (path == NULL || out == NULL) {
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "lf_probe_file: null argument");
    }
    const int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return lf_fail_errno(LF_ERR_IO, "open", path);
    }
    uint8_t buffer[LF_BINARY_SNIFF_BYTES];
    size_t filled = 0;
    while (filled < sizeof buffer) {
        const ssize_t got = read(fd, buffer + filled, sizeof buffer - filled);
        if (got < 0) {
            const lf_status status = lf_fail_errno(LF_ERR_IO, "read", path);
            close(fd);
            return status;
        }
        if (got == 0) {
            break;
        }
        filled += (size_t)got;
    }
    close(fd);
    *out = lf_detect_text(buffer, filled);
    return LF_OK;
}

/* ---- UTF-16 <-> UTF-8 --------------------------------------------------- */

static uint32_t read_unit(const uint8_t *p, int big_endian) {
    return big_endian ? (uint32_t)(p[0] << 8 | p[1]) : (uint32_t)(p[1] << 8 | p[0]);
}

static void write_unit(uint8_t *p, uint32_t unit, int big_endian) {
    p[big_endian ? 0 : 1] = (uint8_t)(unit >> 8);
    p[big_endian ? 1 : 0] = (uint8_t)(unit & 0xFFu);
}

static size_t encode_utf8(uint32_t cp, uint8_t *out) {
    if (cp < 0x80u) {
        out[0] = (uint8_t)cp;
        return 1;
    }
    if (cp < 0x800u) {
        out[0] = (uint8_t)(0xC0u | (cp >> 6));
        out[1] = (uint8_t)(0x80u | (cp & 0x3Fu));
        return 2;
    }
    if (cp < LF_SUPPLEMENTARY_BASE) {
        out[0] = (uint8_t)(0xE0u | (cp >> 12));
        out[1] = (uint8_t)(0x80u | ((cp >> 6) & 0x3Fu));
        out[2] = (uint8_t)(0x80u | (cp & 0x3Fu));
        return 3;
    }
    out[0] = (uint8_t)(0xF0u | (cp >> 18));
    out[1] = (uint8_t)(0x80u | ((cp >> 12) & 0x3Fu));
    out[2] = (uint8_t)(0x80u | ((cp >> 6) & 0x3Fu));
    out[3] = (uint8_t)(0x80u | (cp & 0x3Fu));
    return 4;
}

lf_status lf_utf16_to_utf8(const uint8_t *in, size_t in_len, int big_endian, uint8_t **out, size_t *out_len) {
    if (in_len % 2 != 0) {
        return lf_fail(LF_ERR_UNSUPPORTED, "invalid UTF-16: odd number of bytes");
    }
    const size_t units = in_len / 2;
    uint8_t *buffer = malloc(units * 3 + 1);
    if (buffer == NULL) {
        return lf_fail(LF_ERR_NO_MEMORY, "out of memory decoding UTF-16");
    }
    size_t written = 0;
    for (size_t i = 0; i < units;) {
        const uint32_t unit = read_unit(in + 2 * i, big_endian);
        i++;
        uint32_t cp = unit;
        if (unit >= LF_SURROGATE_HIGH_FIRST && unit <= LF_SURROGATE_HIGH_LAST) {
            const uint32_t low = i < units ? read_unit(in + 2 * i, big_endian) : 0;
            if (low < LF_SURROGATE_LOW_FIRST || low > LF_SURROGATE_LOW_LAST) {
                free(buffer);
                return lf_fail(LF_ERR_UNSUPPORTED, "invalid UTF-16: unpaired high surrogate");
            }
            i++;
            cp = LF_SUPPLEMENTARY_BASE + ((unit - LF_SURROGATE_HIGH_FIRST) << 10) + (low - LF_SURROGATE_LOW_FIRST);
        } else if (unit >= LF_SURROGATE_LOW_FIRST && unit <= LF_SURROGATE_LOW_LAST) {
            free(buffer);
            return lf_fail(LF_ERR_UNSUPPORTED, "invalid UTF-16: unpaired low surrogate");
        }
        written += encode_utf8(cp, buffer + written);
    }
    *out = buffer;
    *out_len = written;
    return LF_OK;
}

/* Decodes one strictly valid UTF-8 sequence; returns its length, or 0 if invalid. */
static size_t decode_utf8(const uint8_t *p, size_t remaining, uint32_t *cp) {
    const uint8_t lead = p[0];
    size_t length;
    uint32_t value;
    uint32_t minimum;
    if (lead < 0x80u) {
        *cp = lead;
        return 1;
    } else if (lead >= 0xC2u && lead <= 0xDFu) {
        length = 2, value = lead & 0x1Fu, minimum = 0x80u;
    } else if (lead >= 0xE0u && lead <= 0xEFu) {
        length = 3, value = lead & 0x0Fu, minimum = 0x800u;
    } else if (lead >= 0xF0u && lead <= 0xF4u) {
        length = 4, value = lead & 0x07u, minimum = LF_SUPPLEMENTARY_BASE;
    } else {
        return 0;
    }
    if (remaining < length) {
        return 0;
    }
    for (size_t i = 1; i < length; i++) {
        if ((p[i] & 0xC0u) != 0x80u) {
            return 0;
        }
        value = (value << 6) | (p[i] & 0x3Fu);
    }
    const int surrogate = value >= LF_SURROGATE_HIGH_FIRST && value <= LF_SURROGATE_LOW_LAST;
    if (value < minimum || value > LF_MAX_CODE_POINT || surrogate) {
        return 0;
    }
    *cp = value;
    return length;
}

lf_status lf_utf8_to_utf16(const uint8_t *in, size_t in_len, int big_endian, uint8_t **out, size_t *out_len) {
    uint8_t *buffer = malloc(in_len * 2 + LF_UTF16_BOM_LENGTH);
    if (buffer == NULL) {
        return lf_fail(LF_ERR_NO_MEMORY, "out of memory encoding UTF-16");
    }
    write_unit(buffer, 0xFEFFu, big_endian);
    size_t written = LF_UTF16_BOM_LENGTH;
    for (size_t i = 0; i < in_len;) {
        uint32_t cp = 0;
        const size_t consumed = decode_utf8(in + i, in_len - i, &cp);
        if (consumed == 0) {
            free(buffer);
            return lf_fail(LF_ERR_UNSUPPORTED, "cannot save as UTF-16: invalid UTF-8 at byte %zu", i);
        }
        i += consumed;
        if (cp >= LF_SUPPLEMENTARY_BASE) {
            const uint32_t reduced = cp - LF_SUPPLEMENTARY_BASE;
            write_unit(buffer + written, LF_SURROGATE_HIGH_FIRST + (reduced >> 10), big_endian);
            write_unit(buffer + written + 2, LF_SURROGATE_LOW_FIRST + (reduced & 0x3FFu), big_endian);
            written += 4;
        } else {
            write_unit(buffer + written, cp, big_endian);
            written += 2;
        }
    }
    *out = buffer;
    *out_len = written;
    return LF_OK;
}
