#!/usr/bin/env bash
# Regression tests for dsh-solve-error secret handling with a mock `node`:
# diagnostics must reach the process only as a protected context file path
# (never inline), the file must be 0600/redacted, and cleanup must happen on
# both success and failure. Pass SOLVER=/path to test another copy.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOLVER="${SOLVER:-$ROOT/files/dsh-solve-error}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d); export TMP
mkdir -p "$TMP/home" "$TMP/fakedsh/apps/cli/src"
: > "$TMP/fakedsh/apps/cli/src/bin.ts"

# mock node: records argv, reads this run's ctx file, checks its mode and
# redacted content, exits with $MOCK_RC
cat > "$TMP/node" <<'C'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TMP/nodeargs.txt"
MOCK_RC="${MOCK_RC:-0}"
ctx=""
for a in "$@"; do
  if [[ $a == *"$HOME/.local/state/dsh-omarchy-agent/ctx."* ]]; then ctx="$a"; fi
done
ctx=$(printf '%s' "$@" | tr ' ' '\n' | grep -oE "$HOME/.local/state/dsh-omarchy-agent/ctx\\.[A-Za-z0-9]+" | head -1)
if [[ -n $ctx && -f $ctx ]]; then
  stat -c '%a' "$ctx" > "$TMP/ctxmode.txt"
  cp "$ctx" "$TMP/ctxcontent.txt"
  printf 'MOCK-OK' 
else
  printf 'MISSING'
fi
sleep 0.05
exit "$MOCK_RC"
C
chmod +x "$TMP/node"

SECRETS=$'Authorization: Bearer abc123\ngho_abcdefgh12345678\napi_key=hunter2\nfoo@example.com'
run_solver(){ PATH="$TMP:$PATH" HOME="$TMP/home" DSH_REPO="$TMP/fakedsh" MOCK_RC="${2:-0}" "$SOLVER" -y --text "$1"; }

# 1) per-line redaction via --show-context (each rule independently)
out=$(PATH="$TMP:$PATH" HOME="$TMP/home" "$SOLVER" --text "$SECRETS" --show-context 2>&1)
for secret in 'Bearer abc123' 'gho_abcdefgh12345678' 'hunter2' 'foo@example.com'; do
  if printf '%s' "$out" | grep -qF "$secret"; then bad "show-context leaked: $secret"; else ok; fi
done

# 2) success run through mock node: argv has no secrets, ctx is 0600/redacted,
#    ctx file removed afterwards, output present
out=$(run_solver "$SECRETS
MARKER-A1" 0); rc=$?
[[ $rc -eq 0 && "$out" == *"MOCK-OK"* ]] && ok || bad "success run rc=$rc out='$out'"
for secret in 'abc123' 'abcdefgh12345678' 'hunter2' 'foo@example.com'; do
  if grep -qF "$secret" "$TMP/nodeargs.txt" 2>/dev/null; then bad "secret in node argv: $secret"; else ok; fi
done
grep -qE 'ctx\.[A-Za-z0-9]+' "$TMP/nodeargs.txt" 2>/dev/null && ok || bad "no context path in node argv"
[[ "$(cat "$TMP/ctxmode.txt" 2>/dev/null)" == "600" ]] && ok || bad "ctx file mode not 0600"
grep -qF 'MARKER-A1' "$TMP/ctxcontent.txt" 2>/dev/null && ok || bad "marker missing from ctx content"
for secret in 'abc123' 'abcdefgh12345678' 'hunter2' 'foo@example.com'; do
  if grep -qF "$secret" "$TMP/ctxcontent.txt" 2>/dev/null; then bad "secret in ctx content: $secret"; else ok; fi
done
if ls "$TMP/home/.local/state/dsh-omarchy-agent"/ctx.* 2>/dev/null | grep -q .; then bad "ctx left after success"; else ok; fi

# 3) failure run: cleanup still happens
rm -f "$TMP/nodeargs.txt"
out=$(run_solver "$SECRETS
MARKER-A2" 5); rc=$?
[[ $rc -eq 5 ]] && ok || bad "failure run rc=$rc"
if ls "$TMP/home/.local/state/dsh-omarchy-agent"/ctx.* 2>/dev/null | grep -q .; then bad "ctx left after failure"; else ok; fi
if ls "$TMP/home/.local/state/dsh-omarchy-agent"/solve.* 2>/dev/null | grep -q .; then bad "work file left after failure"; else ok; fi
rm -rf "$TMP"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
