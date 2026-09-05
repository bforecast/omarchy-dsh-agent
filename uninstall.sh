#!/usr/bin/env bash
#
# omarchy-dsh-agent uninstall.sh -- remove what install.sh (and the optional
# --with-widget step) installed, conservatively:
#   * only removes files whose content matches this plugin;
#   * restores the .dshplugin.bak backups that install.sh took before it
#     overwrote pre-existing wrappers/desktop/icons;
#   * edits menu/bindings surgically (plugin marker blocks only) so post-install
#     user changes are kept;
#   * only deletes icons that hash-match the ones we installed;
#   * never touches the Chromium-installed "DeepSeek Harness" PWA unless
#     --remove-pwa is passed;
#   * never spawns installer windows and never modifies /usr/share/omarchy.
#
# Usage:
#   ./uninstall.sh [-n] [--keep-widget] [--remove-pwa] [-r <agent>]
#     -n            dry run: report actions, change nothing (no state removal)
#     --keep-widget keep the omarchy-managed bar widget (dsh-launcher)
#     --remove-pwa  also delete Chromium "DeepSeek Harness" PWA .desktop entries
#     -r <agent>    default-AI restore target (fallback when no state file; default codex)

set -euo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DRY=false
KEEP_WIDGET=false
REMOVE_PWA=false
RESTORE_AGENT="codex"
while (($#)); do
  case "$1" in
    -n | --dry-run) DRY=true ;;
    --keep-widget) KEEP_WIDGET=true ;;
    --remove-pwa) REMOVE_PWA=true ;;
    -r | --restore) shift; RESTORE_AGENT=${1:?need agent} ;;
    -h | --help) sed -n '1,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
BINDFILE="$HOME/.config/hypr/bindings.lua"
DESKTOP_FILE="$HOME/.local/share/applications/dsh.desktop"
ICON_ROOT="$HOME/.local/share/icons"
STATE_DIR="$HOME/.local/state/dsh-omarchy-plugin"
STATE_FILE="$STATE_DIR/state"

# Restore a pre-install backup (taken by install.sh as <file>.dshplugin.bak).
# Called only in the real (non-dry) run.
restore_backup() {
  local path=$1
  if [[ -f $path.dshplugin.bak ]]; then
    mv -f "$path.dshplugin.bak" "$path"
    echo "== Restored pre-install backup -> $path"
  fi
}

# ---------- Default AI restore ----------
current=""
[[ -f $AGENT_FILE ]] && read -r current <"$AGENT_FILE" || true
previous=""
plugin_set=""
if [[ -f $STATE_FILE ]]; then
  # Parse the state as plain data; never `source` it.
  plugin_set=$(sed -n 's/^plugin_set=\(.*\)$/\1/p' "$STATE_FILE" | tail -1)
  previous=$(sed -n 's/^previous=\(.*\)$/\1/p' "$STATE_FILE" | tail -1)
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
  else
    if [[ -z $target ]]; then
      rm -f "$AGENT_FILE"
      echo "== Cleared the default AI record"
    else
      # Write the record directly. Never delegate to the stock default-agent
      # setter: it may decide the agent is missing and pop up an interactive
      # install/presentation window (e.g. a Codex one).
      mkdir -p "$(dirname "$AGENT_FILE")"
      printf '%s\n' "$target" >"$AGENT_FILE"
      echo "== Default AI restored to $target"
    fi
    # Only after a real, successful restore: drop the state file.
    rm -f "$STATE_FILE"
    rmdir "$STATE_DIR" 2>/dev/null || true
  fi
else
  echo "== Current default AI is not dsh (=${current:-<unset>}); skipping default restore"
fi

# ---------- Remove wrappers (full byte match only) and restore backups ----------
# A wrapper is only removed when it is byte-identical to the bundled template;
# user modifications make it differ and are never deleted.
remove_one() {
  local name=$1
  local path="$BIN/$name"
  local bundle="$SELF_DIR/files/$name"
  if [[ ! -e $path ]]; then
    echo "== Skipped (not found): $path"
    return
  fi
  if [[ ! -f $bundle ]] || ! cmp -s "$path" "$bundle"; then
    echo "!! Skipped (content differs from the plugin template; possibly modified): $path" >&2
    return
  fi
  if $DRY; then
    echo "  [dry-run] would delete $path (and restore its pre-install backup, if any)"
  else
    rm -f "$path"
    echo "== Deleted $path"
    restore_backup "$path"
  fi
}
remove_one dsh-web
remove_one omarchy-default-agent
remove_one omarchy-agent
remove_one omarchy
remove_one dsh-solve-error

# ---------- Menu entry removal (surgical: marker block only) ----------
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
while lines and lines[-1].strip() == "":
    lines.pop()
if not lines or lines[-1].strip() != "}":
    lines.append("}\n")
with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
print("== Menu restored")
PY
  if ! $DRY; then
    # The .bak snapshot predates any user edits made after install; drop it so
    # it can never overwrite the surgically-clean current file.
    rm -f "$MENU.dshplugin.bak"
  fi
else
  echo "== Skipped (menu file not found)"
fi

# ---------- Hyprland Agent keybinding block removal (surgical) ----------
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
print("== Removing the Agent keybinding block" + (" (dry-run)" if dry else ""))
if dry:
    sys.exit(0)
del lines[start:end + 1]
while len(lines) >= 2 and lines[-2].strip() == "":
    del lines[-2]
while len(lines) >= 1 and lines[0].strip() == "":
    del lines[0]
with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
print("== Keybinding block removed")
PY
  if ! $DRY; then
    rm -f "$BINDFILE.dshplugin.bak"
  fi
  if ! $DRY && command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 \
      && echo "   (hyprctl reload done; binding restored to the Omarchy default)" \
      || echo "   (hyprctl reload unavailable: takes effect at next graphical session, or run hyprctl reload manually)"
  fi
else
  echo "== Skipped (bindings.lua not found)"
fi

# ---------- Desktop-app registration removal ----------
desktop_expected() {
  cat <<EOF
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
}
if [[ -f $DESKTOP_FILE ]]; then
  if [[ $(cat "$DESKTOP_FILE") == "$(desktop_expected)" ]]; then
    if $DRY; then
      echo "  [dry-run] would delete desktop entry $DESKTOP_FILE"
    else
      rm -f "$DESKTOP_FILE"
      echo "== Deleted desktop entry $DESKTOP_FILE"
      restore_backup "$DESKTOP_FILE"
      update-desktop-database "$(dirname "$DESKTOP_FILE")" >/dev/null 2>&1 || true
    fi
  else
    echo "!! Desktop entry differs from the plugin template (possibly modified); skipping: $DESKTOP_FILE" >&2
  fi
else
  echo "== Skipped (dsh.desktop not found)"
fi

# ---------- Icon removal (hash-matched against the bundled icons only) ----------
removed_any=false
for size in 48 64 128 256 512; do
  icon="$ICON_ROOT/hicolor/${size}x${size}/apps/dsh.png"
  bundle="$SELF_DIR/files/icons/hicolor/${size}x${size}/apps/dsh.png"
  if [[ ! -f $icon ]]; then
    continue
  fi
  if [[ -f $bundle ]] && [[ $(sha256sum "$icon" | awk '{print $1}') == $(sha256sum "$bundle" | awk '{print $1}') ]]; then
    if $DRY; then
      echo "  [dry-run] would delete icon (hash matches installed copy): $icon"
    else
      rm -f "$icon"
      echo "== Deleted icon (hash matches installed copy): $icon"
      removed_any=true
      # restore whatever was there before this plugin installed over it
      if [[ -f $icon.dshplugin.bak ]]; then
        mv -f "$icon.dshplugin.bak" "$icon"
        echo "== Restored pre-install icon -> $icon"
      fi
    fi
  else
    echo "!! Icon differs from the installed copy or no bundle reference; skipping: $icon" >&2
  fi
done
if ! $DRY && $removed_any; then
  gtk-update-icon-cache -f "$ICON_ROOT/hicolor" >/dev/null 2>&1 || true
fi

# ---------- Bar widget (omarchy plugin system) removal ----------
WIDGET_ID="dsh-launcher"
WIDGET_DIR="$HOME/.config/omarchy/plugins/$WIDGET_ID"
if $KEEP_WIDGET; then
  echo "== Skipped bar-widget removal (--keep-widget)"
elif [[ -d $WIDGET_DIR ]] \
    && grep -qF '"id": "dsh-launcher"' "$WIDGET_DIR/manifest.json" 2>/dev/null \
    && grep -qF "DSH Launcher bar widget." "$WIDGET_DIR/BarWidget.qml" 2>/dev/null; then
  if $DRY; then
    echo "  [dry-run] would remove the bar widget: omarchy plugin remove $WIDGET_ID --yes"
  else
    if omarchy plugin remove "$WIDGET_ID" --yes >/dev/null 2>&1; then
      echo "== Removed bar widget: $WIDGET_ID"
    else
      echo "!! Could not remove the bar widget automatically; run manually:" >&2
      echo "   omarchy plugin remove $WIDGET_ID --yes" >&2
    fi
  fi
elif [[ -d $WIDGET_DIR ]]; then
  echo "!! Bar widget exists but differs from this plugin; not removing: $WIDGET_DIR" >&2
else
  echo "== No bar widget installed (plugin-managed dsh-launcher not found)"
fi

# ---------- Chromium PWA entry cleanup (opt-in) ----------
# install.sh never creates the Chromium "DeepSeek Harness" PWA, so by default we
# do not delete it either -- only with an explicit --remove-pwa.
if $REMOVE_PWA; then
  found_pwa=false
  for f in "$HOME/.local/share/applications"/chrome-*-Default.desktop "$HOME"/chrome-*-Default.desktop; do
    if [[ -f $f ]] \
        && grep -qiE '^Name=(DeepSeek Harness|DSH)' "$f" \
        && grep -qE '^Exec=.*(chromium|chrome|google-chrome)' "$f" \
        && grep -qE -- '--app-id=' "$f"; then
      if $DRY; then
        echo "  [dry-run] would delete PWA desktop entry $f"
      else
        rm -f "$f"
        echo "== Deleted PWA desktop entry $f"
      fi
      found_pwa=true
    fi
  done
  if ! $DRY && $found_pwa; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi
  if ! $found_pwa; then
    echo "== No DeepSeek Harness PWA desktop entry found; skipping"
  fi
else
  echo "== Chromium PWA entry kept (pass --remove-pwa to delete it)"
fi

# ---------- Leftover cleanup hints ----------
if ! $DRY; then
  echo
  echo "== Uninstall complete."
  echo "   Optional leftover cleanup: rm -rf ~/.local/state/dsh   # DSH run log"
  echo "   rm -f ~/.local/bin/*.dshplugin.bak.* .../dsh.desktop.dshplugin.bak.*   # timestamped upgrade snapshots, if any"
fi
