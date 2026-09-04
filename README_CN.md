# omarchy-dsh-agent —— 把 DeepSeek Harness 装成 Omarchy 的 AI agent

GitHub: https://github.com/bforecast/omarchy-dsh-agent

一个可 git 分发的 Omarchy 插件包。在任一台 Omarchy 机器上克隆后一键执行：

```bash
git clone https://github.com/bforecast/omarchy-dsh-agent.git omarchy-dsh-agent
cd omarchy-dsh-agent
./install.sh --default        # 安装 DSH 并注册为默认 AI agent
./install.sh                  # 只安装并注册，不改动现有默认 AI
./uninstall.sh                # 卸载（还原默认、移除包装与菜单项）
```

> 说明：Omarchy 的官方插件体系（`omarchy plugin add/clone`）只承载 QML shell 组件；
> 本包的"安装为 AI agent"需要写 ~/.local/bin 包装、菜单覆盖与默认记录，因此以
> 自包含安装器插件形式分发，行为与本机手工安装完全一致，同样不触碰 /usr/share/omarchy。

## 目录结构

```
manifest.json           Omarchy shell 插件清单（bar-widget "dsh-launcher"）
BarWidget.qml           顶栏图标：一键启动并打开 DSH Web 界面
install.sh              安装器（幂等，可重复运行）
uninstall.sh            卸载器（带安全校验与干跑）
files/
  dsh-web               DSH 启动脚本模板（幂等启动 + 打开 Web 界面）
  omarchy-default-agent 用户级包装：支持 `omarchy default agent dsh`
  omarchy-agent         用户级包装：默认 agent 为 dsh 时启动 DSH Web
  omarchy               CLI 薄包装：拦截 omarchy agent / default agent dsh
  menu-entries.jsonc    菜单片段（Default Agent 选择器 DSH 项）
  icons/                DSH 官方图标（hicolor 各尺寸 dsh.png）
```

## 它做了什么

| 目标 | 内容 |
| --- | --- |
| DSH 源码 | 目标机无 `~/deepseek-harness` 时自动 `git clone https://github.com/deepseek-ai/deepseek-harness.git`（可用 `--repo-url` / `--repo-dir` 覆盖）；新克隆且无依赖时自动 `pnpm install`（`--no-bootstrap` 跳过） |
| `~/.local/bin/dsh-web` | 幂等启动 `dsh web`，然后以 Omarchy 独立应用窗口打开 `http://127.0.0.1:3080`（日志 `~/.local/state/dsh/web.log`） |
| `~/.local/bin/omarchy-*` | 3 个用户级包装，让 Omarchy 的菜单/按键/崩溃诊断各入口认识 `dsh`（其余行为透传原版） |
| `~/.config/omarchy/extensions/omarchy-menu.jsonc` | 合并菜单项：Default Agent 选择器 DSH 项（幂等，先备份 `*.dshplugin.bak`） |
| `~/.local/share/applications/dsh.desktop` + hicolor `dsh.png` | 注册为带官方图标的应用：菜单应用搜索显示真 DSH logo |
| `~/.local/share/applications/dsh.desktop` + `~/.local/share/icons/hicolor/*/apps/dsh.png` | 把 DSH 注册为带官方图标的桌面应用：菜单/应用搜索里出现带真 DSH logo 的应用行（图标取自 DSH 官方 `favicon.svg`） |
| `~/.config/omarchy/defaults/agent` | 仅 `--default` 时写入 `dsh`，并把旧默认记录到 `~/.local/state/dsh-omarchy-plugin/state` 供卸载还原 |

## 依赖与环境要求

- Omarchy（Hyprland + Quickshell），bash、git、curl；DSH 运行需要 Node.js ≥ 22。
- `~/.local/bin` 必须在 PATH 中且先于 `/usr/share/omarchy/bin`（Omarchy 默认如此；安装器会给出提示）。
- 首次 `dsh web` 启动较慢属正常（首次等待上限 90 秒，见日志）。

## install.sh 参数

| 参数 | 说明 |
| --- | --- |
| `--default` | 安装后把默认 AI 设为 dsh（记录原值，卸载自动还原） |
| `--repo-dir PATH` | DSH 源码目录（缺省 `~/deepseek-harness`；已存在则复用） |
| `--repo-url URL` | 克隆来源（缺省 `https://github.com/deepseek-ai/deepseek-harness.git`） |
| `--no-bootstrap` | 跳过 `pnpm install` |
| `-n` / `--dry-run` | 干跑，只打印将执行的动作 |

## 图标说明

Omarchy 菜单的**静态菜单项只能显示字体图标**（无法放 PNG），因此顶层不放字形
快捷行，避免误导图标；DSH 的启动统一走带**官方 logo** 的应用行（`.desktop`
`Icon=dsh`，菜单应用搜索 "DSH" 即见），或在 Default Agent 选择器里设置/查看
默认（该项用机器人字形，与选择器内其它 agent 风格一致）。

## 顶栏 widget（marketplace 合规的 shell 插件）

仓库根目录同时也是合法 Omarchy **shell 插件**（`bar-widget`，id `dsh-launcher`）：
顶栏一个图标，点击启动 DSH 并打开 Web 界面。

```bash
omarchy plugin add https://github.com/bforecast/omarchy-dsh-agent.git   # 克隆到 ~/.config/omarchy/plugins
omarchy plugin enable dsh-launcher                                      # 把 DSH 图标放进顶栏
```

widget 只负责启动 DSH；完整的 AI-agent 注册（PATH 包装、默认 agent、按键、
桌面项）仍由 `./install.sh` 完成。

## 用 DSH 解决系统错误

系统出现 error log（崩溃提示、journal 报错、粘来的错误文本）时，可以直接交给本地
DeepSeek Harness 分析解决：

- **`dsh-solve-error`**（由 `install.sh` 安装）：
  - `dsh-solve-error` 或 `dsh-solve-error --auto` —— 自动抓取最近系统/用户错误日志与
    core dump 列表，交给 DSH 分析（headless 运行，直接输出结论）；
  - `dsh-solve-error "错误文本"` / `--text …` / `--file 日志文件` —— 针对指定错误或日志；
  - `--show-context` 预览将发送的内容；`--dry-run` 只显示要执行的 DSH 命令。
- **崩溃提示 / `omarchy agent crash`**：默认 agent 为 `dsh` 时，点击"诊断"不再是只打开
  网页——会带崩溃事实在终端里运行 `dsh-solve-error`，由 DSH 给出原因与修复步骤。
- **菜单**：新增 "Fix system error with DSH" 项（Super+Space，id `dsh-fix`），在终端运行
  `dsh-solve-error --auto`。

要求：可用的 DSH 源码（`~/deepseek-harness`，见 install.sh）与 Node.js ≥ 22。

## 验证

```bash
omarchy default agent      # 期望: dsh（若用 --default）
omarchy agent              # 打开 DSH Web 独立窗口
dsh-web --no-open          # 只确保服务在跑
```

## 卸载

```bash
./uninstall.sh -n          # 先干跑确认
./uninstall.sh             # 还原默认 AI、删除包装、还原菜单
```

卸载器只删除内容与本插件一致的文件；被改动过的文件会跳过并提示，不会误删。

## 注意

- 安装/卸载均不修改 `/usr/share/omarchy`，系统更新不受影响。
- 默认 AI 还原目标：安装了 `--default` 时还原为安装前的值；否则按 `-r` 参数（缺省 `codex`）。
- 分发前请自行把本目录 `git init && git add . && git commit`，并替换上面示例中的仓库地址。

## FAQ：Hyprland 按键打不开 DSH（终端 `omarchy agent` 却可以）

原因：Hyprland 执行按键命令的 PATH 不一定把 `~/.local/bin` 排在 `/usr/share/omarchy/bin`
前面，于是按键走了系统原版 `omarchy-agent`，遇到默认 `dsh` 会报
"Unsupported default agent" 或干脆没反应。

本插件已把修法固化进安装器：`install.sh` 会自动在
`~/.config/hypr/bindings.lua` 末尾追加一段 **BEGIN/END omarchy-dsh-agent** 标记块，
把默认 AI 键（`SUPER + SHIFT + CTRL + A`）改绑为包装的**绝对路径**
（`$HOME/.local/bin/omarchy-agent --pick`），随后尝试 `hyprctl reload`；
`uninstall.sh` 会自动移除该块并恢复 Omarchy 出厂绑定。`--no-keybinding` 可跳过。

手动等效改动（`~/.config/hypr/bindings.lua` 末尾）：

```lua
hl.unbind("SUPER + SHIFT + CTRL + A")
o.bind("SUPER + SHIFT + CTRL + A", "Agent", "/home/<你的用户名>/.local/bin/omarchy-agent --pick")
```

然后 `hyprctl reload`。注意：`SUPER + SHIFT + A` 出厂绑的是 ChatGPT 网页应用，不是 agent 键。
