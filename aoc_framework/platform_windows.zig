const w = @import("std").os.windows;

extern "kernel32" fn SetConsoleMode(in_hConsoleHandle: w.HANDLE, in_dwMode: w.DWORD) callconv(w.WINAPI) w.BOOL;
const CP_UTF8: w.UINT = 65001;

pub fn init() void {
    _ = w.kernel32.SetConsoleOutputCP(CP_UTF8);
    for ([2]w.DWORD{ w.STD_OUTPUT_HANDLE, w.STD_ERROR_HANDLE }) |handle| {
        const h_console = w.GetStdHandle(handle) catch continue;
        var console_mode: w.DWORD = undefined;
        const getRes = w.kernel32.GetConsoleMode(h_console, &console_mode);
        if (getRes != 0) {
            _ = SetConsoleMode(h_console, console_mode | w.ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        }
    }
}
