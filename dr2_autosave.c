// Autosave for Danganronpa 2: Goodbye Despair (Steam, DR2_us.exe).
// Loaded by the game as d3dx9_43.dll. Saves into the last three slots of the normal save list.
#include <windows.h>
#include <shlobj.h>
#include "vfs.h"
#include "notify.h"

#define SAVE_SIZE 0x37358
#define FIRST_SLOT 27
#define SLOT_COUNT 3

// Addresses of this exact build. ASLR is on, so every one goes through R().
#define R(a) (base + ((a) - 0x400000))
#define U8(a) (*(unsigned char *)R(a))
#define U16(a) (*(unsigned short *)R(a))
#define U32(a) (*(unsigned *)R(a))
#define PTR(a) (*(unsigned char **)R(a))

static unsigned char *base;
static void *orig_gameplay_menu_check;
static int slot_ok[SLOT_COUNT], next_slot;
static unsigned char save_buf[SAVE_SIZE];
static DWORD interval_ms = 5 * 60 * 1000;
static int show_notification = 1, keep_backups = 1;
static wchar_t backup_dir[MAX_PATH], save_dir[MAX_PATH];
static const wchar_t *const save_files[] = { L"savedata.vfs", L"savedata_jp.vfs", L"savedata_ch.vfs" };

static void game_file(wchar_t *path, const wchar_t *name)
{
    DWORD n = GetModuleFileNameW(NULL, path, MAX_PATH);
    while (n && path[n - 1] != L'\\') n--;
    lstrcpyW(path + n, name);
}

static void log_line(const char *text)
{
    wchar_t path[MAX_PATH];
    DWORD written;
    game_file(path, L"dr2_autosave.log");
    HANDLE f = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ, NULL, OPEN_ALWAYS, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) return;
    SYSTEMTIME t;
    char line[200];
    GetLocalTime(&t);
    int len = wsprintfA(line, "%02d:%02d:%02d %s\r\n", t.wHour, t.wMinute, t.wSecond, text);
    WriteFile(f, line, len, &written, NULL);
    CloseHandle(f);
}

// Same conditions the game checks before opening the pause menu and enabling its Save entry.
static int can_save(void)
{
    if (U32(0x7B67A8) || U32(0x7B6AC0)) return 0; // a save or the save screen is active
    if (!((int(__cdecl *)(void))R(0x426690))()) return 0;
    if (((char(__cdecl *)(void))R(0x46F850))()) return 0;
    if ((U8(0x78A114) >> 4) & 1 || U8(0x7A9761) == 1) return 0;

    unsigned flags = U32(0x78A2F8);
    if ((flags >> 7) & 1 || (flags >> 9) & 1 || (flags >> 12) & 1) return 0;
    if ((flags >> 2) & 1) {
        short v = *(short *)(PTR(0x7A7314) + 0x4C4);
        if (v < 5 || v >= 200) return 0;
    }
    if (U32(0x7A3AFC)) return 0;

    unsigned char *game = PTR(0x7A8240);
    if (game[1] == 1 && *(unsigned short *)(game + 0xECF8) == 100) return 0;
    if (game[0xECE0]) return 0;

    unsigned mode = *(unsigned *)(game + 0xE754);
    if (mode && (game[0xE751] == 3 || (mode != 5 && mode != 15))) return 0;

    unsigned char *ev = PTR(0x7196A8);
    if (ev && (U32(0x78A2FC) >> 12) & 1 && *(unsigned short *)(ev + 2) != 100) return 0;

    unsigned short room = U16(0x7A39C2);
    if (room == 0x6E || room == 0x262 || room == 0x1CC) return 0;
    if (!((U8(0x78A114) >> 1) & 1 || U8(0x78A2F6) & 1 || (flags >> 2) & 1 || mode == 5)) return 0;
    if (U8(0x7A83F3) == 4 || !(U8(0x78A2B4) & 0x10)) return 0;

    return ((char(__cdecl *)(void))R(0x48F1F0))() != 0;
}

// Keeps the five most recent copies of the save file, replacing the oldest.
static void backup_saves(void)
{
    for (int i = 0; i < 3; i++) {
        wchar_t src[MAX_PATH], dst[MAX_PATH], oldest[MAX_PATH] = L"";
        FILETIME oldest_time = { 0xFFFFFFFF, 0x7FFFFFFF };
        wsprintfW(src, L"%s%s", save_dir, save_files[i]);
        if (GetFileAttributesW(src) == INVALID_FILE_ATTRIBUTES) continue;
        for (int n = 1; n <= 5; n++) {
            WIN32_FILE_ATTRIBUTE_DATA info;
            wsprintfW(dst, L"%s%s.%d.bak", backup_dir, save_files[i], n);
            if (!GetFileAttributesExW(dst, GetFileExInfoStandard, &info)) {
                lstrcpyW(oldest, dst);
                break;
            }
            if (CompareFileTime(&info.ftLastWriteTime, &oldest_time) < 0) {
                oldest_time = info.ftLastWriteTime;
                lstrcpyW(oldest, dst);
            }
        }
        if (!CopyFileW(src, oldest, FALSE)) log_line("warning: could not back up the save file");
        else { // CopyFile keeps the source date, which would break the oldest-first order
            HANDLE f = CreateFileW(oldest, FILE_WRITE_ATTRIBUTES, 0, NULL, OPEN_EXISTING, 0, NULL);
            if (f != INVALID_HANDLE_VALUE) {
                FILETIME now;
                GetSystemTimeAsFileTime(&now);
                SetFileTime(f, NULL, NULL, &now);
                CloseHandle(f);
            }
        }
    }
}

static void do_save(void)
{
    int slot = -1;
    for (int i = 0; i < SLOT_COUNT && slot < 0; i++, next_slot = (next_slot + 1) % SLOT_COUNT)
        if (slot_ok[next_slot]) slot = FIRST_SLOT + next_slot;
    if (slot < 0) return;
    if (keep_backups) backup_saves();

    // Same steps as the game's own save, without its menu.
    ((void(__cdecl *)(int, int))R(0x431DF0))(U8(0x752DB2), 1);
    ((void(__cdecl *)(void *))R(0x4EEE80))(R(0x752D9C));
    ((void(__cdecl *)(void *))R(0x432F80))(R(0x752D88));
    ((void(__cdecl *)(void *))R(0x432EA0))(R(0x752DC8));
    memcpy(save_buf, R(0x752D88), 0x40);
    memcpy(save_buf + 0x40, R(0x752DC8), 0x37318);

    char sub[0x80] = "[AUTO] ", chapter[0x80] = {0};
    ((void(__cdecl *)(char *, int))R(0x433220))(chapter, sizeof chapter);
    chapter[sizeof chapter - 1] = 0;
    int len = lstrlenA(chapter), room = (int)sizeof sub - 8;
    if (len > room) { // cut on a UTF-8 character boundary
        len = room;
        while (len && (chapter[len] & 0xC0) == 0x80) len--;
    }
    memcpy(sub + 7, chapter, len);
    sub[7 + len] = 0;

    memset(R(0x7B67A8), 0, 0x314);
    U32(0x7B67AC) = SAVE_SIZE;
    *(void **)R(0x7B67B0) = save_buf;
    U32(0x7B67A8) = 1;
    U32(0x7B67C0) = 1;
    lstrcpyA((char *)R(0x7B67C4), AUTOSAVE_MARK);
    lstrcpyA((char *)R(0x7B6804), sub);
    ((void(__cdecl *)(void *, int))R(0x433040))(R(0x7B6884), 0x200);
    SYSTEMTIME t;
    GetLocalTime(&t);
    wsprintfA((char *)R(0x7B6A84), "%02d.%02d.%04d/%02d.%02d.%02d",
              t.wDay, t.wMonth, t.wYear, t.wHour, t.wMinute, t.wSecond);

    ((int(__cdecl *)(int, int))R(0x511700))(0, slot);
    int result = (int)U32(0x7B67B8);
    U32(0x7B67A8) = 0;
    U32(0x7B67B4) = 0; // so tick() does not mistake this write for a manual save

    char msg[80];
    wsprintfA(msg, "autosave slot %d: %s (%d)", slot + 1, result ? "FAILED" : "ok", result);
    log_line(msg);
    if (result) notify_show(L"Autosave failed");
    else if (show_notification) notify_show(L"Autosaved");
}

static void __cdecl tick(void)
{
    static DWORD next;
    static int armed;

    // The player saved by hand into a slot we rotate through: that slot is theirs now.
    int manual = (int)U32(0x7B67B4) - FIRST_SLOT;
    if (U32(0x7B6AC4) == 1 && manual >= 0 && manual < SLOT_COUNT && slot_ok[manual]) {
        slot_ok[manual] = 0;
        log_line("a manual save now uses one of the autosave slots: slot skipped");
    }

    DWORD now = GetTickCount();
    if (!armed) { armed = 1; next = now + interval_ms; return; }
    if ((LONG)(now - next) < 0 || !can_save()) return;
    next = now + interval_ms;
    do_save();
}

// The engine may rely on registers across its own calls, so all of them are preserved.
static __declspec(naked) void hook(void)
{
    __asm {
        pushad
        pushfd
        cld
        call tick
        popfd
        popad
        jmp orig_gameplay_menu_check
    }
}

static void scan_slots(void)
{
    wchar_t path[MAX_PATH];
    for (int s = 0; s < SLOT_COUNT; s++) slot_ok[s] = 1;
    if (FAILED(SHGetFolderPathW(NULL, CSIDL_PERSONAL, NULL, 0, save_dir))) {
        for (int s = 0; s < SLOT_COUNT; s++) slot_ok[s] = 0;
        return;
    }
    lstrcatW(save_dir, L"\\My Games\\Danganronpa2\\");
    wsprintfW(backup_dir, L"%sAutosaveBackups\\", save_dir);
    CreateDirectoryW(backup_dir, NULL);

    for (int i = 0; i < 3; i++) {
        wsprintfW(path, L"%s%s", save_dir, save_files[i]);
        HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
        if (f == INVALID_HANDLE_VALUE) continue;

        wchar_t bak[MAX_PATH];
        wsprintfW(bak, L"%s%s.pre-autosave", backup_dir, save_files[i]);
        CopyFileW(path, bak, TRUE); // first run only: keeps the saves as they were before the mod

        DWORD size = GetFileSize(f, NULL), got = 0;
        unsigned char *d = size <= 64 << 20 ? HeapAlloc(GetProcessHeap(), 0, size + 1) : NULL;
        BOOL read = d && ReadFile(f, d, size, &got, NULL) && got == size;
        for (int s = 0; s < SLOT_COUNT; s++) {
            char entry[16];
            wsprintfA(entry, "data%04d.bin", FIRST_SLOT + s);
            if (!read || !vfs_entry_writable(d, size, entry)) slot_ok[s] = 0;
        }
        if (d) HeapFree(GetProcessHeap(), 0, d);
        CloseHandle(f);
    }
}

static DWORD WINAPI setup(void *unused)
{
    (void)unused;
    wchar_t exe[MAX_PATH], ini[MAX_PATH];
    GetModuleFileNameW(NULL, exe, MAX_PATH);
    int exe_len = lstrlenW(exe);
    if (exe_len < 10 || lstrcmpiW(exe + exe_len - 10, L"DR2_us.exe")) return 0; // e.g. the game's launcher

    // The window appears only after the Steam stub has handed control to the game.
    for (int waited = 0; !find_game_window(); waited++) {
        if (waited > 1200) { log_line("game window not found: autosave disabled"); return 0; }
        Sleep(100);
    }

    game_file(ini, L"dr2_autosave.ini");
    UINT minutes = GetPrivateProfileIntW(L"Autosave", L"IntervalMinutes", 5, ini);
    interval_ms = (minutes < 1 ? 1 : minutes > 120 ? 120 : minutes) * 60000;
    show_notification = GetPrivateProfileIntW(L"Autosave", L"ShowNotification", 1, ini) != 0;
    keep_backups = GetPrivateProfileIntW(L"Autosave", L"KeepBackups", 1, ini) != 0;

    base = (unsigned char *)GetModuleHandleW(NULL);
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    unsigned char *site = R(0x48E517);
    if (nt->FileHeader.TimeDateStamp != 0x57C6D776 || nt->OptionalHeader.SizeOfImage != 0x489000 ||
        site[0] != 0xE8 || site + 5 + *(int *)(site + 1) != R(0x48DB60)) {
        log_line("unsupported game version: autosave disabled");
        return 0;
    }

    scan_slots();
    if (!slot_ok[0] && !slot_ok[1] && !slot_ok[2]) {
        log_line("slots 28-30 hold your own saves: autosave disabled");
        return 0;
    }

    orig_gameplay_menu_check = R(0x48DB60);
    DWORD old;
    if (!VirtualProtect(site + 1, 4, PAGE_EXECUTE_READWRITE, &old)) {
        log_line("could not install the hook: autosave disabled");
        return 0;
    }
    *(int *)(site + 1) = (int)((unsigned char *)hook - (site + 5));
    VirtualProtect(site + 1, 4, old, &old);
    FlushInstructionCache(GetCurrentProcess(), site, 5);
    notify_start();
    char msg[80];
    wsprintfA(msg, "autosave active: every %u min, notification %d, backups %d",
              interval_ms / 60000, show_notification, keep_backups);
    log_line(msg);
    return 0;
}

// The one function the game imports from the real d3dx9_43.dll.
__declspec(dllexport) HRESULT WINAPI D3DXCompileShader(void *a, UINT b, void *c, void *d, void *e,
                                                       void *f, DWORD g, void *h, void *i, void *j)
{
    typedef HRESULT(WINAPI * Fn)(void *, UINT, void *, void *, void *, void *, DWORD, void *, void *, void *);
    static Fn real;
    if (!real) {
        wchar_t path[MAX_PATH];
        GetSystemDirectoryW(path, MAX_PATH);
        lstrcatW(path, L"\\d3dx9_43.dll");
        HMODULE m = LoadLibraryW(path);
        real = m ? (Fn)GetProcAddress(m, "D3DXCompileShader") : NULL;
        if (!real) return E_FAIL;
    }
    return real(a, b, c, d, e, f, g, h, i, j);
}

BOOL WINAPI DllMain(HINSTANCE dll, DWORD reason, void *reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(dll);
        HANDLE t = CreateThread(NULL, 0, setup, NULL, 0, NULL);
        if (t) CloseHandle(t);
    }
    return TRUE;
}
