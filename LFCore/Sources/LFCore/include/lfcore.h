/*
 * lfcore.h — public C API of the LF-Git merge engine.
 *
 * Conventions:
 *   - Every fallible function returns an lf_status; LF_OK means success.
 *     On failure, lf_last_error() describes what went wrong (per thread).
 *   - Handles are opaque; callers never touch their internals.
 *   - Strings returned by the library are static or valid until the next call
 *     on the same thread, and must not be freed.
 *   - An lf_doc is not thread-safe: use one document from one thread at a time.
 *   - Offsets and sizes are 64-bit, so files larger than 4 GB are supported.
 */
#ifndef LFCORE_H
#define LFCORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LF_VERSION_MAJOR 0
#define LF_VERSION_MINOR 2
#define LF_VERSION_PATCH 1

/* Default length of conflict marker runs ("<<<<<<<"), as written by git. */
#define LF_DEFAULT_MARKER_SIZE 7

typedef enum lf_status {
    LF_OK = 0,
    LF_ERR_INVALID_ARGUMENT = 1,
    LF_ERR_IO = 2,
    LF_ERR_NO_MEMORY = 3,
    LF_ERR_MALFORMED = 4,
    LF_ERR_UNRESOLVED = 5,
    LF_ERR_UNSUPPORTED = 6,
    LF_ERR_CHANGED = 7, /* the source file changed on disk after it was opened */
} lf_status;

/* Human-readable description of a status. Never returns NULL. */
const char *lf_status_string(lf_status status);

/* Details of the last failure on the calling thread. Never returns NULL. */
const char *lf_last_error(void);

/* Library version as "MAJOR.MINOR.PATCH". Never returns NULL. */
const char *lf_version_string(void);

/* ---- File classification ------------------------------------------------ */

typedef enum lf_file_kind {
    LF_KIND_TEXT = 0,
    LF_KIND_BINARY = 1,
} lf_file_kind;

typedef enum lf_encoding {
    LF_ENCODING_UTF8 = 0,
    LF_ENCODING_UTF8_BOM = 1,
    LF_ENCODING_UTF16LE = 2,
    LF_ENCODING_UTF16BE = 3,
} lf_encoding;

typedef enum lf_eol {
    LF_EOL_NONE = 0, /* no line terminator at all */
    LF_EOL_LF = 1,
    LF_EOL_CRLF = 2,
    LF_EOL_MIXED = 3,
} lf_eol;

typedef struct lf_text_info {
    lf_file_kind kind;
    lf_encoding encoding;
    uint32_t bom_length; /* bytes of byte-order mark at the start, 0 if none */
} lf_text_info;

/*
 * Classifies a buffer: binary (NUL byte in the first 8000 bytes, or UTF-32),
 * or text with a detected encoding. Pure function, never fails.
 */
lf_text_info lf_detect_text(const uint8_t *data, size_t length);

/* Classifies a file by reading only its first 8000 bytes. */
lf_status lf_probe_file(const char *path, lf_text_info *out);

/* ---- Documents ---------------------------------------------------------- */

typedef struct lf_doc lf_doc;

typedef struct lf_open_options {
    uint32_t marker_size; /* 0 means LF_DEFAULT_MARKER_SIZE */
} lf_open_options;

typedef struct lf_doc_info {
    uint64_t size;             /* bytes of the (UTF-8) text the document works on */
    uint64_t line_count;
    uint64_t conflict_count;
    uint64_t unresolved_count;
    lf_encoding encoding;
    lf_eol eol;
    uint32_t marker_size;
} lf_doc_info;

typedef enum lf_choice {
    LF_CHOICE_UNRESOLVED = 0,
    LF_CHOICE_CURRENT = 1,
    LF_CHOICE_INCOMING = 2,
    LF_CHOICE_BOTH_CURRENT_FIRST = 3,
    LF_CHOICE_BOTH_INCOMING_FIRST = 4,
    LF_CHOICE_BASE = 5,
    LF_CHOICE_CUSTOM = 6,
} lf_choice;

typedef struct lf_range {
    uint64_t offset;
    uint64_t length;
} lf_range;

typedef struct lf_conflict_info {
    uint64_t open_line;      /* 1-based line of "<<<<<<<" */
    uint64_t base_line;      /* line of "|||||||", 0 when there is no base section */
    uint64_t separator_line; /* line of "=======" */
    uint64_t close_line;     /* line of ">>>>>>>" */
    lf_range region;         /* whole conflict, marker lines included */
    lf_range current;        /* content only, without marker lines */
    lf_range base;
    lf_range incoming;
    lf_range current_label;  /* text after "<<<<<<< " */
    lf_range incoming_label; /* text after ">>>>>>> " */
    lf_choice choice;
    int has_base;
    int has_custom;
} lf_conflict_info;

/* Flags for lf_doc_save. */
#define LF_SAVE_FORCE 1u          /* write unresolved conflicts back verbatim instead of failing */
#define LF_SAVE_IGNORE_CHANGES 2u /* save even if the source file changed since it was opened */

/*
 * Opens a text file, indexes its lines and scans for conflicts in one pass.
 * Large files are memory-mapped, so memory use stays small.
 * Fails with LF_ERR_UNSUPPORTED for binary files and LF_ERR_MALFORMED for
 * broken conflict markers (the message names the line).
 */
lf_status lf_doc_open(const char *path, const lf_open_options *options, lf_doc **out);

/* Releases a document. Accepts NULL. */
void lf_doc_close(lf_doc *doc);

lf_status lf_doc_get_info(const lf_doc *doc, lf_doc_info *out);

/* The UTF-8 text the document's offsets refer to. Valid until lf_doc_close. */
const uint8_t *lf_doc_data(const lf_doc *doc, uint64_t *length);

/* Byte offset of the start of a 1-based line; line_count + 1 yields the end of file. */
lf_status lf_doc_line_offset(const lf_doc *doc, uint64_t line, uint64_t *offset);

lf_status lf_doc_get_conflict(const lf_doc *doc, uint64_t index, lf_conflict_info *out);

/* Chooses how a conflict is resolved. LF_CHOICE_BASE needs a diff3 base section. */
lf_status lf_doc_set_choice(lf_doc *doc, uint64_t index, lf_choice choice);

/* Applies one choice to every conflict. LF_CHOICE_BASE fails if any conflict has no base. */
lf_status lf_doc_set_choice_all(lf_doc *doc, lf_choice choice);

/* Replaces a conflict with caller-supplied text (copied) and selects LF_CHOICE_CUSTOM. */
lf_status lf_doc_set_custom(lf_doc *doc, uint64_t index, const uint8_t *data, size_t length);

/*
 * Writes the resolved file atomically (temporary file, fsync, rename), keeping
 * the original permissions, encoding, byte-order mark and line endings. A symlink
 * destination is followed, so the link itself is kept. (Extended attributes, ACLs and
 * hard links of the old file are not carried over.)
 * dest_path may be NULL to replace the source file. Fails, leaving the destination
 * untouched, with LF_ERR_UNRESOLVED if conflicts remain and LF_SAVE_FORCE is not set,
 * and with LF_ERR_CHANGED if the source file was modified since lf_doc_open (its
 * offsets would be stale) and LF_SAVE_IGNORE_CHANGES is not set.
 * Custom text is given a line terminator if it lacks one. After a successful save the
 * document remembers the new state of the source file, so it can be saved again.
 */
lf_status lf_doc_save(lf_doc *doc, const char *dest_path, uint32_t flags);

/* ---- Semantic merge of Xcode project files ----------------------------- */

typedef struct lf_merge_options {
    uint32_t marker_size;       /* 0 means LF_DEFAULT_MARKER_SIZE */
    int include_base;           /* write a "|||||||" base section in conflicts (diff3 style) */
    const char *current_label;  /* NULL means "HEAD" */
    const char *base_label;     /* NULL means "base" */
    const char *incoming_label; /* NULL means "incoming" */
} lf_merge_options;

typedef struct lf_merge_result {
    uint8_t *data; /* merged file, owned: release with lf_merge_result_free */
    size_t length;
    uint64_t conflict_count;      /* conflict blocks written with markers */
    uint64_t merged_object_count; /* objects changed on both sides and merged without conflict */
} lf_merge_result;

/*
 * Three-way merge of project.pbxproj contents (base = common ancestor).
 *
 * Objects are matched by ID. An object changed on one side takes that side's text verbatim;
 * objects changed on both sides are merged field by field (nested dictionaries key by key,
 * lists of IDs as ordered sets). Real disagreements become small conflict blocks around the
 * object or the setting, so each side stays a valid project when picked. A deletion that the
 * other side still references becomes a conflict instead of a dangling reference.
 *
 * Fails with LF_ERR_UNSUPPORTED (and changes nothing) when an input is not a project file
 * written in Xcode's format; callers should then fall back to a line-based merge.
 * options may be NULL (diff3 style, default labels and marker size).
 */
lf_status lf_pbx_merge(const uint8_t *base, size_t base_length, const uint8_t *ours, size_t ours_length,
                       const uint8_t *theirs, size_t theirs_length, const lf_merge_options *options,
                       lf_merge_result *out);

/* Releases the merged text. Accepts a zeroed or already-freed result. */
void lf_merge_result_free(lf_merge_result *result);

#ifdef __cplusplus
}
#endif

#endif /* LFCORE_H */
