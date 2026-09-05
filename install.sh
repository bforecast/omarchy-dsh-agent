#!/usr/bin/env bash
#
# omarchy-dsh-agent install.sh
#
# One-shot installer: register a local DeepSeek Harness (DSH) as an Omarchy AI agent.
#   1) Prepare the DSH source: clone into ~/deepseek-harness when missing, then
#      detached-checkout a pinned 40-hex commit (DSH_COMMIT / --repo-rev) and verify
#      HEAD; dependencies are installed with `pnpm install --frozen-lockfile`
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
#   ./install.sh [--default] [--with-widget] [--widget-url URL]
#                [--repo-dir PATH] [--repo-url URL] [--repo-rev <40-hex>]
#                [--use-existing] [--no-bootstrap] [--no-keybinding] [--dry-run]
#
# The DSH checkout is pinned to commit $DSH_COMMIT (env-overridable). A custom
# --repo-url without an explicit --repo-rev is refused.
# Reusing an existing DSH checkout requires it to sit at the pinned commit,
# or an explicit --use-existing (which skips HEAD verification).

set -euo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FILES="$SELF_DIR/files"

DRY=false
SET_DEFAULT=false
NO_BOOTSTRAP=false
NO_KEYBINDING=false
WITH_WIDGET=false
USE_EXISTING=false
WIDGET_URL="https://github.com/bforecast/omarchy-dsh-agent.git"
REPO_DIR="${DSH_REPO_DIR:-$HOME/deepseek-harness}"
REPO_URL="https://github.com/deepseek-ai/deepseek-harness.git"
# Pinned DeepSeek Harness commit (full SHA) fetched from the upstream default
# branch. Bump this deliberately and re-run the full install/uninstall cycle.
DSH_COMMIT="${DSH_COMMIT:-d347e703908d0406b7a7ef80e3a0e594d86b2215}"
REPO_REV="${DSH_REPO_REV:-}"

while (($#)); do
  case "$1" in
    --default) SET_DEFAULT=true ;;
    --with-widget) WITH_WIDGET=true ;;
    --widget-url) shift; WIDGET_URL=${1:?--widget-url needs a URL} ;;
    --repo-dir) shift; REPO_DIR=${1:?--repo-dir needs a path} ;;
    --repo-url) shift; REPO_URL=${1:?--repo-url needs a URL} ;;
    --repo-rev) shift; REPO_REV=${1:?--repo-rev needs a 40-hex commit} ;;
    --use-existing) USE_EXISTING=true ;;
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

do_or_dry mkdir -p "$HOME/.local/bin"

# ---------- 1) DSH source (pinned, detached) ----------
is_hex40() { [[ $1 =~ ^[0-9a-f]{40}$ ]]; }
pin=${REPO_REV:-$DSH_COMMIT}
if ! is_hex40 "$pin"; then
  echo "install.sh: invalid commit pin '$pin' (expected 40 lowercase hex chars; set --repo-rev or DSH_COMMIT)" >&2
  exit 1
fi

if [[ ! -f "$REPO_DIR/apps/cli/src/bin.ts" ]]; then
  # Target path exists but is not a usable DSH checkout: refuse and never touch it.
  if [[ -e $REPO_DIR ]]; then
    echo "install.sh: $REPO_DIR exists but is not a valid DSH checkout; refusing to modify it." >&2
    echo "   Remove it yourself or point --repo-dir elsewhere." >&2
    exit 1
  fi
  for c in git; do command -v "$c" >/dev/null 2>&1 || { echo "install.sh: missing '$c'" >&2; exit 1; }; done
  if [[ $REPO_URL != "https://github.com/deepseek-ai/deepseek-harness.git" && -z $REPO_REV ]]; then
    echo "install.sh: a custom --repo-url requires an explicit --repo-rev <40-hex-commit>" >&2
    exit 1
  fi
  echo "== DSH source not found ($REPO_DIR); preparing it at pinned commit $pin"
  tmpdir="$REPO_DIR.dsh-tmp.$$"
  if $DRY; then
    echo "  [dry-run] would prepare $tmpdir (git init, fetch commit $pin, detached checkout, verify) then atomically rename it to $REPO_DIR"
  else
    # Build in a sibling temporary directory first; only our own temp dir is
    # ever cleaned up, and the final rename is atomic.
    git init -q "$tmpdir" || { echo "install.sh: could not git init $tmpdir" >&2; exit 1; }
    git -C "$tmpdir" remote add origin "$REPO_URL" 2>/dev/null || true
    if ! git -C "$tmpdir" fetch --depth 1 origin "$pin"; then
      echo "install.sh: could not fetch pinned commit $pin from $REPO_URL" >&2
      rm -rf "$tmpdir"
      exit 1
    fi
    git -C "$tmpdir" checkout --detach "$pin"
    got=$(git -C "$tmpdir" rev-parse HEAD)
    if [[ $got != "$pin" ]]; then
      echo "install.sh: pinned checkout verification failed (HEAD=$got != $pin); removing temporary directory" >&2
      rm -rf "$tmpdir"
      exit 1
    fi
    mv "$tmpdir" "$REPO_DIR"
    echo "== Verified detached HEAD at $pin and moved checkout into place"
  fi
  say "DSH source ready: $REPO_DIR"
else
  # Existing checkout: honour the pin unless the user explicitly opts out.
  echo "== Found existing DSH source: $REPO_DIR"
  got=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || true)
  if [[ -n $got && $got != "$pin" && $USE_EXISTING == false ]]; then
    echo "install.sh: existing checkout is at $got, not the pinned commit $pin." >&2
    echo "   Update it to $pin, remove it (a fresh checkout is pinned automatically), or pass --use-existing to accept it as-is." >&2
    exit 1
  fi
  echo "== Using existing DSH checkout${got:+ (HEAD ${got:0:7})}"
fi

if ! $NO_BOOTSTRAP && [[ -f "$REPO_DIR/apps/cli/src/bin.ts" && ! -d "$REPO_DIR/node_modules" ]]; then
  if command -v pnpm >/dev/null 2>&1; then
    echo "== Installing DSH dependencies (pnpm install --frozen-lockfile)…"
    (cd "$REPO_DIR" && do_or_dry pnpm install --frozen-lockfile)
  else
    echo "!! pnpm not found; skipping dependency install. Run manually before starting dsh: cd $REPO_DIR && pnpm install --frozen-lockfile" >&2
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
  do_or_dry mkdir -p "$(dirname "$menu")"
  [[ -f $menu ]] && do_or_dry cp "$menu" "$menu.dshplugin.bak"
  python3 - "$menu" "$FILES/menu-entries.jsonc" "$(if $DRY; then echo 1; else echo 0; fi)" <<'PY'
import json, os, sys, tempfile

menu_path, snippet_path, dry = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
try:
    with open(menu_path, encoding="utf-8") as f:
        content = f.read()
except FileNotFoundError:
    content = "{\n}"          # missing file: start from an empty object

with open(snippet_path, encoding="utf-8") as f:
    snippet = f.read().rstrip("\n")

# Heal a missing closing brace, then append the snippet as new top-level
# members before the final "}", inserting a separator comma when needed.
text = content
if not text.rstrip().endswith("}"):
    text = text.rstrip() + "\n}\n"
idx = text.rfind("}")
if idx == -1:
    sys.exit("install: menu file has no closing '}'; cannot merge, please check " + menu_path)
prefix = text[:idx].rstrip()
last = prefix[-1:] if prefix else ""
sep = "" if last in ("{", ",") else ","
new = prefix + sep + "\n" + snippet + "\n" + text[idx:]

def strip_jsonc(text):
    out, i = [], 0
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

json.loads(strip_jsonc(new))  # validate before replacing anything
if not dry:
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(menu_path) or ".", prefix=".menu.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(new)
        os.replace(tmp, menu_path)   # atomic
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise
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
      do_or_dry mkdir -p "$(dirname "$bindfile")"
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
do_or_dry mkdir -p "$desktop_dir"
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
      target="$icon_root/$rel"
      mkdir -p "$(dirname "$target")"
      if [[ -e $target ]] && ! cmp -s "$icon" "$target"; then
        cp "$target" "$target.dshplugin.bak"
        echo "   (backed up existing icon -> $target.dshplugin.bak)"
      fi
      cp "$icon" "$target"
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
    do_or_dry bash -c "printf 'plugin_set=1\nprevious=%s\n' \"\$0\" > \"\$1\"" "$previous" "$state_file"
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
