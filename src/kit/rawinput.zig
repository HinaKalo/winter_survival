//! 原始输入边沿模块 `kit_input`（优先级 -75）：
//! 自算键鼠 released（支持同帧按下并松开）、last_key、last_mouse_button、last_device，
//! 并在非 dev_console 模式下每帧关闭调试控制台。
const std = @import("std");
const delve = @import("delve");
const debug = delve.debug;
const input = delve.platform.input;
const modules = delve.modules;

const gamepad = @import("gamepad.zig");
const pad_logic = @import("pad_logic.zig");

pub const Device = enum(u8) {
    keyboard = 0,
    mouse = 1,
    pad = 2,
};

pub const Config = struct {
    dev_console: bool = false,
};

const max_key_code: usize = 512;
const mouse_btn_count: usize = 3;

var config: Config = .{};
var key_prev: [max_key_code]bool = .{false} ** max_key_code;
var key_rel: [max_key_code]bool = .{false} ** max_key_code;
var mouse_prev: [mouse_btn_count]bool = .{false} ** mouse_btn_count;
var mouse_rel: [mouse_btn_count]bool = .{false} ** mouse_btn_count;

var last_key_code: ?i32 = null;
var last_mouse_btn: ?i32 = null;
var last_dev: Device = .keyboard;
var prev_mouse_x: f32 = 0;
var prev_mouse_y: f32 = 0;
var mouse_pos_init: bool = false;

pub fn register(cfg: Config) !void {
    config = cfg;
    try modules.registerModule(.{
        .name = "kit_input",
        .priority = -75,
        .tick_fn = onTick,
    });
}

fn onTick(dt: f32) void {
    if (!config.dev_console) {
        debug.setConsoleVisible(false);
    }

    last_key_code = null;
    last_mouse_btn = null;

    // 键盘边沿与 last_key
    inline for (@typeInfo(input.KeyCodes).@"enum".fields) |f| {
        const code: usize = @intCast(f.value);
        if (code < max_key_code) {
            const kc: input.KeyCodes = @enumFromInt(f.value);
            const down = input.isKeyPressed(kc);
            const jp = input.isKeyJustPressed(kc);
            key_rel[code] = (key_prev[code] or jp) and !down;
            key_prev[code] = down;
            if (jp) {
                if (last_key_code == null) last_key_code = @intCast(f.value);
                last_dev = .keyboard;
            }
        }
    }

    // 鼠标边沿与 last_mouse_button
    for (0..mouse_btn_count) |b| {
        const mb: input.MouseButtons = @enumFromInt(@as(i32, @intCast(b)));
        const down = input.isMouseButtonPressed(mb);
        const jp = input.isMouseButtonJustPressed(mb);
        mouse_rel[b] = (mouse_prev[b] or jp) and !down;
        mouse_prev[b] = down;
        if (jp) {
            if (last_mouse_btn == null) last_mouse_btn = @intCast(b);
            last_dev = .mouse;
        }
    }

    // 鼠标移动 >= 3 px 切换设备为 mouse
    const mp = input.getMousePosition();
    if (!mouse_pos_init) {
        mouse_pos_init = true;
        prev_mouse_x = mp.x;
        prev_mouse_y = mp.y;
    } else {
        const dx = mp.x - prev_mouse_x;
        const dy = mp.y - prev_mouse_y;
        if (dx * dx + dy * dy >= 9.0) {
            prev_mouse_x = mp.x;
            prev_mouse_y = mp.y;
            last_dev = .mouse;
        }
    }

    // 手柄轮询与设备检测
    gamepad.poll(dt);
    const pad_st = gamepad.logical();
    for (0..pad_logic.button_count) |i| {
        if (pad_st.pressed[i]) {
            last_dev = .pad;
            break;
        }
    }
    for (0..pad_logic.axis_count) |i| {
        if (@abs(pad_st.axes[i]) >= 0.5) {
            last_dev = .pad;
            break;
        }
    }
}

pub fn keyReleased(code: i32) bool {
    if (code < 0 or code >= max_key_code) return false;
    return key_rel[@intCast(code)];
}

pub fn mouseReleased(btn: i32) bool {
    if (btn < 0 or btn >= mouse_btn_count) return false;
    return mouse_rel[@intCast(btn)];
}

pub fn lastKey() ?i32 {
    return last_key_code;
}

pub fn lastMouseButton() ?i32 {
    return last_mouse_btn;
}

pub fn lastDevice() Device {
    return last_dev;
}
