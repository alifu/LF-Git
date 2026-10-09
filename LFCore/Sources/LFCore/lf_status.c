#include "lfcore.h"

#define LF_STRINGIFY_(x) #x
#define LF_STRINGIFY(x) LF_STRINGIFY_(x)

const char *lf_status_string(lf_status status) {
    switch (status) {
    case LF_OK:
        return "ok";
    case LF_ERR_INVALID_ARGUMENT:
        return "invalid argument";
    case LF_ERR_IO:
        return "i/o error";
    case LF_ERR_NO_MEMORY:
        return "out of memory";
    case LF_ERR_MALFORMED:
        return "malformed conflict markers";
    case LF_ERR_UNRESOLVED:
        return "unresolved conflicts remain";
    case LF_ERR_UNSUPPORTED:
        return "unsupported file";
    case LF_ERR_CHANGED:
        return "file changed on disk";
    }
    return "unknown status";
}

const char *lf_version_string(void) {
    return LF_STRINGIFY(LF_VERSION_MAJOR) "." LF_STRINGIFY(LF_VERSION_MINOR) "." LF_STRINGIFY(LF_VERSION_PATCH);
}
