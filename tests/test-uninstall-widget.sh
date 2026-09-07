#!/usr/bin/env bash
# Widget-removal regression: hermetic (temp HOME + mocked omarchy).
#  - clean git widget        -> removal path runs `omarchy plugin remove dsh-launcher --yes`
#  - tracked/staged/untracked-> auto-removal refused, dir kept, no plugin remove call
#  - --keep-widget           -> always kept
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNINSTALL="$ROOT/uninstall.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d); export TMP
HOME="$TMP/home"; export HOME
mkdir -p "$HOME/.config/omarchy/plugins" "$TMP/bin"
WD="$HOME/.config/omarchy/plugins/dsh-launcher"
mkdir -p "$WD"
cat > "$WD/manifest.json" <<'M'
{"schemaVersion":1,"id":"dsh-launcher","name":"DSH Launcher","version":"1.8.2","author":"bforecast","description":"x","kinds":["bar-widget"],"entryPoints":{"barWidget":"BarWidget.qml"}}
M
printf '// DSH Launcher bar widget (marketplace-safe).\n' > "$WD/BarWidget.qml"

# mock omarchy: records plugin-remove calls; honors MOCK_WIDGET_DIR to actually delete
cat > "$TMP/bin/omarchy" <<'C'
#!/usr/bin/env bash
log="$TMP/omarchy.log"
if [[ ${1:-} == plugin && ${2:-} == remove ]]; then
  printf '%s\n' "plugin remove $*" >> "$log"
  if [[ -n ${MOCK_WIDGET_DIR:-} && ${3:-} == dsh-launcher ]]; then
    rm -rf "$MOCK_WIDGET_DIR"
  fi
  exit 0
fi
printf '%s\n' "omarchy $*" >> "$log"
C
chmod +x "$TMP/bin/omarchy"

run_uninstall(){ PATH="$TMP/bin:$PATH" MOCK_WIDGET_DIR="$WD" "$UNINSTALL" "$@" >/dev/null 2>"$TMP/err.log"; echo $?; }
removed_calls(){ grep -c 'plugin remove dsh-launcher' "$TMP/omarchy.log" 2>/dev/null || echo 0; }

# 0) --keep-widget keeps regardless
run_uninstall --keep-widget >/dev/null
[[ -d $WD ]] && ok || bad "keep-widget removed the dir"
rm -f "$TMP/omarchy.log"

# 1) clean git widget -> removal path called
git -C "$WD" init -q; git -C "$WD" add -A; git -C "$WD" -c user.name=t -c user.email=t@t commit -qm base
run_uninstall >/dev/null
[[ $(removed_calls) -ge 1 ]] && ok || bad "clean widget: plugin remove not called"
[[ ! -d $WD ]] && ok || bad "clean widget: dir not removed by mock"

# 2) tracked modified -> refused, no call, dir kept
mkdir -p "$WD"; cp "$ROOT/files/dsh-web" /dev/null 2>/dev/null || true
printf '{"schemaVersion":1,"id":"dsh-launcher"}' > "$WD/manifest.json"
printf '// DSH Launcher bar widget (marketplace-safe).\n' > "$WD/BarWidget.qml"
git -C "$WD" init -q; git -C "$WD" add -A; git -C "$WD" -c user.name=t -c user.email=t@t commit -qm base
printf '\n// USER LOCAL CUSTOMIZATION\n' >> "$WD/BarWidget.qml"      # tracked file modified
rm -f "$TMP/omarchy.log"
run_uninstall >/dev/null
[[ $(removed_calls) -eq 0 ]] && ok || bad "tracked-modified: plugin remove was called"
[[ -d $WD ]] && ok || bad "tracked-modified: dir removed"
grep -q "uncommitted local changes" "$TMP/err.log" && ok || bad "tracked-modified: no fail-closed message"

# 3) staged modified -> refused
git -C "$WD" add BarWidget.qml
rm -f "$TMP/omarchy.log"
run_uninstall >/dev/null
[[ $(removed_calls) -eq 0 ]] && ok || bad "staged-modified: plugin remove was called"
[[ -d $WD ]] && ok || bad "staged-modified: dir removed"

# 4) untracked file -> refused
git -C "$WD" reset -q; git -C "$WD" checkout -q . 2>/dev/null || true
printf 'extra' > "$WD/untracked-file.txt"
rm -f "$TMP/omarchy.log"
run_uninstall >/dev/null
[[ $(removed_calls) -eq 0 ]] && ok || bad "untracked: plugin remove was called"
[[ -d $WD ]] && ok || bad "untracked: dir removed"
rm -rf "$TMP"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
