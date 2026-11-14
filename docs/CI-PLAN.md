# winter_survival Jenkins CI 计划

重活放在 Windows GPU 代理上，Linux 控制器只做检出、打包与轻量检查。流水线定义为 `ci/Jenkinsfile`，任务名 `winter_survival`。

## 0. 接入方式（2026-11-14 配置，主代理实测）

| 项 | 配置 |
|---|---|
| 源码 | 用户级 systemd 服务 `git-daemon-pixel.service`（`~/.config/systemd/user/`）以只读方式导出 `~/dev` 下的若干仓库，本仓库已加入其白名单；地址 `git://127.0.0.1/winter_survival` |
| 任务 | Jenkins `winter_survival`，由 `delve-starter` 任务的 XML 复制而来（只改仓库地址与描述）：Pipeline from SCM，分支 `*/main`，脚本 `ci/Jenkinsfile`，轻量检出，`pollSCM H/2 * * * *`，保留 20 次构建，禁止并发 |
| 管理 | `java -jar ~/.config/jenkins/jenkins-cli.jar -s http://localhost:8080/ -auth @~/.config/jenkins/ci_auth <命令>`（`get-job` / `update-job` / `build winter_survival -s -v`） |
| 基线 | #1（初始提交 `40a079d`）SUCCESS：Linux 资产检查与 Python 单测通过；Windows 构建、单测、headless 探针 19/19、真 GPU 窗口截图 1280×720 |

本地提交到 `main` 后，2 分钟内自动触发构建，无需推送。

## 0.1 规划中的扩展（随里程碑加入）

| 里程碑 | 新增步骤 |
|---|---|
| M1 | `zig build luatest -Dbackend=headless`；`tools/i18n_check.py` 与 `tools/bake_font.py --check` 进 `assets.py check`；内存浸泡探针；`grep` 禁止 `lua_util.getLua/manager.init`；Windows 交叉编译检查（手柄后端） |
| M2 | `engine_ext.lua` 探针（含模糊输入）；截图改为家园场景 |
| M4/M6 | 三份完整循环探针 `loop_keyboard/loop_mouse/loop_pad.lua` 替换脚手架 `smoke.lua` 成为门禁 |
| M3/M10 | `zig build balance -Dbackend=headless`（500 局批量模拟）作为夜间任务或手动参数，报告归档为 HTML |

## 1. 阶段

| 阶段 | 节点 | 内容 |
|---|---|---|
| Source | `built-in`（控制器） | 检出 `winter_survival/`；`ci/setup_delve.sh delve-framework "$(cat ci/delve.rev)"`；`tools/assets.py check --junit reports/linux/assets.xml`；`ci/run_pytests.py --junit reports/linux/unit_py.xml`；stash 源码 |
| Windows GPU | `windows && opengl` | unstash；`ci/setup_zig.py --lua-mirror`；`ci/zig_steps.py --probe`（`zig build`、`zig build test --summary all`、`zig build probe -Dbackend=headless`）；`zig build -Dbackend=sokol` 恢复 sokol 可执行文件；`ci/smoke.py --title "Thirty Below"` 截图冒烟 |

Post：`reports/linux/*.xml`、`reports/windows/*.xml` 发布为 JUnit；`reports/windows/**` 归档。

## 2. 工作区与源码传递

```
$WORKSPACE/
  winter_survival/     （checkout / unstash）
  delve-framework/   （setup_delve.sh / unstash）
```

`build.zig.zon` 的 `../delve-framework` 因此成立。Windows 代理不能访问控制器的 git daemon，所以源码通过 stash 传递，排除 `**/.git/**`、`**/.zig-cache/**`、`**/zig-out/**`、`**/zig-pkg/**`。

Delve 固定在 `ci/delve.rev`（当前 `3d09cb88e35290bbac9bc45e7827794d90cc1030`，delve-framework main，含 Ogg 支持）。`ci/setup_delve.sh` 每次都会幂等地重新应用 quakemap 补丁（`GeneralPurposeAllocator(` → `DebugAllocator(`），因为该补丁尚未合入上游。

持久缓存（不随 `deleteDir` 删除）：Windows 上为 `%USERPROFILE%\.ci\tools\zig-0.16.0\` 与 `%USERPROFILE%\.ci\zig-cache\`。

## 3. 脚本

| 文件 | 职责 |
|---|---|
| `ci/Jenkinsfile` | 流水线定义（见第 1 节） |
| `ci/delve.rev` | Delve 修订号，一行 |
| `ci/setup_delve.sh <dest> <rev>` | 幂等检出 delve-framework、清理并打补丁 |
| `ci/setup_zig.py --dest DIR [--lua-mirror]` | 按平台安装 Zig 0.16.0（sha256 校验）；`--lua-mirror` 预填 zlua 的 Lua 5.4.8 |
| `ci/zig_steps.py --zig ZIG --log-dir DIR [--probe]` | build、test，以及 `--probe` 时运行探针并生成 `probe.xml` |
| `ci/probe_junit.py --log FILE --junit FILE` | 探针日志转 JUnit：去除 NUL，检查 `PROBE SUMMARY` 与检查数，不完整则退出 1 |
| `ci/smoke.py --exe EXE --title T ...` | 启动游戏（`ISO_AUTOQUIT`），检查日志与退出码，截图（Windows 按窗口标题查找） |
| `ci/run_pytests.py --junit FILE` | `unittest` 发现 `tests/tools`，输出 JUnit |

除 `ci/smoke.py` 的 Windows 截图路径需要 Pillow（`PIL.ImageGrab`）外，所有脚本只用标准库；它们由 `tests/tools/test_ci.py` 等单元测试覆盖。

## 4. 探针与冒烟的顺序

探针使用 `-Dbackend=headless` 构建，会覆盖 `zig-out/bin/winter_survival.exe`。因此先运行探针，再执行 `zig build` 恢复默认的 sokol 版本（命中缓存，无需重新编译），最后冒烟截图。

探针在 Windows 交互式桌面会话中以有声模式运行（`-Dprobe-audio` 默认为 `true`）。

## 5. 验收

1. 本地：`python3 -m unittest discover -s tests/tools -t .` 通过；`zig build probe -Dbackend=headless -Dprobe-audio=false` 为 19/19；`ci/probe_junit.py` 生成的 JUnit 中 19 个用例、0 个失败。
2. Jenkins：Source 与 Windows GPU 全部成功，JUnit 全绿，`shot.png` 显示等距地形、主角与 HUD。

## 6. 风险

- Windows 首次构建需要从 GitHub 拉取 sokol、zaudio、zmesh、cimgui 等依赖，耗时较长；结果缓存于 `%USERPROFILE%\.ci\zig-cache`。
- Windows 工作区路径可能超过 260 个字符。若遇到，在 Jenkinsfile 中使用 `customWorkspace` 缩短路径。
- 截图只归档，不做自动判定。
