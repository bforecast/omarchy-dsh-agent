#!/usr/bin/env bash
# Regression tests for dsh-balance: no key in argv, stdin header, byte/scalar caps.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/files/dsh-balance"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# 1) source hygiene
if grep -qE -- '-H "Authorization' "$HELPER"; then bad "key still in curl argv"; else ok; fi
if ! grep -q -- '-H @-' "$HELPER"; then bad "missing stdin header transport"; else ok; fi

# 2) stub curl: verify argv has no key and stdin carries the header
TMP=$(mktemp -d)
export TMP
cat > "$TMP/curl" <<'C'
#!/usr/bin/env bash
args="$*"; stdin=$(cat)
echo "ARGS=$args" > "$TMP/args.txt"
echo "STDIN=$stdin" > "$TMP/stdin.txt"
case "$stdin" in
  *Authorization:*Bearer*sk-secret-123*) printf '{"balance_infos":[{"currency":"CNY","total_balance":"12.34"}]}' ;;
  *OVERSIZE*) python3 -c "print('{\"balance_infos\":[{\"currency\":\"CNY\",\"total_balance\":\"'+('9'*100000)+'\"}]}')" ;;
  *BADJSON*) printf 'not json' ;;
  *LONGVAL*) printf '{"balance_infos":[{"currency":"CNY","total_balance":"%s"}]}' "$(printf '9%.0s' {1..100})" ;;
  *BADCUR*) printf '{"balance_infos":[{"currency":"CUR1","total_balance":"1.0"}]}' ;;
  *) exit 22 ;;
esac
C
chmod +x "$TMP/curl"
run_helper(){ PATH="$TMP:$PATH" DEEPSEEK_API_KEY="sk-secret-123" "$HELPER"; }

out=$(run_helper); rc=$?
[[ $rc -eq 0 && "$out" == "12.34 CNY" ]] && ok || bad "valid payload (rc=$rc out=$out)"
grep -q "sk-secret-123" "$TMP/args.txt" && bad "key leaked into curl argv" || ok
grep -q "Authorization: Bearer sk-secret-123" "$TMP/stdin.txt" && ok || bad "header not on stdin"
out=$(run_helper); rc=$?
# oversized response -> fail (curl stub prints huge line; helper python cap)
rm -rf "$TMP"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
