#include <assert.h>
#include <stdio.h>
#include "vfs.h"

static size_t put(unsigned char *p, const char *name, const char *data, unsigned size)
{
    unsigned n = (unsigned)strlen(name);
    memcpy(p, &n, 4); memcpy(p + 4, name, n); memcpy(p + 4 + n, &size, 4);
    memcpy(p + 8 + n, data, size);
    return 8 + n + size;
}

int main(void)
{
    unsigned char f[256];
    unsigned end = 0xDEADBEEF;
    size_t o = put(f, "data0000.bin", "Danganronpa 2 save", 18);
    o += put(f + o, "data0027.bin", AUTOSAVE_MARK " x", 14);
    o += put(f + o, "data0028.bin", "Danganronpa 2 save", 18);
    memcpy(f + o, &end, 4); o += 4;

    assert(vfs_entry_writable(f, o, "data0027.bin") == 1);  // ours
    assert(vfs_entry_writable(f, o, "data0028.bin") == 0);  // the player's
    assert(vfs_entry_writable(f, o, "data0029.bin") == 1);  // empty
    assert(vfs_entry_writable(f, 0, "data0029.bin") == 1);  // empty file
    assert(vfs_entry_writable(f, 20, "data0029.bin") == 0); // truncated

    unsigned huge = 0x7FFFFFFF;
    memcpy(f + 16, &huge, 4);
    assert(vfs_entry_writable(f, o, "data0029.bin") == 0);  // size past end of file
    puts("vfs ok");
    return 0;
}
