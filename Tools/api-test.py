"""Exercises the Derby Web Check In API like a browser would."""
import csv, io, json, sys, time, urllib.request, urllib.error, zipfile

BASE = sys.argv[1]
ROSTER = sys.argv[2]
failed = 0

# What to expect, worked out from the roster so any GPRM roster can be used.
rows = list(csv.DictReader(open(ROSTER, newline="", encoding="utf-8")))
used = {int(r["Car#"]) for r in rows if r["Car#"].strip().isdigit()}
def first_free(n, taken):
    while n in taken:
        n += 1
    return n
bear1 = first_free(400, used)
bear2 = first_free(400, used | {bear1})
owner_400 = next(f'{r["First Name"]} {r["Last Name"]}' for r in rows if r["Car#"] == "400")
lion_count = sum(1 for r in rows if r["Rank"] == "CS_K_Lions")

def check(name, ok):
    global failed
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        failed += 1

def call(method, path, body=None, raw=None):
    data, headers = None, {}
    if raw is not None:
        data = raw
    elif body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, r.read(), dict(r.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read(), dict(e.headers)

def state(method, path, body=None, raw=None):
    status, data, _ = call(method, path, body, raw)
    return status, json.loads(data)

for _ in range(40):
    try:
        call("GET", "/api/version"); break
    except Exception:
        time.sleep(0.25)

s, body, h = call("GET", "/")
check("serves the page", s == 200 and b"Derby Web Check In" in body)
for f in ["app.js", "styles.css", "icon.png"]:
    check(f"serves {f}", call("GET", "/" + f)[0] == 200)
check("unknown path is 404", call("GET", "/nope.html")[0] == 404)
check("path tricks are refused", call("GET", "/..%2F..%2Fetc%2Fpasswd")[0] == 404)

_, st = state("GET", "/api/state")
v0 = st["version"]
check("starts with the pack's 11 groups", len(st["event"]["groups"]) == 11)

_, st = state("POST", "/api/import", raw=open(ROSTER, "rb").read())
check("imports the roster", len(st["event"]["racers"]) == len(rows) and f"Imported {len(rows)}" in st["message"])
check("version goes up", st["version"] > v0)
_, st2 = state("POST", "/api/import", raw=open(ROSTER, "rb").read())
check("importing twice adds nothing", len(st2["event"]["racers"]) == len(rows))

bears = next(g for g in st["event"]["groups"] if g["rank"] == "CS_3_Bears")
_, st = state("POST", "/api/racers", {"rank": "CS_3_Bears"})
new_id = st["selected"]
new = next(r for r in st["event"]["racers"] if r["id"] == new_id)
check(f"new Bear gets car #{bear1}", new["carNumber"] == bear1 and new["subgroup"] == "Bears")
check("new racer can't check in without a name", "name" in (st["problems"][new_id]["checkIn"] or ""))

s, body, _ = call("POST", f"/api/racers/{new_id}/checkin")
check("check-in refused until ready", s == 409)

_, st = state("PATCH", f"/api/racers/{new_id}", {"firstName": "Pat", "lastName": "Tester", "carName": "A very long car name indeed"})
r = next(r for r in st["event"]["racers"] if r["id"] == new_id)
check("names saved", r["firstName"] == "Pat" and r["lastName"] == "Tester")
check("car name cut to 20 characters", r["carName"] == "A very long car name")

_, st = state("PATCH", f"/api/racers/{new_id}", {"weightOz": 4.9})
r = next(r for r in st["event"]["racers"] if r["id"] == new_id)
check("weight under 5 oz ticks the weight check", r["inspection"]["weightOK"] is True)

for field in ["dimensionsOK", "clearanceOK", "wheelsAxlesOK"]:
    state("PATCH", f"/api/racers/{new_id}", {"inspection": {field: True}})
_, st = state("PATCH", f"/api/racers/{new_id}", {"inspection": {"noLooseParts": True}})
r = next(r for r in st["event"]["racers"] if r["id"] == new_id)
check("all checks ticked marks it passed", r["inspection"]["passed"] is True)
check("changing one inspection field keeps the others", r["inspection"]["weightOK"] is True)

# Two computers editing different fields of the same racer at once
state("PATCH", f"/api/racers/{new_id}", {"notes": "from computer A"})
_, st = state("PATCH", f"/api/racers/{new_id}", {"carName": "Zoom"})
r = next(r for r in st["event"]["racers"] if r["id"] == new_id)
check("edits from two computers don't overwrite each other", r["notes"] == "from computer A" and r["carName"] == "Zoom")

_, st = state("PATCH", f"/api/racers/{new_id}", {"carNumber": 400})
check("duplicate car number is flagged", f"already used by {owner_400}" in (st["problems"][new_id]["carNumber"] or ""))
_, st = state("POST", f"/api/racers/{new_id}/next-number")
r = next(r for r in st["event"]["racers"] if r["id"] == new_id)
check("Next Available fixes it", r["carNumber"] == bear1)

_, st = state("POST", f"/api/racers/{new_id}/checkin")
r = next(r for r in st["event"]["racers"] if r["id"] == new_id)
check("checks in", r["checkedInAt"] is not None)

# A tiny JPEG made by the Mac's own tools would be ideal; a PNG works since the host re-encodes.
png = open(sys.argv[3], "rb").read()
_, st = state("PUT", f"/api/racers/{new_id}/photo/car", raw=png)
r = next(r for r in st["event"]["racers"] if r["id"] == new_id)
check("car photo uploaded", r["carPhoto"] is not None)
s, body, h = call("GET", "/photos/" + r["carPhoto"])
check("photo served as JPEG", s == 200 and body[:2] == b"\xff\xd8")
s, st = state("PUT", f"/api/racers/{new_id}/photo/car", raw=b"not an image")
check("bad image refused", s == 400)

_, st = state("POST", f"/api/racers/{new_id}/add-car")
second = st["selected"]
r2 = next(r for r in st["event"]["racers"] if r["id"] == second)
check("Add Another Car copies the racer and numbers it", r2["firstName"] == "Pat" and r2["lastName"] == "Tester" and r2["carNumber"] == bear2)

_, st = state("PATCH", "/api/settings", {"eventName": "Pack 352 Derby 2026", "maxWeightOz": 5.0})
check("settings saved", st["event"]["eventName"] == "Pack 352 Derby 2026")

lions = next(g for g in st["event"]["groups"] if g["rank"] == "CS_K_Lions")
_, st = state("PATCH", f"/api/groups/{lions['id']}", {"startNumber": 150, "subgroup": "Lion Cubs"})
g = next(g for g in st["event"]["groups"] if g["id"] == lions["id"])
check("group start number and name saved", g["startNumber"] == 150 and g["subgroup"] == "Lion Cubs")
check("renaming a subgroup updates its cars", all(r["subgroup"] == "Lion Cubs" for r in st["event"]["racers"] if r["rank"] == "CS_K_Lions"))
_, st = state("POST", f"/api/groups/{lions['id']}/renumber", {"onlyUnnumbered": False})
nums = sorted(r["carNumber"] for r in st["event"]["racers"] if r["rank"] == "CS_K_Lions")
check("renumber from 150", nums == list(range(150, 150 + lion_count)) and f"Numbered {lion_count}" in (st["message"] or ""))
_, st = state("PATCH", f"/api/groups/{lions['id']}", {"rank": "CS_3_Bears"})
check("duplicate Rank refused with a message", "already a group" in (st["message"] or ""))
_, st = state("DELETE", f"/api/groups/{bears['id']}")
check("group with cars can't be deleted", any(g["rank"] == "CS_3_Bears" for g in st["event"]["groups"]) and "Move them" in (st["message"] or ""))
_, st = state("POST", "/api/groups")
added = st["event"]["groups"][-1]
ids = [g["id"] for g in st["event"]["groups"]]
ids.insert(0, ids.pop())
_, st = state("PUT", "/api/groups/order", {"ids": ids})
check("groups can be reordered", st["event"]["groups"][0]["id"] == added["id"])
_, st = state("DELETE", f"/api/groups/{added['id']}")
check("empty group deleted", all(g["id"] != added["id"] for g in st["event"]["groups"]))

s, body, h = call("GET", "/api/export?checkedInOnly=1")
check("export is a zip download", s == 200 and h.get("Content-Type") == "application/zip" and "attachment" in h.get("Content-Disposition", ""))
z = zipfile.ZipFile(io.BytesIO(body))
names = z.namelist()
csv_name = next(n for n in names if n.endswith("GPRM Roster.csv"))
csv = z.read(csv_name).decode()
lines = csv.split("\r\n")
check("zip has the GPRM CSV with the right header", lines[0] == "First Name,Last Name,Car#,Car Name,Rank,Subgroup,Passed,Exclude,Finalist,Grand Finalist,Grand Turtle,ImageFile")
check("only the checked-in car is exported", len([l for l in lines[1:] if l]) == 1 and lines[1].startswith(f"Pat,Tester,{bear1},Zoom,CS_3_Bears,Bears,True"))
check("ImageFile points at the GPRM PC folder", lines[1].endswith(rf"GrandPrix Race Manager\Images\{bear1}.jpg"))
check("zip has the photo", any(n.endswith(f"Images/{bear1}.jpg") for n in names))

s, body, _ = call("GET", "/api/export")
check("full export blocked by the duplicate car number problem? (none expected)", s == 200)

_, st = state("DELETE", f"/api/racers/{second}")
check("racer deleted", all(r["id"] != second for r in st["event"]["racers"]))
s, body, _ = call("PATCH", f"/api/racers/{second}", {"notes": "x"})
check("editing a deleted racer says so", s == 404 and b"deleted on another computer" in body)

print("All checks passed" if failed == 0 else f"{failed} checks failed")
sys.exit(1 if failed else 0)
