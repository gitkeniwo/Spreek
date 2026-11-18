#!/usr/bin/env bash
# Acceptance gate: SpreekCore tests + app build. Run from anywhere.
set -euo pipefail

cd "$(dirname "$0")/.."

step="start"
start=$SECONDS
trap 'echo "FAIL: verify.sh failed during \"$step\" after $((SECONDS - start))s" >&2' ERR

# Explains a failed `swift test` run from its log: failing tests, or (when the test process
# crashed, which swift test reports with no message at all) the tests that never finished.
report_test_failure() {
  local log=$1
  echo
  if grep -qE '^(✔|✘) Test run with' "$log"; then
    echo "==> failing tests / issues:"
    grep -E '^✘|^error:|: error:' "$log" | head -40 || true
  elif grep -q 'Test run started' "$log"; then
    echo "==> the test process died mid-run (crash). Tests started but never finished:"
    awk '
      /^◇ Test (case |run started)/ { next }
      /^◇ Test .* started\.$/ { name = $0; sub(/^◇ Test /, "", name); sub(/ started\.$/, "", name); running[name] = 1 }
      /^(✔|✘) Test / {
        name = $0; sub(/^(✔|✘) Test /, "", name)
        sub(/ (with [0-9]+ test cases? )?(passed|failed|recorded).*$/, "", name); delete running[name]
      }
      END { for (name in running) print "  " name }
    ' "$log"
    local report
    report=$(ls -t ~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-*.ips 2>/dev/null | head -1 || true)
    [[ -n $report ]] && echo "    newest crash report: $report"
  else
    echo "==> build or harness failure:"
    grep -E '^error:|: error:' "$log" | head -40 || true
  fi
  echo
  echo "==> last 40 lines of swift test output:"
  tail -n 40 "$log"
}

step="swift test"
echo "==> swift test (SpreekCore)"
test_log="$(mktemp -t spreek-swift-test)"
if ! swift test --package-path Packages/SpreekCore 2>&1 | tee "$test_log"; then
  report_test_failure "$test_log" >&2
  rm -f "$test_log"
  false
fi
rm -f "$test_log"

step="xcodegen generate"
echo "==> xcodegen generate"
xcodegen generate --quiet

step="xcodebuild build"
echo "==> xcodebuild build (Debug, unsigned)"
xcodebuild -project Spreek.xcodeproj -scheme Spreek -destination 'platform=macOS' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet

echo "PASS: core tests + app build in $((SECONDS - start))s"
