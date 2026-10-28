#!/bin/bash
# Runs every check on both apps against the sample roster, using throwaway folders.
# Usage: Tools/check-all.sh <roster.csv> <scratch folder>
# Prints a fingerprint of the exported GPRM CSV, so a refactor can prove the output is unchanged.
set -uo pipefail
cd "$(dirname "$0")/.."
roster=$1; scratch=$2
rm -rf "$scratch"; mkdir -p "$scratch"/{rt,grp,sto,web}
swift build -c release 2>&1 | grep -E 'error|warning:' ; true
bin=.build/release
failed=0

echo "== round trip"
$bin/DerbyCheckIn --roundtrip "$roster" "$scratch/rt" | head -2
csv=$(ls "$scratch"/rt/*Export*/"GPRM Roster.csv")
echo "GPRM CSV fingerprint: $(shasum -a 256 "$csv" | cut -c1-16)"

echo "== groups"
printf '{"eventName":"x","groups":[{"rank":"CS_K_Lions","subgroup":"Lions"},{"rank":"CS_2_Wolves","subgroup":"Wolves"},{"rank":"CS_3_Bears","subgroup":"Bears"},{"rank":"CS_4_Webelos","subgroup":"Webelos"},{"rank":"CS_5_AOL","subgroup":"Arrow of Light"},{"rank":"GS_2nd_1486","subgroup":"GS_2nd_1486"},{"rank":"GS_3rd_1461","subgroup":"GS_3rd_1461"},{"rank":"GS_4th_1422","subgroup":"GS_4th_1422"},{"rank":"GS_4th_1797","subgroup":"GS_4th_1797"},{"rank":"GS_5th_1476","subgroup":"GS_5th_1476"},{"rank":"Outlaw","subgroup":"Test Race"}],"maxWeightOz":5,"imageFolderOnPC":"","racers":[]}' > "$scratch/old-event.json"
$bin/DerbyCheckIn --grouptest "$roster" "$scratch/old-event.json" "$scratch/grp" | grep -E 'FAIL|checks' || failed=1

echo "== storage"
$bin/DerbyCheckIn --storagetest "$scratch/sto" | grep -E 'FAIL|checks' || failed=1

echo "== web API"
$bin/DerbyWebCheckIn --data-folder "$scratch/web" --port 8099 >/dev/null 2>&1 &
server=$!
/usr/bin/python3 -I Tools/api-test.py http://localhost:8099 "$roster" Resources/AppIcon-1024.png | grep -E 'FAIL|checks' || failed=1
kill $server 2>/dev/null
exit $failed
