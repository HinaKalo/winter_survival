const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const Backend = enum { sokol, headless, null };
    const backend = b.option(Backend, "backend", "Delve backend: sokol (default), headless, null") orelse .sokol;
    const probe_file = b.option([]const u8, "probe", "Probe script for `zig build probe`") orelse "tests/probe/smoke.lua";
    const probe_audio = b.option(bool, "probe-audio", "Run the probe with audio playback on (default true)") orelse true;

    const dep = b.dependency("delve", .{
        .target = target,
        .optimize = optimize,
        .backend = backend,
    });
    const delve_mod = dep.module("delve");
    const delve_lib = dep.artifact("delve");

    // iso 引擎模块（纯逻辑 + 图形层）
    const iso_mod = b.addModule("iso", .{
        .root_source_file = b.path("src/iso/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    iso_mod.addImport("delve", delve_mod);

    // kit 模块（音频 + 探针 + UI + 输入 + 存档）
    const kit_mod = b.addModule("kit", .{
        .root_source_file = b.path("src/kit/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    kit_mod.addImport("delve", delve_mod);
    kit_mod.addImport("iso", iso_mod);
    kit_mod.addImport("zlua", delve_mod.import_table.get("zlua").?);

    // 游戏可执行文件
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("delve", delve_mod);
    exe_mod.addImport("iso", iso_mod);
    exe_mod.addImport("kit", kit_mod);

    const exe = b.addExecutable(.{
        .name = "winter_survival",
        .root_module = exe_mod,
    });
    exe.root_module.linkLibrary(delve_lib);
    b.installArtifact(exe);

    // run：工作目录设为项目根，便于读取 assets/
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.setCwd(b.path("."));
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the game");
    run_step.dependOn(&run_cmd.step);

    // probe：在项目根用 Lua 探针脚本跑已安装的 exe（建议配合 -Dbackend=headless）
    const probe_cmd = b.addRunArtifact(exe);
    probe_cmd.setCwd(b.path("."));
    probe_cmd.step.dependOn(b.getInstallStep());
    probe_cmd.addArgs(&.{ "--probe", probe_file });
    if (!probe_audio) probe_cmd.addArg("--no-audio");
    const probe_step = b.step("probe", "Run the headless CI probe (-Dprobe=FILE, -Dprobe-audio=false)");
    probe_step.dependOn(&probe_cmd.step);

    // luatest：无窗口 Lua 单元测试（--script tests/lua/main.lua --probe tests/lua/runner.lua --no-audio）
    const luatest_cmd = b.addRunArtifact(exe);
    luatest_cmd.setCwd(b.path("."));
    luatest_cmd.step.dependOn(b.getInstallStep());
    luatest_cmd.addArgs(&.{ "--script", "tests/lua/main.lua", "--probe", "tests/lua/runner.lua", "--no-audio" });
    const luatest_step = b.step("luatest", "Run Lua unit tests in headless mode");
    luatest_step.dependOn(&luatest_cmd.step);

    // test：纯逻辑单元测试根 src/iso/tests.zig
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/iso/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("delve", delve_mod);
    test_mod.linkLibrary(delve_lib);

    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // kit 纯逻辑测试（audio_catalog）：不依赖 delve，在项目根运行以便读取真实 catalog.json
    const kit_test_mod = b.createModule(.{
        .root_source_file = b.path("src/kit/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const kit_tests = b.addTest(.{ .root_module = kit_test_mod });
    const run_kit_tests = b.addRunArtifact(kit_tests);
    run_kit_tests.setCwd(b.path("."));
    test_step.dependOn(&run_kit_tests.step);
}
