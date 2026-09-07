#!/usr/bin/env bash
# Regression tests for dsh-balance.
# Modes are orthogonal to the auth check: the curl stub switches on TEST_MODE,
# so every negative branch is really exercised. Pass HELPER=/path to test a
# different copy (e.g. an older HEAD) and expect failures.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="${HELPER:-$ROOT/files/dsh-balance}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

if grep -qE -- '-H "Authorization' "$HELPER"; then bad "key still in curl argv"; else ok; fi
if ! grep -q -- '-H @-' "$HELPER"; then bad "missing stdin header transport"; else ok; fi

TMP=$(mktemp -d); export TMP
cat > "$TMP/curl" <<'C'
#!/usr/bin/env bash
printf 'ARGS=%s\n' "$*" > "$TMP/args.txt"
cat > "$TMP/stdin.txt"
mode="${TEST_MODE:-ok}"
case "$mode" in
  ok)        printf '{"balance_infos":[{"currency":"CNY","total_balance":"12.34"}]}' ;;
  oversize)  python3 -c "print('{\"balance_infos\":[{\"currency\":\"CNY\",\"total_balance\":\"'+('9'*100000)+'\"}]}')" ;;
  badjson)   printf 'not json' ;;
  longval)   python3 -c "print('{\"balance_infos\":[{\"currency\":\"CNY\",\"total_balance\":\"'+('9'*100)+'\"}]}')" ;;
  badcur)    printf '{"balance_infos":[{"currency":"cny","total_balance":"1.0"}]}' ;;
  boolcur)   printf '{"balance_infos":[{"currency":true,"total_balance":"1.0"}]}' ;;
  emptytotal)printf '{"balance_infos":[{"currency":"CNY","total_balance":""}]}' ;;
  nan)       printf '{"balance_infos":[{"currency":"CNY","total_balance":NaN}]}' ;;
  negative)  printf '{"balance_infos":[{"currency":"CNY","total_balance":"-1.0"}]}' ;;
  booltotal) printf '{"balance_infos":[{"currency":"CNY","total_balance":true}]}' ;;
  missingcur) printf '{"balance_infos":[{"total_balance":"1.00"}]}' ;;
  inttotal)   printf '{"balance_infos":[{"currency":"CNY","total_balance":1}]}' ;;
  floattotal) printf '{"balance_infos":[{"currency":"USD","total_balance":1.25}]}' ;;
  nulltotal)  printf '{"balance_infos":[{"currency":"CNY","total_balance":null}]}' ;;
  unsupportedcur) printf '{"balance_infos":[{"currency":"ABC","total_balance":"1.00"}]}' ;;
  *) exit 22 ;;
esac
C
chmod +x "$TMP/curl"
run(){ PATH="$TMP:$PATH" TEST_MODE="$1" DEEPSEEK_API_KEY="sk-secret-123" "$HELPER"; }

# positive
out=$(run ok); rc=$?
[[ $rc -eq 0 && "$out" == "12.34 CNY" ]] && ok || bad "valid payload (rc=$rc out='$out')"
grep -q -- "sk-secret-123" "$TMP/args.txt" && bad "key leaked into curl argv" || ok
grep -q -- "Authorization: Bearer sk-secret-123" "$TMP/stdin.txt" && ok || bad "header not on stdin"

# negatives: every mode must exit non-zero with empty stdout
for mode in oversize badjson longval badcur boolcur emptytotal nan negative booltotal missingcur inttotal floattotal nulltotal unsupportedcur; do
  out=$(run "$mode"); rc=$?
  if (( rc == 0 )); then bad "mode $mode unexpectedly succeeded (out='$out')"; else ok; fi
  if [[ -n $out ]]; then bad "mode $mode printed output"; else ok; fi
done
rm -rf "$TMP"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
