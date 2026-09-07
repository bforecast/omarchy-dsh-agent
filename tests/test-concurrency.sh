#!/usr/bin/env bash
# Concurrent-invocation regression for dsh-solve-error: two simultaneous runs in
# the same HOME must each read their own context (unique files) and clean up.
# Pass SOLVER=/path to test another copy (an older HEAD with one fixed context
# path is expected to FAIL here).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOLVER="${SOLVER:-$ROOT/files/dsh-solve-error}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d); export TMP
mkdir -p "$TMP/home" "$TMP/fakedsh/apps/cli/src"
: > "$TMP/fakedsh/apps/cli/src/bin.ts"
cat > "$TMP/node" <<'C'
#!/usr/bin/env bash
ctx=$(printf '%s' "$@" | tr ' ' '\n' | grep -oE "$HOME/.local/state/dsh-omarchy-agent/ctx\\.[A-Za-z0-9]+" | head -1)
sleep 0.6   # widen the overlap window between the two runs
if [[ -n $ctx && -f $ctx ]]; then cat "$ctx"; else printf 'MISSING'; fi
C
chmod +x "$TMP/node"

run_one(){ PATH="$TMP:$PATH" HOME="$TMP/home" DSH_REPO="$TMP/fakedsh" "$SOLVER" -y --text "$1" >"$TMP/out_$2.txt" 2>/dev/null; echo $? > "$TMP/rc_$2.txt"; }
run_one "CONCURRENT-MARKER-ONE" one &
p1=$!
run_one "CONCURRENT-MARKER-TWO" two &
p2=$!
wait $p1; wait $p2

out1=$(cat "$TMP/out_one.txt"); out2=$(cat "$TMP/out_two.txt")
printf '%s' "$out1" | grep -qF "CONCURRENT-MARKER-ONE" && ok || bad "run1 got wrong/missing content: $out1"
printf '%s' "$out1" | grep -qF "MISSING" && bad "run1 saw MISSING (shared file deleted?)" || ok
printf '%s' "$out2" | grep -qF "CONCURRENT-MARKER-TWO" && ok || bad "run2 got wrong/missing content: $out2"
printf '%s' "$out2" | grep -qF "MISSING" && bad "run2 saw MISSING" || ok
[[ $(cat "$TMP/rc_one.txt") == 0 && $(cat "$TMP/rc_two.txt") == 0 ]] && ok || bad "non-zero rc"

left=$(ls "$TMP/home/.local/state/dsh-omarchy-agent"/ctx.* "$TMP/home/.local/state/dsh-omarchy-agent"/solve.* 2>/dev/null | wc -l)
[[ $left -eq 0 ]] && ok || bad "$left ctx/solve files left behind"
rm -rf "$TMP"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
