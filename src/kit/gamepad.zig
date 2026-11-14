//! 手柄后端：Linux `/dev/input/js*`、Windows 动态加载 XInput、虚拟/探针注入。
const builtin = @import("builtin");
const std = @import("std");
const pad_logic = @import("pad_logic.zig");

pub const RawEvent = struct {
    is_axis: bool,
    index: u8,
    value: f32,
};

var mapping: pad_logic.Mapping = pad_logic.Mapping.xpad;
var tuning: pad_logic.Tuning = .{};
var logical_state: pad_logic.Logical = .{};

var phys_raw: pad_logic.RawState = .{};
var virt_buttons: [pad_logic.button_count]bool = .{false} ** pad_logic.button_count;
var virt_axes: [pad_logic.axis_count]f32 = .{0} ** pad_logic.axis_count;
var virt_active: bool = false;

var is_connected: bool = false;
var allow_hardware: bool = true;
var device_name_buf: [64]u8 = undefined;
var device_name_len: usize = 0;
var scan_timer: f32 = 1.0; // 首帧立即扫描一次
var last_raw_evt: ?RawEvent = null;

// ------------------------------------------------------------------ Linux js* 后端
const linux_backend = if (builtin.os.tag == .linux) struct {
    const JsEvent = extern struct {
        time: u32,
        value: i16,
        type: u8,
        number: u8,
    };

    var fd: std.os.linux.fd_t = -1;

    fn closeDev() void {
        if (fd >= 0) {
            _ = std.os.linux.close(fd);
            fd = -1;
        }
        is_connected = false;
        device_name_len = 0;
        phys_raw = .{};
    }

    fn tryOpen() void {
        var path_buf: [32]u8 = undefined;
        for (0..8) |i| {
            const path = std.fmt.bufPrintZ(&path_buf, "/dev/input/js{d}", .{i}) catch continue;
            const rc = std.os.linux.open(path.ptr, .{ .ACCMODE = .RDONLY, .NONBLOCK = true }, 0);
            if (std.os.linux.errno(rc) != .SUCCESS) continue;
            fd = @intCast(rc);
            is_connected = true;
            const label = std.fmt.bufPrint(&device_name_buf, "js{d}", .{i}) catch "js";
            device_name_len = label.len;
            phys_raw = .{ .n_buttons = 16, .n_axes = 8 };
            // 扳机轴在收到首个事件前记为 -1
            if (mapping.axis[@intFromEnum(pad_logic.Axis.lt)] >= 0) {
                const idx: usize = @intCast(mapping.axis[@intFromEnum(pad_logic.Axis.lt)]);
                if (idx < phys_raw.axes.len) phys_raw.axes[idx] = -1.0;
            }
            if (mapping.axis[@intFromEnum(pad_logic.Axis.rt)] >= 0) {
                const idx: usize = @intCast(mapping.axis[@intFromEnum(pad_logic.Axis.rt)]);
                if (idx < phys_raw.axes.len) phys_raw.axes[idx] = -1.0;
            }
            return;
        }
    }

    fn pollEvents() void {
        if (fd < 0) return;
        var ev: JsEvent = undefined;
        var reads: usize = 0;
        while (reads < 256) : (reads += 1) {
            const bytes = std.mem.asBytes(&ev);
            const n = std.posix.read(fd, bytes) catch |err| switch (err) {
                error.WouldBlock => break,
                else => {
                    closeDev();
                    return;
                },
            };
            if (n == 0) {
                closeDev();
                return;
            }
            if (n != @sizeOf(JsEvent)) break;

            const kind = ev.type & 0x7F;
            const is_init = (ev.type & 0x80) != 0;
            if (kind == 1) {
                // Button
                if (ev.number < phys_raw.buttons.len) {
                    if (ev.number + 1 > phys_raw.n_buttons) phys_raw.n_buttons = ev.number + 1;
                    const down = ev.value != 0;
                    phys_raw.buttons[ev.number] = down;
                    if (!is_init and down) {
                        last_raw_evt = .{ .is_axis = false, .index = ev.number, .value = 1.0 };
                    }
                }
            } else if (kind == 2) {
                // Axis
                if (ev.number < phys_raw.axes.len) {
                    if (ev.number + 1 > phys_raw.n_axes) phys_raw.n_axes = ev.number + 1;
                    const f: f32 = if (ev.value < 0)
                        @as(f32, @floatFromInt(ev.value)) / 32768.0
                    else
                        @as(f32, @floatFromInt(ev.value)) / 32767.0;
                    phys_raw.axes[ev.number] = f;
                    if (!is_init and @abs(f) > 0.5) {
                        last_raw_evt = .{ .is_axis = true, .index = ev.number, .value = f };
                    }
                }
            }
        }
    }
} else struct {
    fn tryOpen() void {}
    fn pollEvents() void {}
};

// ------------------------------------------------------------------ Windows XInput 后端
const windows_backend = if (builtin.os.tag == .windows) struct {
    const XINPUT_GAMEPAD = extern struct {
        wButtons: u16,
        bLeftTrigger: u8,
        bRightTrigger: u8,
        sThumbLX: i16,
        sThumbLY: i16,
        sThumbRX: i16,
        sThumbRY: i16,
    };
    const XINPUT_STATE = extern struct {
        dwPacketNumber: u32,
        Gamepad: XINPUT_GAMEPAD,
    };
    const XInputGetStateFn = *const fn (u32, *XINPUT_STATE) callconv(.winapi) u32;

    var loaded: bool = false;
    var get_state_fn: ?XInputGetStateFn = null;
    var active_slot: ?u32 = null;

    extern "kernel32" fn LoadLibraryA(lpLibFileName: [*:0]const u8) callconv(.winapi) ?std.os.windows.HMODULE;
    extern "kernel32" fn GetProcAddress(hModule: std.os.windows.HMODULE, lpProcName: [*:0]const u8) callconv(.winapi) ?std.os.windows.FARPROC;

    fn ensureLoaded() void {
        if (loaded) return;
        loaded = true;
        const dlls = [_][*:0]const u8{ "xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll" };
        for (dlls) |dll| {
            if (LoadLibraryA(dll)) |mod| {
                if (GetProcAddress(mod, "XInputGetState")) |proc| {
                    get_state_fn = @ptrCast(@alignCast(proc));
                    return;
                }
            }
        }
    }

    fn normThumb(v: i16) f32 {
        return if (v < 0) @as(f32, @floatFromInt(v)) / 32768.0 else @as(f32, @floatFromInt(v)) / 32767.0;
    }

    fn applyState(st: *const XINPUT_STATE) void {
        const gp = st.Gamepad;
        phys_raw.n_buttons = 16;
        phys_raw.n_axes = 8;
        const w = gp.wButtons;
        // Map XInput bits to xpad indices: 0 A, 1 B, 2 X, 3 Y, 4 LB, 5 RB, 6 Back, 7 Start, 9 L3, 10 R3
        phys_raw.buttons[0] = (w & 0x1000) != 0;
        phys_raw.buttons[1] = (w & 0x2000) != 0;
        phys_raw.buttons[2] = (w & 0x4000) != 0;
        phys_raw.buttons[3] = (w & 0x8000) != 0;
        phys_raw.buttons[4] = (w & 0x0100) != 0;
        phys_raw.buttons[5] = (w & 0x0200) != 0;
        phys_raw.buttons[6] = (w & 0x0020) != 0;
        phys_raw.buttons[7] = (w & 0x0010) != 0;
        phys_raw.buttons[9] = (w & 0x0040) != 0;
        phys_raw.buttons[10] = (w & 0x0080) != 0;

        phys_raw.axes[0] = normThumb(gp.sThumbLX);
        phys_raw.axes[1] = -normThumb(gp.sThumbLY); // up = -1
        phys_raw.axes[2] = (@as(f32, @floatFromInt(gp.bLeftTrigger)) / 255.0) * 2.0 - 1.0;
        phys_raw.axes[3] = normThumb(gp.sThumbRX);
        phys_raw.axes[4] = -normThumb(gp.sThumbRY); // up = -1
        phys_raw.axes[5] = (@as(f32, @floatFromInt(gp.bRightTrigger)) / 255.0) * 2.0 - 1.0;

        var hx: f32 = 0;
        if ((w & 0x0004) != 0) hx -= 1.0;
        if ((w & 0x0008) != 0) hx += 1.0;
        var hy: f32 = 0;
        if ((w & 0x0001) != 0) hy -= 1.0;
        if ((w & 0x0002) != 0) hy += 1.0;
        phys_raw.axes[6] = hx;
        phys_raw.axes[7] = hy;
    }

    fn tryOpen() void {
        ensureLoaded();
        const fn_ptr = get_state_fn orelse return;
        var st: XINPUT_STATE = undefined;
        for (0..4) |i| {
            const idx: u32 = @intCast(i);
            if (fn_ptr(idx, &st) == 0) {
                active_slot = idx;
                is_connected = true;
                const label = std.fmt.bufPrint(&device_name_buf, "XInput {d}", .{idx}) catch "XInput";
                device_name_len = label.len;
                applyState(&st);
                return;
            }
        }
    }

    fn pollEvents() void {
        const fn_ptr = get_state_fn orelse return;
        const slot = active_slot orelse return;
        var st: XINPUT_STATE = undefined;
        if (fn_ptr(slot, &st) != 0) {
            active_slot = null;
            is_connected = false;
            device_name_len = 0;
            phys_raw = .{};
            return;
        }
        applyState(&st);
    }
} else struct {
    fn tryOpen() void {}
    fn pollEvents() void {}
};

// ------------------------------------------------------------------ 公共 API

pub fn setAllowHardware(allow: bool) void {
    allow_hardware = allow;
}

pub fn poll(dt: f32) void {
    last_raw_evt = null;

    if (allow_hardware) {
        if (!is_connected) {
            scan_timer += dt;
            if (scan_timer >= 1.0) {
                scan_timer = 0;
                if (builtin.os.tag == .linux) linux_backend.tryOpen();
                if (builtin.os.tag == .windows) windows_backend.tryOpen();
            }
        } else {
            if (builtin.os.tag == .linux) linux_backend.pollEvents();
            if (builtin.os.tag == .windows) windows_backend.pollEvents();
        }
    }

    var phys_logical: pad_logic.Logical = .{};
    if (is_connected) {
        phys_logical.update(&phys_raw, &mapping, tuning);
    }

    // 合并物理状态 OR 虚拟探针注入
    for (0..pad_logic.button_count) |i| {
        const down = phys_logical.down[i] or virt_buttons[i];
        logical_state.pressed[i] = down and !logical_state.down[i];
        logical_state.released[i] = !down and logical_state.down[i];
        logical_state.down[i] = down;
    }
    for (0..pad_logic.axis_count) |i| {
        const pv = phys_logical.axes[i];
        const vv = virt_axes[i];
        logical_state.axes[i] = if (@abs(vv) > @abs(pv)) vv else pv;
    }
}

pub fn connected() bool {
    return is_connected or virt_active;
}

pub fn name() []const u8 {
    if (is_connected and device_name_len > 0) return device_name_buf[0..device_name_len];
    if (virt_active) return "Virtual Pad";
    return "";
}

pub fn logical() *const pad_logic.Logical {
    return &logical_state;
}

pub fn lastRaw() ?RawEvent {
    return last_raw_evt;
}

pub fn setMapping(m: pad_logic.Mapping) void {
    mapping = m;
}

pub fn getMapping() pad_logic.Mapping {
    return mapping;
}

pub fn resetMapping() void {
    mapping = pad_logic.Mapping.xpad;
}

pub fn setTuning(t: pad_logic.Tuning) void {
    tuning = t;
}

pub fn injectButton(b: pad_logic.Button, down: bool) void {
    virt_active = true;
    virt_buttons[@intFromEnum(b)] = down;
}

pub fn injectAxis(a: pad_logic.Axis, v: f32) void {
    virt_active = true;
    virt_axes[@intFromEnum(a)] = if (std.math.isFinite(v)) std.math.clamp(v, -1.0, 1.0) else 0.0;
}
