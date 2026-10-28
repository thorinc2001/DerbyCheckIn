#!/bin/bash
# Runs every check on both apps: the unit tests, then the web API test against a test server.
# Usage: Tools/check-all.sh [roster.csv] [scratch folder]   (the made-up sample roster by default)
# With a real GPRM roster it also checks that roster round-trips and prints a fingerprint
# of the export, so a refactor can prove the output is unchanged.
set -uo pipefail
cd "$(dirname "$0")/.."
roster=${1:-Tests/Fixtures/sample-roster.csv}
scratch=${2:-$(mktemp -d)}
rm -rf "$scratch"; mkdir -p "$scratch/web"
failed=0

echo "== unit tests"
export DERBY_ROSTER=$roster DERBY_EXPORT_OUT=$scratch/export.csv
results=$(swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
echo "$results" | grep -E 'error:|✘|Test run'
echo "$results" | grep -q '✘\|error:' && failed=1
echo "GPRM CSV fingerprint: $(shasum -a 256 "$scratch/export.csv" | cut -c1-16)"

echo "== web API"
swift build -c release 2>&1 | grep -E 'error:'
.build/release/DerbyWebCheckIn --data-folder "$scratch/web" --port 8099 >/dev/null 2>&1 &
server=$!
/usr/bin/python3 -I Tools/api-test.py http://localhost:8099 "$roster" Resources/AppIcon-1024.png | grep -E 'FAIL|^All checks|checks failed' || failed=1
kill $server 2>/dev/null
exit $failed
