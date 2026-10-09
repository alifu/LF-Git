#include "lf_internal.h"

#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

lf_status lf_map_file(const char *path, lf_mapping *out) {
    out->base = NULL;
    out->length = 0;
    out->mode = 0;

    const int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return lf_fail_errno(LF_ERR_IO, "open", path);
    }
    struct stat info;
    if (fstat(fd, &info) != 0) {
        const lf_status status = lf_fail_errno(LF_ERR_IO, "stat", path);
        close(fd);
        return status;
    }
    if (!S_ISREG(info.st_mode)) {
        close(fd);
        return lf_fail(LF_ERR_INVALID_ARGUMENT, "'%s' is not a regular file", path);
    }
    out->mode = (uint32_t)(info.st_mode & 07777);
    out->length = (size_t)info.st_size;
    if (info.st_size > 0) {
        void *base = mmap(NULL, out->length, PROT_READ, MAP_PRIVATE, fd, 0);
        if (base == MAP_FAILED) {
            const lf_status status = lf_fail_errno(LF_ERR_IO, "map", path);
            close(fd);
            out->length = 0;
            return status;
        }
        madvise(base, out->length, MADV_SEQUENTIAL);
        out->base = base;
    }
    close(fd);
    return LF_OK;
}

void lf_unmap(lf_mapping *mapping) {
    if (mapping->base != NULL) {
        munmap(mapping->base, mapping->length);
    }
    mapping->base = NULL;
    mapping->length = 0;
}
