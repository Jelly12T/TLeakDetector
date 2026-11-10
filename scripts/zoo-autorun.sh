#!/usr/bin/env bash
#
# Runs every LeakZoo scenario on an iOS Simulator (--autorun, TLEAK_MODE=log) and grades what
# TLeakDetector reported, plus which screens deinit, against LeakZoo/expected.json.
# Writes the result table to LeakZoo/RESULTS.md.
#
# Usage:
#   scripts/zoo-autorun.sh [--udid UDID] [--output PATH]
#
# Exit codes: 0 = every scenario matches, 1 = mismatch, 2 = setup error.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT/LeakZoo/RESULTS.md"
UDID=""
BUNDLE_ID="vn.kalapa.TLeakDetector.LeakZoo"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --udid)    UDID="$2"; shift 2 ;;
    --output)  OUTPUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         echo "error: unknown option: $1" >&2; exit 2 ;;
  esac
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zoo-autorun.XXXXXX")"
LAUNCHER=""
cleanup() {
  [[ -n "$LAUNCHER" ]] && kill "$LAUNCHER" 2>/dev/null || true
  [[ -n "$UDID" ]] && xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT
die() {
  echo "error: $*" >&2
  [[ -f "$WORK/app.log" ]] && { echo "--- app output:" >&2; tail -20 "$WORK/app.log" >&2; }
  exit 2
}

if [[ -z "$UDID" ]]; then
  UDID="$(xcrun simctl list devices booted | grep -m1 -E '^\s+iPhone' | grep -oE '[0-9A-F-]{36}' || true)"
  [[ -n "$UDID" ]] || UDID="$(xcrun simctl list devices available | grep -m1 -E '^\s+iPhone' | grep -oE '[0-9A-F-]{36}' || true)"
fi
[[ -n "$UDID" ]] || die "no iPhone simulator found"

echo "==> Building LeakZoo (Debug) for $UDID"
xcodebuild build -project "$ROOT/LeakZoo/LeakZoo.xcodeproj" -scheme LeakZoo -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$WORK/DerivedData" > "$WORK/build.log" 2>&1 \
  || { tail -30 "$WORK/build.log" >&2; die "build failed"; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl install "$UDID" "$WORK/DerivedData/Build/Products/Debug-iphonesimulator/LeakZoo.app"

echo "==> Running every scenario"
START="$(date '+%Y-%m-%d %H:%M:%S')"
SIMCTL_CHILD_TLEAK_MODE=log xcrun simctl launch --console-pty --terminate-running-process \
  "$UDID" "$BUNDLE_ID" --autorun > "$WORK/app.log" 2>&1 &
LAUNCHER=$!
for _ in $(seq 1 180); do
  grep -q "autorun done" "$WORK/app.log" 2>/dev/null && break
  sleep 1
done
grep -q "autorun done" "$WORK/app.log" || die "autorun did not finish within 180 s"
# "autorun done" comes 2.5 s after the last close: wait past that close's T2 (8 s).
sleep 8
PID="$(pgrep -n -f "LeakZoo.app/LeakZoo" || true)"
[[ -n "$PID" ]] || die "LeakZoo is no longer running"

xcrun simctl spawn "$UDID" log show --start "$START" --style json \
  --predicate "subsystem == \"TLeakDetector\" AND processID == $PID" > "$WORK/reports.json" 2>/dev/null

COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)$(git -C "$ROOT" diff --quiet HEAD -- Sources LeakZoo || echo '+changes')"
XCODE="$(xcodebuild -version | sed -n 1p)"
SIMULATOR="$(xcrun simctl list devices -j | python3 -I -c '
import json, sys
udid = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        if device["udid"] == udid:
            version = runtime.rsplit(".", 1)[-1].replace("iOS-", "iOS ").replace("-", ".")
            print(device["name"] + ", " + version)
' "$UDID")"

python3 -I - "$ROOT/LeakZoo/expected.json" "$WORK/app.log" "$WORK/reports.json" "$OUTPUT" \
  "$COMMIT" "$XCODE" "$SIMULATOR" <<'PY'
import datetime, json, re, sys

expected_path, app_log, reports_path, output, commit, xcode, simulator = sys.argv[1:8]
scenarios = json.load(open(expected_path, encoding="utf-8"))["scenarios"]
app = open(app_log, encoding="utf-8", errors="replace").read()
opened = set(re.findall(r"\bopen (\S+)", app))
deinits = set(re.findall(r"\bdeinit (\S+)", app))

reports, config_errors = [], []
for entry in json.load(open(reports_path, encoding="utf-8")):
    message = entry.get("eventMessage", "")
    if entry.get("category") == "config":
        config_errors.append(message)
    elif entry.get("category") == "leak":
        def first(pattern):
            match = re.search(pattern, message)
            return match.group(1) if match else None
        reports.append({
            "type": first(r"LEAK ([\w.]+)"),
            "kind": first(r"kind: (\w+)"),
            "trigger": first(r"after (\w+) of"),
            "suppressed": "suppressed until" in message,
        })

def describe(report):
    if report["suppressed"]:
        return f"`{report['type']}` chỉ log (suppressed)"
    if report["kind"] == "budget":
        return f"`{report['type']}` vượt budget"
    return f"`{report['type']}` {report['kind']} sau {report['trigger']}"

EXPECTED = {
    "leak_cycle": "báo leak",
    "leak_rooted": "báo leak",
    "leak_budget": "báo vượt budget",
    "leak_suppressed": "chỉ log",
    "no_leak": "không báo",
    "allowed": "không báo",
}

def wanted(expectation, report):
    if expectation in ("leak_cycle", "leak_rooted"):
        return not report["suppressed"] and report["kind"] in ("screen", "outlived")
    if expectation == "leak_budget":
        return report["kind"] == "budget"
    if expectation == "leak_suppressed":
        return report["suppressed"]
    return False

rows, failures, claimed = [], 0, set()
for spec in scenarios:
    classes = {o["className"] for o in spec["objects"]}
    leaking = {o["className"] for o in spec["objects"] if o["leaks"]}
    mine = [r for r in reports if r["type"] in classes]
    claimed.update(id(r) for r in mine)
    good = [r for r in mine if wanted(spec["expectation"], r)]
    problems = []
    if spec["id"] not in opened:
        problems.append("không được mở")
    missing = leaking - {r["type"] for r in good} if spec["expectation"] not in ("no_leak", "allowed") else set()
    if missing:
        problems.append("không báo " + ", ".join(f"`{m}`" for m in sorted(missing)))
    problems += [f"báo thừa {describe(r)}" for r in mine if r not in good]
    for o in spec["objects"]:
        died = o["log"] in deinits
        if o["leaks"] and died:
            problems.append(f"`{o['log']}` deinit dù phải còn sống")
        if not o["leaks"] and not died:
            problems.append(f"`{o['log']}` không deinit")
    failures += bool(problems)
    actual = "<br>".join(describe(r) for r in mine) or "không báo"
    rows.append(f"| {spec['id']} | {spec['name']} | `{spec['expectation']}`: {EXPECTED[spec['expectation']]} "
                f"| {actual} | {'✅' if not problems else '❌ ' + '; '.join(problems)} |")

stray = [r for r in reports if id(r) not in claimed]
failures += len(stray) + len(config_errors)
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
lines = [
    "# Kết quả LeakZoo",
    "",
    f"Sinh bởi `scripts/zoo-autorun.sh` lúc {now}: commit `{commit}`, {xcode}, {simulator}.",
    "Mỗi scenario được mở rồi đóng (`--autorun`, `TLEAK_MODE=log`), rồi so report của TLeakDetector",
    "và log `deinit` của LeakZoo với [expected.json](expected.json).",
    "",
    f"**{len(scenarios) - (failures - len(stray) - len(config_errors))}/{len(scenarios)} scenario khớp.**",
    "",
    "| Case | Scenario | Mong đợi | Thực tế | Kết quả |",
    "|---|---|---|---|---|",
    *rows,
    "",
    "## Lệch đã chấp nhận",
    "",
    "- Leak `leak_cycle` và `leak_rooted` đều được báo với `kind: screen`. Đúng thiết kế: `kind` là điều quan sát được,",
    "  còn nguyên nhân (cycle hay rooted) sẽ là trường riêng khi có graph ở S3–4. Xem ADR 003.",
    "- Z05: cycle giữa hai màn hình được báo thành hai report, mỗi màn một report.",
]
if stray:
    lines += ["", "## Report không thuộc scenario nào", ""] + [f"- {describe(r)}" for r in stray]
if config_errors:
    lines += ["", "## Lỗi cấu hình", ""] + [f"- {e}" for e in config_errors]
open(output, "w", encoding="utf-8").write("\n".join(lines) + "\n")

print("\n".join(rows))
print(f"==> {'OK' if failures == 0 else 'FAIL'}: wrote {output}")
sys.exit(1 if failures else 0)
PY
