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

## 7. 验证任务（Windows 为主）

### 7.1 目的

玩家只在 Windows 上运行游戏，而 Linux 开发机（2 核、7 GB、软件渲染）跑 zig 构建和截图太慢。因此 Windows GPU 代理是主测试台：编码代理改完代码后，把工作区快照交给 Jenkins 任务 `winter_survival-verify`，在 Windows 上完成构建、单测、探针、平衡模拟与真 GPU 截图，再读取其 JUnit 与截图。流水线定义为 `ci/Jenkinsfile.verify`，任务 XML 为 `ci/jobs/winter_survival-verify.xml`。与 `winter_survival` 任务的区别：参数化、不轮询、不做桌面投放（不动 `ThirtyBelow` 目录）。

### 7.2 参数

| 参数 | 含义 |
|---|---|
| `REF` | 要测试的 git 引用或 sha，通常为 `refs/ci/<name>`（由 `tools/ci_verify.sh` 创建） |
| `PROFILE` | `full`（默认）或 `quick`；quick 跳过慢探针（`soak_heap.lua`）与平衡模拟 |
| `SHOTS` | 多行文本，每行一张截图：`name\|KEY=VAL KEY2=VAL2\|额外游戏参数` |
| `PROBES` | 可选，探针文件/通配符列表（空格、逗号或换行分隔）；默认 `tests/probe/*.lua` |
| `BALANCE_DAYS` | 平衡模拟天数，默认 30；仅 full 且 `build.zig` 有 `balance` 步骤时生效 |

阶段：Source（`built-in`）检出 `REF`（任务的 SCM 配置抓取 `refs/heads/*` 与 `refs/ci/*`）→ `setup_delve.sh` → `assets.py check`（含 i18n）与 Python 单测 → stash；Windows GPU：`setup_zig.py` → `ci/verify_steps.py`（`zig build test`、`luatest`（若有该步骤）、逐个 headless 探针、balance）→ `zig build -Dbackend=sokol` → `ci/smoke.py --shots-file` 逐行截图。任何一步失败都不会隐藏其他步骤：先收集，阶段末尾再标记失败。

产物（`reports/**` 归档，JUnit 自动发布）：

| 路径 | 内容 |
|---|---|
| `linux/*.xml` | 资产检查、Python 单测 |
| `windows/unit.xml`、`luatest.xml`、`balance.xml` + `*.log` | 对应步骤，失败时 JUnit 附日志尾部 |
| `windows/probe_<name>.xml/.log` | 每个探针一份 |
| `windows/shots/<name>.png` + `<name>.log`、`windows/shots.xml` | 每行 SHOTS 一张截图与游戏日志 |

### 7.3 截图行约定

- 格式 `name|KEY=VAL KEY2=VAL2|额外游戏参数`，`#` 开头为注释；环境变量与参数按 shell 规则分词，后两段可省略。名称只用字母数字与 `._-`，不可重复。
- 每张截图使用独立存档目录（`--save-dir`），并预写 `settings.sav`：`return { version = 1, lang = "<WS_LANG，缺省 zh>" }`，所以 `WS_LANG=zh|en|ko` 直接生效。
- 例：`m2_night_zh|WS_SCENE=m2_demo WS_MODE=cutaway WS_HOUR=21 WS_LANG=zh|`；标题画面：`title_zh|WS_LANG=zh|`。
- 一张截图 = 启动游戏 8 秒、第 5 秒截图，因此场景应在 5 秒内就绪。截图名要表达“场景_状态_语言”，审查者靠名字找图。

### 7.4 代理使用方法

```
tools/ci_verify.sh --name TAG [--profile quick|full] [--shots FILE] [--probes LIST] [--out DIR]
tools/ci_verify.sh --gc [DAYS]      # 清理超过 DAYS（默认 7）天的 refs/ci/*
```

- 脚本用临时 `GIT_INDEX_FILE` 把当前工作区（已跟踪 + 未跟踪，遵守 `.gitignore`）提交为以 `HEAD` 为父的快照，写入共享仓库的 `refs/ci/TAG`（git daemon 可见）。不改分支、暂存区和工作区文件。`TAG` 请带任务名，同名会覆盖旧快照。
- 触发 `build winter_survival-verify -f -v`，等待结束；控制台输出存 `OUT/console.log`，产物下载到 `OUT/`（`OUT/linux`、`OUT/windows`、`OUT/windows/shots/*.png`）；默认 `OUT=/tmp/claude-1000/ci-verify-TAG`，多个代理并行时请显式 `--out`。
- 末尾打印：构建号与结果、各 JUnit 套件的总数与失败用例名、截图路径。退出码 0 当且仅当构建 SUCCESS。等待上限 `--max-wait`（默认 3000 秒），超时只放弃等待，Jenkins 中构建仍会继续。
- 凭据只从 `~/.config/jenkins/ci_auth` 读取（下载时走权限 0600 的临时 curl 配置），不会出现在输出或命令行。

### 7.5 规则

1. 本地 Linux 只做编辑和秒级 Python 检查（`python3 tools/assets.py check`、`python3 -m unittest discover -s tests/tools -t .`、`tools/i18n_check.py`）；不跑 zig 构建，不开 Xvfb。
2. 每个编码任务完成后运行一次 `ci_verify.sh`（改动影响画面时带 `--shots`）；任务报告里写明构建号与结果。
3. 审查者读取该构建的产物（JUnit、日志、截图），不要重新构建；需要新截图时用新的 `--name` 再跑一次。
4. 不以 Linux 兼容为目标：只要 Windows 流水线通过即可。
5. Windows 只有一个执行器，任务禁止并发，多个构建会排队（full 构建首次需编译依赖，较慢）。日常迭代用 `quick`，合并前用 `full`。若 Windows 代理离线或排队很久，如实报告，不要无限等待。
6. 用完的快照引用由 `--gc` 清理；不要把 `refs/ci/*` 推到任何远端。

### 7.6 返工 1（Codex 审查，2026-11-14）

验收测试：`tests/tools/test_ci_verify_fix.py`，由主代理编写，编码代理不得修改。

| # | 问题 | 裁定 |
|---|---|---|
| C1 | Source 阶段 `assets.py check` / `run_pytests.py` 失败会中止阶段，跳过 stash 与 Windows | 两条命令各自包在 `catchError(buildResult: 'FAILURE', stageResult: 'FAILURE') { sh '...' }` 里，stash 照常执行 |
| C2 | `--shots` 相对路径在 `cd "$TOP"` 之后失效 | 解析参数后立即把 `--shots` 转成绝对路径（`--out` 已是这样） |
| C3 | 构建 SUCCESS 但产物解压失败时，脚本因 `set -e` 提前退出 | 解压失败只打印警告（含 "artifact" 字样），继续打印摘要；退出码只由构建结果决定 |
| C4 | `PROBES` 通配符无匹配时被静默丢弃 | `select_probes` 对无匹配的通配符、以及最终为空的选择抛 `ValueError`（消息里带模式）；`verify_steps.py` 把它记为失败的 JUnit 用例并以非 0 退出 |
| C5 | 截图 JUnit 的失败文本未过滤 XML 非法控制字符 | 复用 `probe_junit._xml_safe`（或等价函数）过滤 message 与 text |
| C6 | 截图名重名检查区分大小写，Windows 上会互相覆盖 | 用 `name.lower()` 判重 |

## 8. 主代理驱动的 TDD 与分支自证（2026-11-14 起，从 P0 开始执行）

M3 两轮审查都没通过，根因有三：一是计划留了空档（燃料预检与实际燃烧的规则不一致）；二是按文件拆分后留下跨模块缺口（审计没查 `wear`）；三是审查者只能手推代码，推断出错。因此从 P0 起改为下列流程：

1. **验收标准即测试**：计划里的每条验收标准都由主代理写成测试，包括 Lua 单测、探针或截图行，在编码前提交到任务分支，并跑一次 `ci_verify.sh --profile quick`，确认它们是红的。写不成测试的标准要改写，或注明由截图/人工核验。
2. **不变量测试长期保留**，每次构建都跑：命令失败不改状态（深比较）、库存守恒总账、`state.validate`、存档往返、平衡模拟 `alive > 0`、`probe_junit` 的禁用告警。
3. **编码代理不得修改验收测试**（文件头有标注）。认为测试有误时停下，在报告里写明理由，由主代理裁定。编码代理可以另加自己的单测。
4. **分支自证**：编码代理的报告必须附 `ci_verify.sh` 的构建号与摘要。合并前跑一次 `--profile full`，必须全绿。
5. **审查**：本机 Codex（gpt-6.1-sol，medium）读取 diff 和该构建的产物，不重新构建。结论为 FAIL 的每一条，要么指向一个失败的测试，要么指出某条验收标准缺少测试。主代理先把确认的问题写成失败测试，再分派返工。
6. 返工上限不变：最多两次返工，第三次由主代理亲自修复或请用户决策。
