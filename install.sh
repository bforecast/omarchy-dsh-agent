#!/usr/bin/env bash
#
# omarchy-dsh-agent install.sh
#
# 一键把本地 DeepSeek Harness (DSH) 安装为 Omarchy 的 AI agent：
#   1) 准备 DSH 源码：~/.deepseek-harness 不存在则自动 git clone（可 --repo-dir / --repo-url 覆盖）
#   2) 安装启动器 ~/.local/bin/dsh-web 与 3 个用户级包装（omarchy-default-agent / omarchy-agent / omarchy）
#   3) 合并菜单项到 ~/.config/omarchy/extensions/omarchy-menu.jsonc（幂等），把 Hyprland
#      默认 AI 键（SUPER + SHIFT + CTRL + A）改绑为包装的绝对路径（--no-keybinding 跳过），
#      并注册为带官方图标的桌面应用（应用搜索/菜单里显示真 DSH 图标）
#   4) 可选 --default：把默认 AI 记录指向 dsh（记录旧值，卸载时可还原）
#
# 所有写入都在用户目录；不修改 /usr/share/omarchy。重复运行安全（幂等）。
#
# 用法:
#   ./install.sh [--default] [--repo-dir PATH] [--repo-url URL] [--no-bootstrap] [--no-keybinding] [--dry-run]

set -euo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FILES="$SELF_DIR/files"

DRY=false
SET_DEFAULT=false
NO_BOOTSTRAP=false
NO_KEYBINDING=false
REPO_DIR="${DSH_REPO_DIR:-$HOME/deepseek-harness}"
REPO_URL="https://github.com/deepseek-ai/deepseek-harness.git"

while (($#)); do
  case "$1" in
    --default) SET_DEFAULT=true ;;
    --repo-dir) shift; REPO_DIR=${1:?--repo-dir needs a path} ;;
    --repo-url) shift; REPO_URL=${1:?--repo-url needs a URL} ;;
    --no-bootstrap) NO_BOOTSTRAP=true ;;
    --no-keybinding) NO_KEYBINDING=true ;;
    --dry-run | -n) DRY=true ;;
    -h | --help)
      sed -n '1,24p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "install.sh: unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

say() { if $DRY; then echo "  [dry-run] $*"; else echo "$*"; fi; }
do_or_dry() { if $DRY; then echo "  [dry-run] 将执行: $*"; else "$@"; fi; }

mkdir -p "$HOME/.local/bin"

# ---------- 1) DSH 源码 ----------
if [[ ! -f "$REPO_DIR/apps/cli/src/bin.ts" ]]; then
  for c in git; do command -v "$c" >/dev/null 2>&1 || { echo "install.sh: missing '$c'" >&2; exit 1; }; done
  echo "== 未找到 DSH 源码 ($REPO_DIR)，将 git clone $REPO_URL"
  do_or_dry git clone --depth 1 "$REPO_URL" "$REPO_DIR"
  say "DSH 源码就绪: $REPO_DIR"
else
  echo "== 复用现有 DSH 源码: $REPO_DIR"
fi

if ! $NO_BOOTSTRAP && [[ -f "$REPO_DIR/apps/cli/src/bin.ts" && ! -d "$REPO_DIR/node_modules" ]]; then
  if command -v pnpm >/dev/null 2>&1; then
    echo "== 安装 DSH 依赖 (pnpm install)…"
    (cd "$REPO_DIR" && do_or_dry pnpm install)
  else
    echo "!! 未找到 pnpm；跳过依赖安装。启动 dsh 前请手动在 $REPO_DIR 执行: pnpm install" >&2
  fi
fi

# ---------- 2) 启动器 + 包装 ----------
install_one() {
  local name=$1 src="$FILES/$1" dst="$HOME/.local/bin/$1"
  if [[ ! -f $src ]]; then echo "install.sh: 缺少 payload: $src" >&2; exit 1; fi
  if [[ -f $dst ]] && ! cmp -s "$src" "$dst"; then
    do_or_dry cp "$dst" "$dst.dshplugin.bak"
    say "已备份旧文件 -> $dst.dshplugin.bak"
  fi
  if $DRY; then
    echo "  [dry-run] 将安装 $name -> $dst"
  else
    install -m 0755 "$src" "$dst"
  fi
  say "安装 $name"
}
install_one dsh-web
install_one omarchy-default-agent
install_one omarchy-agent
install_one omarchy
install_one dsh-solve-error

# ---------- 3) 菜单合并（幂等） ----------
menu="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
if [[ -f $menu ]] && grep -qF "// Local DeepSeek Harness (DSH) -- AI agent entry" "$menu"; then
  echo "== 菜单已包含 DSH 项，跳过"
else
  mkdir -p "$(dirname "$menu")"
  [[ -f $menu ]] && do_or_dry cp "$menu" "$menu.dshplugin.bak"
  python3 - "$menu" "$FILES/menu-entries.jsonc" "$DRY" <<'PY'
import sys, json, re

menu_path, snippet_path, dry = sys.argv[1], sys.argv[2], sys.argv[3] == "True"
with open(menu_path, encoding="utf-8") as f:
    content = f.read()
with open(snippet_path, encoding="utf-8") as f:
    snippet = f.read().rstrip("\n")

if not content.endswith("\n"):
    content += "\n"
# 插到顶层对象最后一个 "}" 之前
idx = content.rstrip("\n").rfind("\n}")
if idx == -1:
    sys.exit("install: 菜单文件缺少结尾 '}'，无法合并，请人工检查 " + menu_path)
insert_at = content.rfind("\n}") + 1  # 保留结尾
new = content[:insert_at] + "\n" + snippet + content[insert_at:]

def strip_jsonc(text):
    out, i, in_str = [], 0, False
    while i < len(text):
        c = text[i]
        if c == '"':
            out.append(c); i += 1
            while i < len(text):
                out.append(text[i])
                if text[i] == "\\": out.append(text[i+1]); i += 2; continue
                if text[i] == '"': i += 1; break
                i += 1
            continue
        if c == "/" and i+1 < len(text) and text[i+1] == "/":
            while i < len(text) and text[i] != "\n": i += 1
            continue
        out.append(c); i += 1
    return "".join(out)

json.loads(strip_jsonc(new))  # 校验，失败即报错退出
if not dry:
    with open(menu_path, "w", encoding="utf-8") as f:
        f.write(new)
print("== 菜单已合并 DSH 项")
PY
fi

# ---------- 3.5) Hyprland 默认 AI 键（绝对路径，绕开 exec PATH 问题） ----------
if ! $NO_KEYBINDING; then
  bindfile="$HOME/.config/hypr/bindings.lua"
  # 仅当检测到 Omarchy/Hyprland 按键体系时才写入
  if command -v hyprctl >/dev/null 2>&1 || [[ -d /usr/share/omarchy/default/hypr ]]; then
    if [[ -f $bindfile ]] && grep -qF -- "-- BEGIN omarchy-dsh-agent" "$bindfile"; then
      echo "== 按键绑定已存在，跳过"
    else
      mkdir -p "$(dirname "$bindfile")"
      [[ -f $bindfile ]] && do_or_dry cp "$bindfile" "$bindfile.dshplugin.bak"
      block=$(cat <<LUA

-- BEGIN omarchy-dsh-agent: default-AI key rebound to the wrapper's absolute
-- path (Hyprland exec PATH may not put ~/.local/bin before
-- /usr/share/omarchy/bin, so a PATH-resolved stock omarchy-agent would not
-- know the "dsh" default). Remove this block to restore the Omarchy default;
-- uninstall.sh removes it for you.
hl.unbind("SUPER + SHIFT + CTRL + A")
o.bind("SUPER + SHIFT + CTRL + A", "Agent", "$HOME/.local/bin/omarchy-agent --pick")
-- END omarchy-dsh-agent
LUA
)
      if $DRY; then
        echo "  [dry-run] 将把 Agent 键绑定写入 $bindfile"
      else
        printf '\n%s\n' "$block" >>"$bindfile"
        echo "== 已写入 Agent 键绑定: SUPER + SHIFT + CTRL + A -> $HOME/.local/bin/omarchy-agent"
        if command -v hyprctl >/dev/null 2>&1; then
          hyprctl reload >/dev/null 2>&1 \
            && echo "   (hyprctl reload 完成，立即生效)" \
            || echo "   (未能 hyprctl reload：下次图形会话生效，或手动执行 hyprctl reload)"
        fi
      fi
    fi
  else
    echo "== 未检测到 Hyprland/Omarchy 按键体系，跳过按键绑定"
  fi
else
  echo "== 已按 --no-keybinding 跳过 Hyprland 按键绑定"
fi

# ---------- 3.6) 注册为带官方图标的桌面应用（应用搜索/菜单里显示真图标） ----------
desktop_dir="$HOME/.local/share/applications"
desktop_file="$desktop_dir/dsh.desktop"
icon_root="$HOME/.local/share/icons"
mkdir -p "$desktop_dir"
if [[ -f $desktop_file ]] && grep -qF "DeepSeek Harness" "$desktop_file" \
    && grep -qF "$HOME/.local/bin/dsh-web" "$desktop_file"; then
  echo "== DSH 桌面项已存在，跳过"
else
  if [[ -f $desktop_file ]]; then
    do_or_dry cp "$desktop_file" "$desktop_file.dshplugin.bak"
  fi
  desktop=$(cat <<EOF
# Installed by omarchy-dsh-agent plugin (uninstall.sh removes it).
[Desktop Entry]
Type=Application
Version=1.0
Name=DSH (DeepSeek Harness)
GenericName=DeepSeek Harness
Comment=Local DeepSeek Harness AI agent: starts the server and opens its web interface
Exec=$HOME/.local/bin/dsh-web
Icon=dsh
Terminal=false
Categories=Development;Network;
Keywords=AI;agent;deepseek;harness;
StartupNotify=true
EOF
)
  if $DRY; then
    echo "  [dry-run] 将写入桌面项 $desktop_file"
  else
    printf '%s\n' "$desktop" >"$desktop_file"
    echo "== 已写入桌面项 $desktop_file"
  fi
fi
if [[ -d $FILES/icons ]]; then
  if $DRY; then
    echo "  [dry-run] 将安装官方图标到 $icon_root/hicolor"
  else
    while IFS= read -r icon; do
      rel="${icon#"$FILES/icons/"}"
      mkdir -p "$icon_root/$(dirname "$rel")"
      cp "$icon" "$icon_root/$rel"
    done < <(find "$FILES/icons" -type f -name "*.png")
    gtk-update-icon-cache -f "$icon_root/hicolor" >/dev/null 2>&1 || true
    update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true
    echo "== 官方图标已安装到 $icon_root/hicolor"
  fi
fi

# ---------- 4) 可选：设为默认 AI ----------
if $SET_DEFAULT; then
  state_dir="$HOME/.local/state/dsh-omarchy-plugin"
  state_file="$state_dir/state"
  previous=""
  if [[ -f "$HOME/.config/omarchy/defaults/agent" ]]; then
    read -r previous <"$HOME/.config/omarchy/defaults/agent" || true
  fi
  if [[ $previous == "dsh" ]]; then
    echo "== 默认 AI 已是 dsh"
  else
    do_or_dry mkdir -p "$state_dir"
    do_or_dry bash -c "printf 'plugin_default_set=1\nprevious_agent=%q\n' \"\$0\" > \"\$1\"" "$previous" "$state_file"
    do_or_dry "$HOME/.local/bin/omarchy-default-agent" dsh
    echo "== 默认 AI 已设为 dsh${previous:+（原默认: $previous，卸载时自动还原）}"
  fi
else
  echo "== 未设置默认 AI（如需设为默认请加 --default 或之后运行: omarchy default agent dsh）"
fi

echo
echo "== 安装完成。验证/使用："
echo "   omarchy default agent          # 查看默认 AI"
echo "   omarchy agent                  # 打开 DSH Web（独立窗口；未设置默认时请先 --default）"
echo "   dsh-web --no-open              # 只确保服务运行"
echo "   卸载: $SELF_DIR/uninstall.sh [-n]"
