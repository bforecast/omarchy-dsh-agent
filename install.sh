#!/usr/bin/env bash
#
# omarchy-dsh-agent install.sh
#
# One-shot installer: register a local DeepSeek Harness (DSH) as an Omarchy AI agent.
#   1) Prepare the DSH source: git clone into ~/deepseek-harness when missing (override with --repo-dir / --repo-url)
#   2) Install the launcher ~/.local/bin/dsh-web and three user-level wrappers (omarchy-default-agent / omarchy-agent / omarchy)
#   3) Merge menu entries into ~/.config/omarchy/extensions/omarchy-menu.jsonc (idempotent), rebind the Hyprland
#      default-AI key (SUPER + SHIFT + CTRL + A) to the wrapper's absolute path (skip with --no-keybinding),
#      and register DSH as a desktop application with the official icon (real icon in app search/menus)
#   4) Optional --default: point the default AI record at dsh (previous value recorded so uninstall can restore it)
#   5) Optional --with-widget: also install and enable the top-bar "dsh-launcher"
#      widget through `omarchy plugin add` (--widget-url overrides the repo source)
#
# All writes stay under the user home; /usr/share/omarchy is never modified. Re-runnable (idempotent).
#
# Usage:
#   ./install.sh [--default] [--with-widget] [--widget-url URL] [--repo-dir PATH] [--repo-url URL]
#                [--no-bootstrap] [--no-keybinding] [--dry-run]

set -euo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FILES="$SELF_DIR/files"

DRY=false
SET_DEFAULT=false
NO_BOOTSTRAP=false
NO_KEYBINDING=false
WITH_WIDGET=false
WIDGET_URL="https://github.com/bforecast/omarchy-dsh-agent.git"
REPO_DIR="${DSH_REPO_DIR:-$HOME/deepseek-harness}"
REPO_URL="https://github.com/deepseek-ai/deepseek-harness.git"

while (($#)); do
  case "$1" in
    --default) SET_DEFAULT=true ;;
    --with-widget) WITH_WIDGET=true ;;
    --widget-url) shift; WIDGET_URL=${1:?--widget-url needs a URL} ;;
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
do_or_dry() { if $DRY; then echo "  [dry-run] would run: $*"; else "$@"; fi; }

mkdir -p "$HOME/.local/bin"

# ---------- 1) DSH source ----------
if [[ ! -f "$REPO_DIR/apps/cli/src/bin.ts" ]]; then
  for c in git; do command -v "$c" >/dev/null 2>&1 || { echo "install.sh: missing '$c'" >&2; exit 1; }; done
  echo "== DSH source not found ($REPO_DIR); cloning $REPO_URL"
  do_or_dry git clone --depth 1 "$REPO_URL" "$REPO_DIR"
  say "DSH source ready: $REPO_DIR"
else
  echo "== Reusing existing DSH source: $REPO_DIR"
fi

if ! $NO_BOOTSTRAP && [[ -f "$REPO_DIR/apps/cli/src/bin.ts" && ! -d "$REPO_DIR/node_modules" ]]; then
  if command -v pnpm >/dev/null 2>&1; then
    echo "== Installing DSH dependencies (pnpm install)…"
    (cd "$REPO_DIR" && do_or_dry pnpm install)
  else
    echo "!! pnpm not found; skipping dependency install. Run manually before starting dsh: cd $REPO_DIR && pnpm install" >&2
  fi
fi

# ---------- 2) Launcher + wrappers ----------
install_one() {
  local name=$1 src="$FILES/$1" dst="$HOME/.local/bin/$1"
  if [[ ! -f $src ]]; then echo "install.sh: missing payload: $src" >&2; exit 1; fi
  if [[ -f $dst ]] && ! cmp -s "$src" "$dst"; then
    do_or_dry cp "$dst" "$dst.dshplugin.bak"
    say "Backed up previous file -> $dst.dshplugin.bak"
  fi
  if $DRY; then
    echo "  [dry-run] would install $name -> $dst"
  else
    install -m 0755 "$src" "$dst"
  fi
  say "Installed $name"
}
install_one dsh-web
install_one omarchy-default-agent
install_one omarchy-agent
install_one omarchy
install_one dsh-solve-error

# ---------- 3) Menu merge (idempotent) ----------
menu="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
if [[ -f $menu ]] && grep -qF "// Local DeepSeek Harness (DSH) -- AI agent entry" "$menu"; then
  echo "== Menu already contains the DSH entry; skipping"
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

# Heal a missing closing brace (a previous merge/removal may have consumed it),
# then insert the snippet right before the final "}".
text = content
if not text.rstrip().endswith("}"):
    text = text.rstrip() + "\n}\n"
idx = text.rfind("}")
if idx == -1:
    sys.exit("install: menu file has no closing '}'; cannot merge, please check " + menu_path)
new = text[:idx] + "\n" + snippet + text[idx:]

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

json.loads(strip_jsonc(new))  # validate: fail loudly if broken
if not dry:
    with open(menu_path, "w", encoding="utf-8") as f:
        f.write(new)
print("== Menu merged with DSH entry")
PY
fi

# ---------- 3.5) Hyprland default-AI key (absolute path; avoids the exec-PATH issue) ----------
if ! $NO_KEYBINDING; then
  bindfile="$HOME/.config/hypr/bindings.lua"
  # Only write when an Omarchy/Hyprland keybinding system is detected
  if command -v hyprctl >/dev/null 2>&1 || [[ -d /usr/share/omarchy/default/hypr ]]; then
    if [[ -f $bindfile ]] && grep -qF -- "-- BEGIN omarchy-dsh-agent" "$bindfile"; then
      echo "== Keybinding already present; skipping"
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
        echo "  [dry-run] would write the Agent keybinding to $bindfile"
      else
        printf '\n%s\n' "$block" >>"$bindfile"
        echo "== Wrote Agent keybinding: SUPER + SHIFT + CTRL + A -> $HOME/.local/bin/omarchy-agent"
        if command -v hyprctl >/dev/null 2>&1; then
          hyprctl reload >/dev/null 2>&1 \
            && echo "   (hyprctl reload done; active now)" \
            || echo "   (hyprctl reload unavailable: takes effect at next graphical session, or run hyprctl reload manually)"
        fi
      fi
    fi
  else
    echo "== No Hyprland/Omarchy keybinding system detected; skipping keybinding"
  fi
else
  echo "== Skipped Hyprland keybinding (--no-keybinding)"
fi

# ---------- 3.6) Register as a desktop application with the official icon ----------
desktop_dir="$HOME/.local/share/applications"
desktop_file="$desktop_dir/dsh.desktop"
icon_root="$HOME/.local/share/icons"
mkdir -p "$desktop_dir"
if [[ -f $desktop_file ]] && grep -qF "DeepSeek Harness" "$desktop_file" \
    && grep -qF "$HOME/.local/bin/dsh-web" "$desktop_file"; then
  echo "== DSH desktop entry already present; skipping"
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
    echo "  [dry-run] would write desktop entry $desktop_file"
  else
    printf '%s\n' "$desktop" >"$desktop_file"
    echo "== Wrote desktop entry $desktop_file"
  fi
fi
if [[ -d $FILES/icons ]]; then
  if $DRY; then
    echo "  [dry-run] would install official icons to $icon_root/hicolor"
  else
    while IFS= read -r icon; do
      rel="${icon#"$FILES/icons/"}"
      mkdir -p "$icon_root/$(dirname "$rel")"
      cp "$icon" "$icon_root/$rel"
    done < <(find "$FILES/icons" -type f -name "*.png")
    gtk-update-icon-cache -f "$icon_root/hicolor" >/dev/null 2>&1 || true
    update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true
    echo "== Official icons installed to $icon_root/hicolor"
  fi
fi

# ---------- 4) Optional: set as the default AI ----------
if $SET_DEFAULT; then
  state_dir="$HOME/.local/state/dsh-omarchy-plugin"
  state_file="$state_dir/state"
  previous=""
  if [[ -f "$HOME/.config/omarchy/defaults/agent" ]]; then
    read -r previous <"$HOME/.config/omarchy/defaults/agent" || true
  fi
  if [[ $previous == "dsh" ]]; then
    echo "== Default AI is already dsh"
  else
    do_or_dry mkdir -p "$state_dir"
    do_or_dry bash -c "printf 'plugin_default_set=1\nprevious_agent=%q\n' \"\$0\" > \"\$1\"" "$previous" "$state_file"
    do_or_dry "$HOME/.local/bin/omarchy-default-agent" dsh
    echo "== Default AI set to dsh${previous:+ (previous default: $previous; restored on uninstall)}"
  fi
else
  echo "== Default AI not set (add --default or run later: omarchy default agent dsh)"
fi

# ---------- 5) Optional: top-bar widget (omarchy plugin system) ----------
# Agent registration is install.sh's job; the bar icon is a shell plugin in this
# repository installed through `omarchy plugin add` -- a separate channel.
# --with-widget runs that channel too so one command reproduces the whole setup.
if $WITH_WIDGET; then
  if ! command -v omarchy >/dev/null 2>&1; then
    echo "!! omarchy CLI not found; skipping bar widget (add it later with: omarchy plugin add $WIDGET_URL --yes --enable)" >&2
  else
    widget_dir="$HOME/.config/omarchy/plugins/dsh-launcher"
    if [[ -d $widget_dir ]] && grep -qF "dsh-launcher" "$HOME/.config/omarchy/shell.json" 2>/dev/null; then
      echo "== Bar widget already installed and enabled; skipping"
    else
      if $DRY; then
        echo "  [dry-run] would add and enable the bar widget: omarchy plugin add $WIDGET_URL --yes --enable"
      else
        if omarchy plugin add "$WIDGET_URL" --yes --enable; then
          omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
          omarchy plugin enable dsh-launcher >/dev/null 2>&1 || true
          echo "== Bar widget installed and enabled (dsh-launcher)"
        else
          echo "!! Could not add the bar widget; run it manually:" >&2
          echo "   omarchy plugin add $WIDGET_URL --yes --enable" >&2
        fi
      fi
    fi
  fi
else
  echo "== Bar widget not installed (add --with-widget, or run: omarchy plugin add $WIDGET_URL --yes --enable)"
fi

echo
echo "== Install complete. Verify / use:"
echo "   omarchy default agent          # show the current default AI"
echo "   omarchy agent                  # open DSH Web (add --default if no default agent is set yet)"
echo "   dsh-web --no-open              # only ensure the server is running"
echo "   Uninstall: $SELF_DIR/uninstall.sh [-n]"
