#include "lf_internal.h"

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#define LF_ERROR_CAPACITY 512
#define LF_ERRNO_TEXT_CAPACITY 128

static _Thread_local char lf_error_buffer[LF_ERROR_CAPACITY];

lf_status lf_fail(lf_status status, const char *format, ...) {
    va_list args;
    va_start(args, format);
    vsnprintf(lf_error_buffer, sizeof lf_error_buffer, format, args);
    va_end(args);
    return status;
}

lf_status lf_fail_errno(lf_status status, const char *action, const char *path) {
    const int saved_errno = errno;
    char text[LF_ERRNO_TEXT_CAPACITY];
    if (strerror_r(saved_errno, text, sizeof text) != 0) {
        snprintf(text, sizeof text, "error %d", saved_errno);
    }
    return lf_fail(status, "cannot %s '%s': %s", action, path, text);
}

const char *lf_last_error(void) {
    return lf_error_buffer;
}
