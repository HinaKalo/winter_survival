//! Lua 库 `kit_input` 与 `pad`：键鼠边沿、活动设备、手柄查询与映射/校准。
const std = @import("std");
const delve = @import("delve");
const lua_util = delve.scripting.lua;
const zlua = @import("zlua");

const gamepad = @import("gamepad.zig");
const pad_logic = @import("pad_logic.zig");
const rawinput = @import("rawinput.zig");

pub fn bind(lua: *lua_util.Lua) void {
    // kit_input 表
    lua.createTable(0, 5);
    setFn(lua, "key_released", zlua.wrap(l_keyReleased));
    setFn(lua, "mouse_released", zlua.wrap(l_mouseReleased));
    setFn(lua, "last_key", zlua.wrap(l_lastKey));
    setFn(lua, "last_mouse_button", zlua.wrap(l_lastMouseButton));
    setFn(lua, "last_device", zlua.wrap(l_lastDevice));
    lua.setGlobal("kit_input");

    // pad 表
    lua.createTable(0, 12);
    setFn(lua, "connected", zlua.wrap(l_padConnected));
    setFn(lua, "name", zlua.wrap(l_padName));
    setFn(lua, "button_down", zlua.wrap(l_padButtonDown));
    setFn(lua, "button_pressed", zlua.wrap(l_padButtonPressed));
    setFn(lua, "button_released", zlua.wrap(l_padButtonReleased));
    setFn(lua, "axis", zlua.wrap(l_padAxis));
    setFn(lua, "rumble", zlua.wrap(l_padRumble));
    setFn(lua, "last_button", zlua.wrap(l_padLastButton));
    setFn(lua, "last_raw", zlua.wrap(l_padLastRaw));
    setFn(lua, "set_mapping", zlua.wrap(l_padSetMapping));
    setFn(lua, "reset_mapping", zlua.wrap(l_padResetMapping));
    setFn(lua, "set_tuning", zlua.wrap(l_padSetTuning));
    lua.setGlobal("pad");

    // 全局枚举表 pad_buttons 与 pad_axes
    lua.createTable(0, pad_logic.button_count);
    inline for (@typeInfo(pad_logic.Button).@"enum".fields) |f| {
        lua.pushInteger(f.value);
        lua.setField(-2, f.name);
    }
    lua.setGlobal("pad_buttons");

    lua.createTable(0, pad_logic.axis_count);
    inline for (@typeInfo(pad_logic.Axis).@"enum".fields) |f| {
        lua.pushInteger(f.value);
        lua.setField(-2, f.name);
    }
    lua.setGlobal("pad_axes");
}

fn setFn(lua: *lua_util.Lua, name: [:0]const u8, func: zlua.CFn) void {
    lua.pushFunction(func);
    lua.setField(-2, name);
}

// ------------------------------------------------------------------ kit_input

fn l_keyReleased(lua: *zlua.Lua) i32 {
    const code = lua.optInteger(1) orelse -1;
    const c = std.math.cast(i32, code) orelse {
        lua.pushBoolean(false);
        return 1;
    };
    lua.pushBoolean(rawinput.keyReleased(c));
    return 1;
}

fn l_mouseReleased(lua: *zlua.Lua) i32 {
    const btn = lua.optInteger(1) orelse -1;
    const b = std.math.cast(i32, btn) orelse {
        lua.pushBoolean(false);
        return 1;
    };
    lua.pushBoolean(rawinput.mouseReleased(b));
    return 1;
}

fn l_lastKey(lua: *zlua.Lua) i32 {
    if (rawinput.lastKey()) |k| {
        lua.pushInteger(k);
    } else {
        lua.pushNil();
    }
    return 1;
}

fn l_lastMouseButton(lua: *zlua.Lua) i32 {
    if (rawinput.lastMouseButton()) |b| {
        lua.pushInteger(b);
    } else {
        lua.pushNil();
    }
    return 1;
}

fn l_lastDevice(lua: *zlua.Lua) i32 {
    lua.pushInteger(@intFromEnum(rawinput.lastDevice()));
    return 1;
}

// ------------------------------------------------------------------ pad

fn l_padConnected(lua: *zlua.Lua) i32 {
    lua.pushBoolean(gamepad.connected());
    return 1;
}

fn l_padName(lua: *zlua.Lua) i32 {
    _ = lua.pushString(gamepad.name());
    return 1;
}

fn buttonIdx(lua: *zlua.Lua) ?usize {
    const b = lua.optInteger(1) orelse return null;
    if (b < 0 or b >= pad_logic.button_count) return null;
    return @intCast(b);
}

fn l_padButtonDown(lua: *zlua.Lua) i32 {
    const idx = buttonIdx(lua) orelse {
        lua.pushBoolean(false);
        return 1;
    };
    lua.pushBoolean(gamepad.logical().down[idx]);
    return 1;
}

fn l_padButtonPressed(lua: *zlua.Lua) i32 {
    const idx = buttonIdx(lua) orelse {
        lua.pushBoolean(false);
        return 1;
    };
    lua.pushBoolean(gamepad.logical().pressed[idx]);
    return 1;
}

fn l_padButtonReleased(lua: *zlua.Lua) i32 {
    const idx = buttonIdx(lua) orelse {
        lua.pushBoolean(false);
        return 1;
    };
    lua.pushBoolean(gamepad.logical().released[idx]);
    return 1;
}

fn l_padAxis(lua: *zlua.Lua) i32 {
    const a = lua.optInteger(1) orelse {
        lua.pushNumber(0);
        return 1;
    };
    if (a < 0 or a >= pad_logic.axis_count) {
        lua.pushNumber(0);
        return 1;
    }
    lua.pushNumber(gamepad.logical().axes[@intCast(a)]);
    return 1;
}

fn l_padRumble(lua: *zlua.Lua) i32 {
    lua.pushBoolean(false);
    return 1;
}

fn l_padLastButton(lua: *zlua.Lua) i32 {
    const st = gamepad.logical();
    for (0..pad_logic.button_count) |i| {
        if (st.pressed[i]) {
            lua.pushInteger(@intCast(i));
            return 1;
        }
    }
    lua.pushNil();
    return 1;
}

fn l_padLastRaw(lua: *zlua.Lua) i32 {
    const evt = gamepad.lastRaw() orelse {
        lua.pushNil();
        return 1;
    };
    lua.createTable(0, 3);
    lua.pushBoolean(evt.is_axis);
    lua.setField(-2, "is_axis");
    lua.pushInteger(evt.index);
    lua.setField(-2, "index");
    lua.pushNumber(evt.value);
    lua.setField(-2, "value");
    return 1;
}

fn l_padSetMapping(lua: *zlua.Lua) i32 {
    const kind = lua.toString(1) catch {
        lua.pushBoolean(false);
        return 1;
    };
    const logical = lua.optInteger(2) orelse -1;
    const raw_idx = lua.optInteger(3) orelse -1;
    const invert = lua.toBoolean(4);

    var m = gamepad.getMapping();
    if (std.mem.eql(u8, kind, "button")) {
        if (logical < 0 or logical >= pad_logic.button_count) {
            lua.pushBoolean(false);
            return 1;
        }
        m.button[@intCast(logical)] = std.math.cast(i8, raw_idx) orelse -1;
        gamepad.setMapping(m);
        lua.pushBoolean(true);
        return 1;
    } else if (std.mem.eql(u8, kind, "axis")) {
        if (logical < 0 or logical >= pad_logic.axis_count) {
            lua.pushBoolean(false);
            return 1;
        }
        m.axis[@intCast(logical)] = std.math.cast(i8, raw_idx) orelse -1;
        m.axis_invert[@intCast(logical)] = invert;
        gamepad.setMapping(m);
        lua.pushBoolean(true);
        return 1;
    }
    lua.pushBoolean(false);
    return 1;
}

fn l_padResetMapping(lua: *zlua.Lua) i32 {
    _ = lua;
    gamepad.resetMapping();
    return 0;
}

fn l_padSetTuning(lua: *zlua.Lua) i32 {
    const stick_dz: f32 = @floatCast(lua.optNumber(1) orelse 0.24);
    const trig_dz: f32 = @floatCast(lua.optNumber(2) orelse 0.12);
    const trig_press: f32 = @floatCast(lua.optNumber(3) orelse 0.5);
    const trig_rel: f32 = @floatCast(lua.optNumber(4) orelse 0.4);
    gamepad.setTuning(.{
        .stick_deadzone = if (std.math.isFinite(stick_dz)) stick_dz else 0.24,
        .trigger_deadzone = if (std.math.isFinite(trig_dz)) trig_dz else 0.12,
        .trigger_press = if (std.math.isFinite(trig_press)) trig_press else 0.5,
        .trigger_release = if (std.math.isFinite(trig_rel)) trig_rel else 0.4,
    });
    return 0;
}
