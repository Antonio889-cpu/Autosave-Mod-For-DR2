// Reader for the game's savedata.vfs: [u32 nameLen][name][u32 size][data]... ended by 0xDEADBEEF.
#pragma once
#include <string.h>

#define AUTOSAVE_MARK "DR2 Autosave"

// 1 if the autosave may write this entry: it is absent or was written by the mod.
// A malformed file returns 0, so the mod never overwrites what it cannot read.
static int vfs_entry_writable(const unsigned char *d, size_t n, const char *entry)
{
    size_t o = 0, want = strlen(entry), mark = strlen(AUTOSAVE_MARK);
    while (n - o >= 4) {
        unsigned nameLen, size;
        memcpy(&nameLen, d + o, 4);
        if (nameLen == 0xDEADBEEF) return 1;
        if (nameLen == 0 || nameLen > 64 || n - o - 4 < (size_t)nameLen + 4) return 0;
        memcpy(&size, d + o + 4 + nameLen, 4);
        o += 8 + (size_t)nameLen;
        if (size > n - o) return 0;
        if (nameLen == want && !memcmp(d + o - 4 - nameLen, entry, want))
            return size >= mark && !memcmp(d + o, AUTOSAVE_MARK, mark);
        o += size;
    }
    return o == n;
}
