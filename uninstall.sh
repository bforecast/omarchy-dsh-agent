#!/usr/bin/env bash
#
# omarchy-dsh-agent uninstall.sh -- remove everything install.sh installed.
#
# Usage:
#   ./uninstall.sh [-n] [-r <agent>]
#     -n          dry run
#     -r <agent>  default-AI restore target (fallback when no state file; default codex)
#
# Removes only files whose content matches this plugin; modified files are skipped with a warning.

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
  *) echo "uninstall.sh: unknown agent '$RESTORE_AGENT'" >&2; exit 1 ;;
esac

BIN="$HOME/.local/bin"
AGENT_FILE="$HOME/.config/omarchy/defaults/agent"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
STATE_DIR="$HOME/.local/state/dsh-omarchy-plugin"
STATE_FILE="$STATE_DIR/state"

# ---------- Default AI restore ----------
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
    echo "  [dry-run] default AI would be restored to ${target:-<clear default>}"
  elif [[ -z $target ]]; then
    rm -f "$AGENT_FILE"
    echo "== Cleared the default AI record"
  else
    if /usr/share/omarchy/bin/omarchy-default-agent "$target" >/dev/null 2>&1; then
      echo "== Default AI restored to $target"
    else
      printf '%s\n' "$target" >"$AGENT_FILE"
      echo "== Default AI restored to $target (wrote the record directly; make sure that agent is installed)"
    fi
  fi
else
  echo "== Current default AI is not dsh (=${current:-<unset>}); skipping default restore"
fi

# ---------- Remove wrappers (only files whose content matches this plugin) ----------
remove_one() {
  local path=$1 sentinel=$2
  if [[ ! -e $path ]]; then echo "== Skipped (not found): $path"; return; fi
  if ! grep -qF "$sentinel" "$path"; then
    echo "!! Skipped (content differs from this plugin; possibly modified): $path" >&2
    return
  fi
  if $DRY; then echo "  [dry-run] would delete $path"; else rm -f "$path"; echo "== Deleted $path"; fi
}
remove_one "$BIN/dsh-web" 'dsh-web -- Omarchy "AI agent" entry'
remove_one "$BIN/omarchy-default-agent" 'teaches `omarchy default agent` about the local DSH'
remove_one "$BIN/omarchy-agent" 'when the default agent is the local DSH agent'
remove_one "$BIN/omarchy" 'User extension wrapper for the `omarchy` CLI'
remove_one "$BIN/dsh-solve-error" 'dsh-solve-error -- collect an error context'

# ---------- Menu entry removal ----------
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
    print("== Menu plugin marker block not found; skipping")
    sys.exit(0)
keys = sum(1 for l in lines[start:end + 1] if l.lstrip().startswith('"'))
print(f"== Removing {keys} DSH menu key(s)" + (" (dry-run)" if dry else ""))
if dry:
    sys.exit(0)
del lines[start:end + 1]
while len(lines) >= 2 and lines[-2].strip() == "" and lines[-1].strip() == "}":
    del lines[-2]
with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
print("== Menu restored")
PY
else
  echo "== Skipped (menu file not found)"
fi

# ---------- Hyprland Agent keybinding block removal ----------
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
    print("== bindings.lua plugin block not found; skipping")
    sys.exit(0)
print("== Removing the Agent keybinding block (restores Omarchy default)" + (" (dry-run)" if dry else ""))
if dry:
    sys.exit(0)
del lines[start:end + 1]
# Trim extra blank lines around the removed block
while len(lines) >= 2 and lines[-2].strip() == "":
    del lines[-2]
while len(lines) >= 1 and lines[0].strip() == "":
    del lines[0]
with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
print("== Keybinding block removed")
PY
  if ! $DRY && command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 \
      && echo "   (hyprctl reload done; binding restored to the Omarchy default)" \
      || echo "   (hyprctl reload unavailable: takes effect at next graphical session, or run hyprctl reload manually)"
  fi
else
  echo "== Skipped (bindings.lua not found)"
fi

# ---------- Desktop-app registration removal (dsh.desktop + dsh.png icons) ----------
DESKTOP_FILE="$HOME/.local/share/applications/dsh.desktop"
ICON_ROOT="$HOME/.local/share/icons"
if [[ -f $DESKTOP_FILE ]] && grep -qF "omarchy-dsh-agent" "$DESKTOP_FILE"; then
  if $DRY; then
    echo "  [dry-run] would delete desktop entry $DESKTOP_FILE"
  else
    rm -f "$DESKTOP_FILE"
    echo "== Deleted desktop entry $DESKTOP_FILE"
    update-desktop-database "$(dirname "$DESKTOP_FILE")" >/dev/null 2>&1 || true
  fi
elif [[ -f $DESKTOP_FILE ]]; then
  echo "!! Desktop entry differs from this plugin (possibly modified); skipping: $DESKTOP_FILE" >&2
else
  echo "== Skipped (dsh.desktop not found)"
fi
if $DRY; then
  echo "  [dry-run] would delete dsh.png icons: $ICON_ROOT/hicolor/{48,64,128,256,512}x*/apps/dsh.png"
else
  rm -f "$ICON_ROOT"/hicolor/*x*/apps/dsh.png 2>/dev/null || true
  gtk-update-icon-cache -f "$ICON_ROOT/hicolor" >/dev/null 2>&1 || true
  echo "== Deleted dsh.png icons and refreshed the cache"
fi

# ---------- Leftover cleanup hints ----------
if ! $DRY; then
  echo
  echo "== Uninstall complete. Optional leftover cleanup:"
  echo "   rm -f $BIN/dsh-web.dshplugin.bak $BIN/dsh-solve-error.dshplugin.bak $BIN/omarchy-default-agent.dshplugin.bak"
  echo "   rm -f $BIN/omarchy-agent.dshplugin.bak $BIN/omarchy.dshplugin.bak"
  echo "   rm -f \"$MENU.dshplugin.bak\" \"$BINDFILE.dshplugin.bak\" $STATE_FILE; rmdir $STATE_DIR 2>/dev/null || true"
  echo "   rm -rf ~/.local/state/dsh                 # DSH run log"
fi
