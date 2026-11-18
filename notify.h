// Small click-through banner shown over the game window. It is a separate window,
// so it never touches the game's OpenGL state.
#pragma once
#include <windows.h>

#define WM_NOTIFY_SHOW (WM_APP + 1)

static HWND notify_wnd;
static const wchar_t *notify_text = L"";
static int notify_alpha, notify_hold;

static BOOL CALLBACK find_game_cb(HWND w, LPARAM out)
{
    DWORD pid;
    GetWindowThreadProcessId(w, &pid);
    if (pid != GetCurrentProcessId() || w == notify_wnd || !IsWindowVisible(w) || GetWindow(w, GW_OWNER)) return TRUE;
    *(HWND *)out = w;
    return FALSE;
}

static HWND find_game_window(void)
{
    HWND w = NULL;
    EnumWindows(find_game_cb, (LPARAM)&w);
    return w;
}

static LRESULT CALLBACK notify_proc(HWND w, UINT msg, WPARAM wp, LPARAM lp)
{
    enum { W = 250, H = 46 };
    switch (msg) {
    case WM_NOTIFY_SHOW: {
        notify_text = (const wchar_t *)lp;
        RECT r = { 0, 0, 800, 600 };
        HWND game = find_game_window();
        if (game) {
            GetClientRect(game, &r);
            MapWindowPoints(game, NULL, (POINT *)&r, 2);
        }
        notify_alpha = 0;
        notify_hold = 90; // 30 ms ticks
        SetLayeredWindowAttributes(w, 0, 0, LWA_ALPHA);
        SetWindowPos(w, HWND_TOPMOST, r.right - W - 24, r.top + 24, W, H, SWP_NOACTIVATE | SWP_SHOWWINDOW);
        InvalidateRect(w, NULL, TRUE);
        SetTimer(w, 1, 30, NULL);
        return 0;
    }
    case WM_TIMER:
        if (notify_hold > 0 && notify_alpha < 235) notify_alpha += 40;
        else if (notify_hold > 0) notify_hold--;
        else notify_alpha -= 20;
        if (notify_alpha > 235) notify_alpha = 235;
        if (notify_alpha <= 0) {
            KillTimer(w, 1);
            ShowWindow(w, SW_HIDE);
            return 0;
        }
        SetLayeredWindowAttributes(w, 0, (BYTE)notify_alpha, LWA_ALPHA);
        return 0;
    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(w, &ps);
        RECT all = { 0, 0, W, H }, accent = { 0, 0, 8, H }, text = { 22, 0, W - 8, H };
        HBRUSH dark = CreateSolidBrush(RGB(17, 17, 20)), pink = CreateSolidBrush(RGB(240, 20, 110));
        FillRect(dc, &all, dark);
        FillRect(dc, &accent, pink);
        DeleteObject(dark);
        DeleteObject(pink);
        HFONT font = CreateFontW(-19, 0, 0, 0, FW_BOLD, TRUE, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
        HGDIOBJ old = SelectObject(dc, font);
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, RGB(255, 255, 255));
        DrawTextW(dc, notify_text, -1, &text, DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);
        SelectObject(dc, old);
        DeleteObject(font);
        EndPaint(w, &ps);
        return 0;
    }
    }
    return DefWindowProcW(w, msg, wp, lp);
}

static DWORD WINAPI notify_thread(void *ready)
{
    WNDCLASSW wc = { 0 };
    wc.lpfnWndProc = notify_proc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"DR2AutosaveNotify";
    RegisterClassW(&wc);
    notify_wnd = CreateWindowExW(WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
                                 wc.lpszClassName, L"", WS_POPUP, 0, 0, 10, 10, NULL, NULL, wc.hInstance, NULL);
    SetEvent((HANDLE)ready);
    MSG m;
    while (GetMessageW(&m, NULL, 0, 0) > 0) DispatchMessageW(&m);
    return 0;
}

static void notify_start(void)
{
    HANDLE ready = CreateEventW(NULL, TRUE, FALSE, NULL);
    HANDLE t = ready ? CreateThread(NULL, 0, notify_thread, ready, 0, NULL) : NULL;
    if (t) {
        WaitForSingleObject(ready, 3000);
        CloseHandle(t);
    }
    if (ready) CloseHandle(ready);
}

// Never blocks the game thread.
static void notify_show(const wchar_t *text)
{
    if (notify_wnd) PostMessageW(notify_wnd, WM_NOTIFY_SHOW, 0, (LPARAM)text);
}
