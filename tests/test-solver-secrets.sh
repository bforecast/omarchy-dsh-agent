#!/usr/bin/env bash
# Regression tests for dsh-solve-error secret handling.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOLVER="$ROOT/files/dsh-solve-error"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# 1) prompt no longer embeds context in argv (heredoc should not interpolate)
if grep -q '=== Error context ===' "$SOLVER"; then bad "context still embedded in prompt"; else ok; fi

# 2) redaction via --show-context (no send)
out=$(printf '' | HOME="$ROOT" "$SOLVER" --text 'Authorization: Bearer abc123 gho_abcdefgh12345678 api_key=hunter2 foo@example.com' --show-context 2>&1)
for secret in 'Bearer abc123' 'gho_abcdefgh12345678' 'hunter2' 'foo@example.com'; do
  if printf '%s' "$out" | grep -qF "$secret"; then bad "secret leaked: $secret"; else ok; fi
done

# 3) context file path usage (sanity)
if ! grep -q 'error-context.txt' "$SOLVER"; then bad "missing protected context file wiring"; else ok; fi
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
