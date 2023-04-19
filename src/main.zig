const std = @import("std");
const os = std.os;
const time = std.time;
const windows = os.windows;
const user32 = windows.user32;
const thread = std.Thread;

extern "user32" fn SendInput(c_uint, *INPUT, c_int) c_uint;
extern "user32" fn UnhookWindowsHook(nCode: c_int, pfnFilterProc: HOOKPROC) callconv(std.os.windows.WINAPI) windows.BOOL;
extern "user32" fn SetWindowsHookExW(idHook: c_int, lpfn: HOOKPROC, hmod: ?windows.HINSTANCE, dwThreadId: windows.DWORD) callconv(std.os.windows.WINAPI) windows.HANDLE;
extern "user32" fn CallNextHookEx(windows.HANDLE, c_int, windows.WPARAM, windows.LPARAM) windows.LRESULT;

const HOOKPROC = ?*const fn (c_int, windows.WPARAM, windows.LPARAM) callconv(.C) windows.LRESULT;

const MSLLHOOKSTRUCT = extern struct { pt: windows.POINT, mouseData: windows.DWORD, flags: windows.DWORD, time: windows.DWORD, dwExtraInfo: windows.ULONG_PTR };

const KBDLLHOOKSTRUCT = extern struct {
    vkCode: windows.DWORD,
    scanCode: windows.DWORD,
    flags: windows.DWORD,
    time: windows.DWORD,
    dwExtraInfo: windows.ULONG_PTR,
};

var mhook: windows.HANDLE = undefined;
var khook: windows.HANDLE = undefined;

export fn mouse_callback(code: c_int, wParam: windows.WPARAM, lParam: windows.LPARAM) callconv(std.os.windows.WINAPI) windows.LRESULT {
    var pMouse: [*c]MSLLHOOKSTRUCT = @as([*c]MSLLHOOKSTRUCT, lParam);
    if (wParam != 0x0200 and pMouse.*.flags == 0) {
        if (wParam == 0x201) {
            LEFT_CLICKER.first_click = true;
            LEFT_CLICKER.mouse_down = true;
        } else if (wParam == 0x202) {
            LEFT_CLICKER.mouse_down = false;
        } else if (wParam == 0x204) {
            RIGHT_CLICKER.first_click = true;
            RIGHT_CLICKER.mouse_down = true;
        } else if (wParam == 0x205) {
            RIGHT_CLICKER.mouse_down = false;
        }
    }
    return CallNextHookEx(mhook, code, wParam, lParam);
}

export fn keyboard_callback(code: c_int, wParam: windows.WPARAM, lParam: windows.LPARAM) callconv(std.os.windows.WINAPI) windows.LRESULT {
    var pKeyboard: [*c]KBDLLHOOKSTRUCT = @as([*c]KBDLLHOOKSTRUCT, lParam);
    if (wParam == 0x0101) {
        if (pKeyboard.*.vkCode == LEFT_CLICKER.toggle) {
            LEFT_CLICKER.toggled = !LEFT_CLICKER.toggled;
        } else if (pKeyboard.*.vkCode == RIGHT_CLICKER.toggle) {
            RIGHT_CLICKER.toggled = !RIGHT_CLICKER.toggled;
        }
    }
    return CallNextHookEx(khook, code, wParam, lParam);
}

const MOUSEINPUT = extern struct {
    dx: windows.LONG = 0,
    dy: windows.LONG = 0,
    mouseData: windows.DWORD = 0,
    dwFlags: windows.DWORD,
    time: windows.DWORD = 0,
    dwExtraInfo: windows.ULONG_PTR = 0,
};

const INPUT = extern struct {
    type: u32,
    DUMMYUNIONNAME: extern union {
        mi: MOUSEINPUT,
        //ki: KEYBDINPUT,
        //hi: HARDWAREINPUT,
    },
};

fn send_mouse_input(flags: u32) void {
    var input = INPUT{ .type = 0, .DUMMYUNIONNAME = .{ .mi = MOUSEINPUT{ .dwFlags = flags } } };
    _ = SendInput(1, &input, @sizeOf(INPUT));
}

const Clicker = struct {
    min: u32 = 10,
    max: u32 = 15,
    last_click: time.Instant = .{ .timestamp = 0 },
    toggled: bool = false,
    mouse_down: bool = false,
    first_click: bool = false,
    toggle: u32,
    running: bool = false,
    input_up: u32,
    input_down: u32,

    fn start_clicker_thread(self: *Clicker) void {
        if (self.running)
            return;

        self.running = true;

        while (self.running) {
            if (self.toggled and self.mouse_down) {
                if (self.first_click) {
                    self.first_click = false;
                    time.sleep(time.ns_per_ms * 30);
                } else {
                    var now = time.Instant.now() catch
                        return;
                    if (!(now.since(self.last_click) > time.ns_per_ms * 50))
                        continue;

                    send_mouse_input(self.input_up);
                    send_mouse_input(self.input_down);

                    self.last_click = time.Instant.now() catch
                        return;
                }
            }
            time.sleep(time.ns_per_ms);
        }
    }
};

var LEFT_CLICKER = Clicker{
    .toggle = 0x79,
    .input_up = 0x004,
    .input_down = 0x002,
};

var RIGHT_CLICKER = Clicker{
    .toggle = 0x49,
    .input_up = 0x010,
    .input_down = 0x008,
};

fn clicker(btn: c_int) *Clicker {
    if (btn == 0) {
        return &LEFT_CLICKER;
    } else if (btn == 1) {
        return &RIGHT_CLICKER;
    } else {
        std.debug.panic("should never happen", .{});
    }
}

export fn set_min(btn: c_int, min: u32) void {
    clicker(btn).min = min;
}

export fn set_max(btn: c_int, max: u32) void {
    clicker(btn).max = max;
}

fn start_left_clicker() void {
    clicker(0).start_clicker_thread();
}

fn start_right_clicker() void {
    clicker(1).start_clicker_thread();
}

export fn start_clicker() void {
    _ = thread.spawn(.{}, start_left_clicker, .{}) catch
        return;
    _ = thread.spawn(.{}, start_right_clicker, .{}) catch
        return;

    mhook = SetWindowsHookExW(14, mouse_callback, null, 0);
    khook = SetWindowsHookExW(13, keyboard_callback, null, 0);

    var msg: *user32.MSG = undefined;
    while (user32.GetMessageW(msg, null, 0, 0) == 1) {
        _ = user32.TranslateMessage(msg);
        _ = user32.DispatchMessageW(msg);
    }
}
