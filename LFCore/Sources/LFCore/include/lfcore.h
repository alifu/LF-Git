/*
 * lfcore.h — public C API of the LF-Git merge engine.
 *
 * Conventions:
 *   - Every fallible function returns an lf_status; LF_OK means success.
 *   - Handles are opaque; callers never touch their internals.
 *   - Strings returned by the library are static and must not be freed.
 */
#ifndef LFCORE_H
#define LFCORE_H

#ifdef __cplusplus
extern "C" {
#endif

#define LF_VERSION_MAJOR 0
#define LF_VERSION_MINOR 1
#define LF_VERSION_PATCH 0

typedef enum lf_status {
    LF_OK = 0,
    LF_ERR_INVALID_ARGUMENT = 1,
    LF_ERR_IO = 2,
    LF_ERR_NO_MEMORY = 3,
    LF_ERR_MALFORMED = 4,
    LF_ERR_UNRESOLVED = 5,
    LF_ERR_UNSUPPORTED = 6,
} lf_status;

/* Human-readable description of a status. Never returns NULL. */
const char *lf_status_string(lf_status status);

/* Library version as "MAJOR.MINOR.PATCH". Never returns NULL. */
const char *lf_version_string(void);

#ifdef __cplusplus
}
#endif

#endif /* LFCORE_H */
