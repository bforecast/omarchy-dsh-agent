#!/usr/bin/env bash
#
# omarchy-dsh-agent uninstall.sh —— 移除 install.sh 安装的所有内容。
#
# 用法:
#   ./uninstall.sh [-n] [-r <agent>]
#     -n          干跑
#     -r <agent>  默认 AI 还原目标（无状态文件时的兜底值，缺省 codex）
#
# 只删除内容与本插件一致的文件；被改动过的文件跳过并告警。

set -euo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DRY=false
RESTORE_AGENT="codex"
while (($#)); do
  case "$1" in
    -n | --dry-run) DRY=true ;;
    -r | --restore) shift; RESTORE_AGENT=${1:?need agent} ;;
    -h | --help) sed -n '1,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "uninstall.sh: unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

case "$RESTORE_AGENT" in
  pi|omp|opencode|claude|codex|crush|grok|gemini|copilot) ;;
  *) echo "uninstall.sh: 未知 agent '$RESTORE_AGENT'" >&2; exit 1 ;;
esac

BIN="$HOME/.local/bin"
AGENT_FILE="$HOME/.config/omarchy/defaults/agent"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
STATE_DIR="$HOME/.local/state/dsh-omarchy-plugin"
STATE_FILE="$STATE_DIR/state"

# ---------- 默认 AI 还原 ----------
current=""
[[ -f $AGENT_FILE ]] && read -r current <"$AGENT_FILE" || true
previous=""
plugin_set=""
if [[ -f $STATE_FILE ]]; then
  . "$STATE_FILE"
fi
if [[ $current == "dsh" ]]; then
  target="$RESTORE_AGENT"
  if [[ $plugin_set == "1" && -n ${previous:-} ]]; then
    target="$previous"
  elif [[ $plugin_set == "1" && -z ${previous:-} ]]; then
    target=""
  fi
  if $DRY; then
    echo "  [dry-run] 默认 AI 将还原为 ${target:-<清除默认>}"
  elif [[ -z $target ]]; then
    rm -f "$AGENT_FILE"
    echo "== 已清除默认 AI 记录"
  else
    if /usr/share/omarchy/bin/omarchy-default-agent "$target" >/dev/null 2>&1; then
      echo "== 默认 AI 已还原为 $target"
    else
      printf '%s\n' "$target" >"$AGENT_FILE"
      echo "== 默认 AI 已还原为 $target（直接写记录；请确认该 agent 已安装）"
    fi
  fi
else
  echo "== 当前默认 AI 不是 dsh（=${current:-<未设置>}），跳过默认还原"
fi

# ---------- 删除包装（仅删除内容匹配本插件的文件） ----------
remove_one() {
  local path=$1 sentinel=$2
  if [[ ! -e $path ]]; then echo "== 跳过（不存在）: $path"; return; fi
  if ! grep -qF "$sentinel" "$path"; then
    echo "!! 跳过（内容与插件不一致，可能被改动过）: $path" >&2
    return
  fi
  if $DRY; then echo "  [dry-run] 将删除 $path"; else rm -f "$path"; echo "== 已删除 $path"; fi
}
remove_one "$BIN/dsh-web" 'dsh-web -- Omarchy "AI agent" entry'
remove_one "$BIN/omarchy-default-agent" 'teaches `omarchy default agent` about the local DSH'
remove_one "$BIN/omarchy-agent" 'when the default agent is the local DSH agent'
remove_one "$BIN/omarchy" 'User extension wrapper for the `omarchy` CLI'
remove_one "$BIN/dsh-solve-error" 'dsh-solve-error -- collect an error context'

# ---------- 菜单键移除 ----------
if [[ -f $MENU ]]; then
  python3 - "$MENU" "$(if $DRY; then echo 1; else echo 0; fi)" <<'PY'
import sys
path, dry = sys.argv[1], sys.argv[2] == "1"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
start = end = None
for i, ln in enumerate(lines):
    if "// Local DeepSeek Harness (DSH) -- AI agent entry" in ln:
        start = i
    if start is not None and '"setup.default.agent.dsh"' in ln:
        end = i
        break
if start is None or end is None or start >= end:
    print("== 菜单未找到插件标记段，跳过")
    sys.exit(0)
keys = sum(1 for l in lines[start:end + 1] if l.lstrip().startswith('"'))
print(f"== 将从菜单移除 {keys} 个 DSH 键" + ("（dry-run）" if dry else ""))
if dry:
    sys.exit(0)
del lines[start:end + 1]
while len(lines) >= 2 and lines[-2].strip() == "" and lines[-1].strip() == "}":
    del lines[-2]
with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
print("== 菜单已还原")
PY
else
  echo "== 跳过（菜单文件不存在）"
fi

# ---------- Hyprland Agent 键绑定块移除 ----------
BINDFILE="$HOME/.config/hypr/bindings.lua"
if [[ -f $BINDFILE ]]; then
  python3 - "$BINDFILE" "$(if $DRY; then echo 1; else echo 0; fi)" <<'PY'
import sys
path, dry = sys.argv[1], sys.argv[2] == "1"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
start = end = None
for i, ln in enumerate(lines):
    if "-- BEGIN omarchy-dsh-agent" in ln:
        start = i
    if start is not None and "-- END omarchy-dsh-agent" in ln:
        end = i
        break
if start is None or end is None or start >= end:
    print("== bindings.lua 未找到插件绑定块，跳过")
    sys.exit(0)
print("== 将移除 Agent 键绑定块（恢复 Omarchy 默认绑定）" + ("（dry-run）" if dry else ""))
if dry:
    sys.exit(0)
del lines[start:end + 1]
# 清理块前后多余空行
while len(lines) >= 2 and lines[-2].strip() == "":
    del lines[-2]
while len(lines) >= 1 and lines[0].strip() == "":
    del lines[0]
with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
print("== 已移除按键绑定块")
PY
  if ! $DRY && command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 \
      && echo "   (hyprctl reload 完成，按键恢复 Omarchy 默认)" \
      || echo "   (未能 hyprctl reload：下次图形会话生效，或手动执行 hyprctl reload)"
  fi
else
  echo "== 跳过（bindings.lua 不存在）"
fi

# ---------- 桌面应用注册移除（dsh.desktop + dsh.png 图标） ----------
DESKTOP_FILE="$HOME/.local/share/applications/dsh.desktop"
ICON_ROOT="$HOME/.local/share/icons"
if [[ -f $DESKTOP_FILE ]] && grep -qF "omarchy-dsh-agent" "$DESKTOP_FILE"; then
  if $DRY; then
    echo "  [dry-run] 将删除桌面项 $DESKTOP_FILE"
  else
    rm -f "$DESKTOP_FILE"
    echo "== 已删除桌面项 $DESKTOP_FILE"
    update-desktop-database "$(dirname "$DESKTOP_FILE")" >/dev/null 2>&1 || true
  fi
elif [[ -f $DESKTOP_FILE ]]; then
  echo "!! 桌面项与插件不一致（可能被改动过），跳过: $DESKTOP_FILE" >&2
else
  echo "== 跳过（dsh.desktop 不存在）"
fi
if $DRY; then
  echo "  [dry-run] 将删除 dsh.png 图标: $ICON_ROOT/hicolor/{48,64,128,256,512}x*/apps/dsh.png"
else
  rm -f "$ICON_ROOT"/hicolor/*x*/apps/dsh.png 2>/dev/null || true
  gtk-update-icon-cache -f "$ICON_ROOT/hicolor" >/dev/null 2>&1 || true
  echo "== 已删除 dsh.png 图标并刷新缓存"
fi

# ---------- 残留提示 ----------
if ! $DRY; then
  echo
  echo "== 卸载完成。可选的残留清理："
  echo "   rm -f $BIN/dsh-web.dshplugin.bak $BIN/dsh-solve-error.dshplugin.bak $BIN/omarchy-default-agent.dshplugin.bak"
  echo "   rm -f $BIN/omarchy-agent.dshplugin.bak $BIN/omarchy.dshplugin.bak"
  echo "   rm -f \"$MENU.dshplugin.bak\" \"$BINDFILE.dshplugin.bak\" $STATE_FILE; rmdir $STATE_DIR 2>/dev/null || true"
  echo "   rm -rf ~/.local/state/dsh                 # DSH 运行日志"
fi
