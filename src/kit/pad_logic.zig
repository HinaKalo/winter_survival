//! 纯逻辑手柄处理：径向死区、扳机滞回、十字键阈值、映射表与边沿状态。
const std = @import("std");

pub const Button = enum(u8) {
    a,
    b,
    x,
    y,
    lb,
    rb,
    back,
    start,
    l3,
    r3,
    dpad_up,
    dpad_down,
    dpad_left,
    dpad_right,
    lt,
    rt,
    guide,
};

pub const button_count = @typeInfo(Button).@"enum".fields.len;

pub const Axis = enum(u8) {
    lx,
    ly,
    rx,
    ry,
    lt,
    rt,
};

pub const axis_count = @typeInfo(Axis).@"enum".fields.len;

pub const RawState = struct {
    buttons: [32]bool = .{false} ** 32,
    axes: [16]f32 = .{0} ** 16,
    n_buttons: u8 = 0,
    n_axes: u8 = 0,
};

pub const Mapping = struct {
    button: [button_count]i8,
    axis: [axis_count]i8,
    axis_invert: [axis_count]bool,
    hat_x: i8,
    hat_y: i8,
    trigger_bipolar: bool,

    // 按钮: 0 A, 1 B, 2 X, 3 Y, 4 LB, 5 RB, 6 Back, 7 Start, 8 Guide, 9 L3, 10 R3
    // 轴: 0 LX, 1 LY, 2 LT, 3 RX, 4 RY, 5 RT, 6/7 十字键
    pub const xpad: Mapping = .{
        .button = .{
            0, // a
            1, // b
            2, // x
            3, // y
            4, // lb
            5, // rb
            6, // back
            7, // start
            9, // l3
            10, // r3
            -1, // dpad_up
            -1, // dpad_down
            -1, // dpad_left
            -1, // dpad_right
            -1, // lt
            -1, // rt
            8, // guide
        },
        .axis = .{
            0, // lx
            1, // ly
            3, // rx
            4, // ry
            2, // lt
            5, // rt
        },
        .axis_invert = .{false} ** axis_count,
        .hat_x = 6,
        .hat_y = 7,
        .trigger_bipolar = true,
    };
};

pub const Tuning = struct {
    stick_deadzone: f32 = 0.24,
    trigger_deadzone: f32 = 0.12,
    trigger_press: f32 = 0.5,
    trigger_release: f32 = 0.4,
    hat_threshold: f32 = 0.5,
};

pub fn stick(x: f32, y: f32, dz: f32) [2]f32 {
    if (!std.math.isFinite(x) or !std.math.isFinite(y)) return .{ 0, 0 };
    const safe_dz = std.math.clamp(dz, 0.0, 0.99);
    const mag = @sqrt(x * x + y * y);
    if (mag <= safe_dz or mag == 0) return .{ 0, 0 };
    const clamped_mag = @min(mag, 1.0);
    const scaled = (clamped_mag - safe_dz) / (1.0 - safe_dz);
    const k = scaled / mag;
    return .{ x * k, y * k };
}

pub fn trigger(raw: f32, bipolar: bool, dz: f32) f32 {
    if (!std.math.isFinite(raw)) return 0;
    const safe_dz = std.math.clamp(dz, 0.0, 0.99);
    const norm = if (bipolar)
        std.math.clamp((raw + 1.0) * 0.5, 0.0, 1.0)
    else
        std.math.clamp(raw, 0.0, 1.0);
    if (norm <= safe_dz) return 0;
    return (norm - safe_dz) / (1.0 - safe_dz);
}

fn readAxis(raw: *const RawState, idx: i8, invert: bool) f32 {
    if (idx < 0) return 0;
    const u: usize = @intCast(idx);
    if (u >= raw.n_axes or u >= raw.axes.len) return 0;
    const v = raw.axes[u];
    if (!std.math.isFinite(v)) return 0;
    return if (invert) -v else v;
}

pub const Logical = struct {
    down: [button_count]bool = .{false} ** button_count,
    pressed: [button_count]bool = .{false} ** button_count,
    released: [button_count]bool = .{false} ** button_count,
    axes: [axis_count]f32 = .{0} ** axis_count,

    pub fn update(self: *Logical, raw: *const RawState, map: *const Mapping, t: Tuning) void {
        const lx_raw = readAxis(raw, map.axis[@intFromEnum(Axis.lx)], map.axis_invert[@intFromEnum(Axis.lx)]);
        const ly_raw = readAxis(raw, map.axis[@intFromEnum(Axis.ly)], map.axis_invert[@intFromEnum(Axis.ly)]);
        const l = stick(lx_raw, ly_raw, t.stick_deadzone);
        self.axes[@intFromEnum(Axis.lx)] = l[0];
        self.axes[@intFromEnum(Axis.ly)] = l[1];

        const rx_raw = readAxis(raw, map.axis[@intFromEnum(Axis.rx)], map.axis_invert[@intFromEnum(Axis.rx)]);
        const ry_raw = readAxis(raw, map.axis[@intFromEnum(Axis.ry)], map.axis_invert[@intFromEnum(Axis.ry)]);
        const r = stick(rx_raw, ry_raw, t.stick_deadzone);
        self.axes[@intFromEnum(Axis.rx)] = r[0];
        self.axes[@intFromEnum(Axis.ry)] = r[1];

        const lt_idx = map.axis[@intFromEnum(Axis.lt)];
        const lt_val = if (lt_idx >= 0 and @as(usize, @intCast(lt_idx)) < raw.n_axes)
            trigger(readAxis(raw, lt_idx, map.axis_invert[@intFromEnum(Axis.lt)]), map.trigger_bipolar, t.trigger_deadzone)
        else
            0.0;
        self.axes[@intFromEnum(Axis.lt)] = lt_val;

        const rt_idx = map.axis[@intFromEnum(Axis.rt)];
        const rt_val = if (rt_idx >= 0 and @as(usize, @intCast(rt_idx)) < raw.n_axes)
            trigger(readAxis(raw, rt_idx, map.axis_invert[@intFromEnum(Axis.rt)]), map.trigger_bipolar, t.trigger_deadzone)
        else
            0.0;
        self.axes[@intFromEnum(Axis.rt)] = rt_val;

        var new_down = [_]bool{false} ** button_count;
        for (0..button_count) |i| {
            const idx = map.button[i];
            if (idx >= 0) {
                const u: usize = @intCast(idx);
                if (u < raw.n_buttons and u < raw.buttons.len) {
                    new_down[i] = raw.buttons[u];
                }
            }
        }

        // Hat axes -> dpad
        const hx = readAxis(raw, map.hat_x, false);
        const hy = readAxis(raw, map.hat_y, false);
        if (hx <= -t.hat_threshold) new_down[@intFromEnum(Button.dpad_left)] = true;
        if (hx >= t.hat_threshold) new_down[@intFromEnum(Button.dpad_right)] = true;
        if (hy <= -t.hat_threshold) new_down[@intFromEnum(Button.dpad_up)] = true;
        if (hy >= t.hat_threshold) new_down[@intFromEnum(Button.dpad_down)] = true;

        // Triggers with hysteresis
        const lt_b = @intFromEnum(Button.lt);
        if (!new_down[lt_b]) {
            new_down[lt_b] = if (self.down[lt_b]) (lt_val > t.trigger_release) else (lt_val >= t.trigger_press);
        }
        const rt_b = @intFromEnum(Button.rt);
        if (!new_down[rt_b]) {
            new_down[rt_b] = if (self.down[rt_b]) (rt_val > t.trigger_release) else (rt_val >= t.trigger_press);
        }

        for (0..button_count) |i| {
            self.pressed[i] = new_down[i] and !self.down[i];
            self.released[i] = !new_down[i] and self.down[i];
            self.down[i] = new_down[i];
        }
    }
};

// ------------------------------------------------------------------ 单元测试

test "stick radial deadzone boundary and full deflection" {
    const dz: f32 = 0.24;
    const inside = stick(0.15, 0.15, dz); // mag ~0.212 < 0.24
    try std.testing.expectEqual(@as(f32, 0), inside[0]);
    try std.testing.expectEqual(@as(f32, 0), inside[1]);

    const exact = stick(dz, 0, dz);
    try std.testing.expectEqual(@as(f32, 0), exact[0]);

    const full = stick(1.0, 0.0, dz);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), full[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), full[1], 1e-5);

    const over = stick(1.0, 1.0, dz);
    const len = @sqrt(over[0] * over[0] + over[1] * over[1]);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), len, 1e-5);
}

test "trigger bipolar and unipolar" {
    try std.testing.expectEqual(@as(f32, 0), trigger(-1.0, true, 0.12));
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), trigger(1.0, true, 0.12), 1e-5);
    try std.testing.expectEqual(@as(f32, 0), trigger(0.10, false, 0.12));
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), trigger(1.0, false, 0.12), 1e-5);
}

test "Logical handles trigger hysteresis, hat, remapping, and single-frame edges" {
    var log: Logical = .{};
    var raw: RawState = .{ .n_buttons = 16, .n_axes = 8 };
    raw.axes[2] = -1.0; // LT released
    raw.axes[5] = -1.0; // RT released
    const t: Tuning = .{};

    // Press A (button 0)
    raw.buttons[0] = true;
    log.update(&raw, &Mapping.xpad, t);
    try std.testing.expect(log.down[@intFromEnum(Button.a)]);
    try std.testing.expect(log.pressed[@intFromEnum(Button.a)]);
    try std.testing.expect(!log.released[@intFromEnum(Button.a)]);

    // Hold A -> pressed clears
    log.update(&raw, &Mapping.xpad, t);
    try std.testing.expect(log.down[@intFromEnum(Button.a)]);
    try std.testing.expect(!log.pressed[@intFromEnum(Button.a)]);

    // Release A -> released for 1 frame
    raw.buttons[0] = false;
    log.update(&raw, &Mapping.xpad, t);
    try std.testing.expect(!log.down[@intFromEnum(Button.a)]);
    try std.testing.expect(log.released[@intFromEnum(Button.a)]);
    log.update(&raw, &Mapping.xpad, t);
    try std.testing.expect(!log.released[@intFromEnum(Button.a)]);

    // Trigger hysteresis: press >= 0.5, stays down at 0.45 (> 0.4), releases at 0.35 (<= 0.4)
    raw.axes[2] = 0.2; // bipolar 0.2 -> norm 0.6 -> trigger ~0.545 >= 0.5
    log.update(&raw, &Mapping.xpad, t);
    try std.testing.expect(log.down[@intFromEnum(Button.lt)]);

    raw.axes[2] = 0.03; // norm 0.515 -> trigger (0.515-0.12)/0.88 = 0.449 > 0.4
    log.update(&raw, &Mapping.xpad, t);
    try std.testing.expect(log.down[@intFromEnum(Button.lt)]);

    raw.axes[2] = -0.2; // norm 0.4 -> trigger 0.318 <= 0.4
    log.update(&raw, &Mapping.xpad, t);
    try std.testing.expect(!log.down[@intFromEnum(Button.lt)]);

    // Hat threshold
    raw.axes[6] = -0.6;
    log.update(&raw, &Mapping.xpad, t);
    try std.testing.expect(log.down[@intFromEnum(Button.dpad_left)]);
    try std.testing.expect(!log.down[@intFromEnum(Button.dpad_right)]);
}
