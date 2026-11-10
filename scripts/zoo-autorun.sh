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
SIMCTL_CHILD_TLEAK_MODE=log SIMCTL_CHILD_TLEAK_VERBOSE=1 xcrun simctl launch --console-pty --terminate-running-process \
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

xcrun simctl spawn "$UDID" log show --start "$START" --style json --info --debug \
  --predicate "subsystem == \"TLeakDetector\" AND processID == $PID" > "$WORK/reports.json" 2>/dev/null

COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
git -C "$ROOT" diff --quiet HEAD -- Sources LeakZoo 2>/dev/null || COMMIT+="+changes"
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

# Long reports are logged in pieces: glue each "(continued)" piece back onto the one before.
entries = []
for entry in json.load(open(reports_path, encoding="utf-8")):
    message = entry.get("eventMessage", "")
    if message.startswith("[TLeakDetector] (continued)") and entries:
        entries[-1]["eventMessage"] += message[len("[TLeakDetector] (continued)"):]
    else:
        entries.append(dict(entry))

reports, config_errors, searches, warnings = [], [], {}, []
for entry in entries:
    message = entry.get("eventMessage", "")
    def first(pattern):
        match = re.search(pattern, message)
        return match.group(1) if match else None
    if entry.get("category") == "config":
        config_errors.append(message)
    elif entry.get("category") == "warning":
        warnings.append({"pattern": first(r"WARNING (\w+):"), "root": first(r"seen when ([\w.]+) closed"),
                         "detail": first(r"WARNING \w+: (.*)")})
    elif entry.get("category") == "mark" and message.startswith("graph "):
        # graph <Type>: <n> objects in <ms> ms over <k> slices, longest <ms> ms, <outcome>
        searches[first(r"^graph ([\w.]+):")] = (int(first(r": (\d+) objects") or 0), float(first(r"in ([\d.]+) ms") or 0),
                                                 int(first(r"over (\d+) slices") or 0), float(first(r"longest ([\d.]+) ms") or 0))
    elif entry.get("category") == "leak":
        holder = first(r"(?m)^  held by (?:a running |a scheduled |a |an )?(Task|Timer|CADisplayLink|NotificationCenter observer|URLSession)")
        if holder:
            cause = "held by " + holder
        elif re.search(r"^  Task \(.*\) is still running", message, re.MULTILINE):
            cause = "still running"
        elif "retain cycle (certain)" in message:
            cause = "cycle"
        elif "possible retain cycle" in message:
            cause = "possible cycle"
        elif "no retain cycle through it" in message:
            cause = "no cycle"
        elif "no retain cycle found through it" in message:
            cause = "no cycle, " + (first(r"(\d+) only partly read") or "?") + " object chỉ đọc được một phần"
        elif "retain cycle search stopped" in message:
            cause = "search stopped at " + (first(r"stopped at the (\w+) limit") or "?")
        else:
            cause = None
        steps = re.findall(r"^    (\S.* → .*)$", message, re.MULTILINE)
        reports.append({
            "type": first(r"LEAK ([\w.]+)"),
            "root": first(r"after \w+ of ([\w.]+)"),
            "fix": first(r"(?m)^  fix: (.*)$"),
            "kind": first(r"kind: (\w+)"),
            "trigger": first(r"after (\w+) of"),
            "age": first(r"still alive ([\d.]+)s"),
            "suppressed": "suppressed until" in message,
            "cause": cause,
            "cycle": [s for s in steps if not s.startswith("UI") or "." in s.split(" ")[0]],
        })

all_classes = {o["className"] for spec in scenarios for o in spec["objects"]}

def describe(report):
    if report["suppressed"]:
        return f"`{report['type']}` chỉ log (suppressed)"
    if report["kind"] == "budget":
        return f"`{report['type']}` vượt budget"
    if report["type"] not in (report["root"], None) and report["kind"] == "outlived":
        return f"`{report['type']}` outlived sau {report['trigger']} của `{report['root']}`, {report['age']}s"
    return f"`{report['type']}` {report['kind']} sau {report['trigger']}, {report['age']}s"

EXPECTED = {
    "leak_cycle": "báo leak",
    "leak_rooted": "báo leak",
    "leak_budget": "báo vượt budget",
    "leak_suppressed": "chỉ log",
    "leak_task": "báo Task chạy tiếp",
    "leak_subscription": "báo subscription sống tiếp",
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
    if expectation == "leak_task":
        return not report["suppressed"] and report["kind"] == "outlived" and report["type"] == "Task"
    if expectation == "leak_subscription":
        return not report["suppressed"] and report["kind"] == "outlived" and report["type"] != report["root"]
    return False

CAUSE_EXPECTED = {"leak_cycle": ("cycle", "possible cycle"), "leak_rooted": ("no cycle", "held by"),
                  "leak_task": ("still running",), "leak_subscription": ("held by",)}

def cause_matches(cause, wanted):
    return any(cause == w or cause.startswith(w + " ") or cause.startswith(w + ",") for w in wanted)

def cause_cell(spec, mine):
    shown = [r for r in mine if r["cause"]]
    if not shown:
        return "—"
    cells = []
    for r in shown:
        text = r["cause"]
        if r["cycle"]:
            text += ": " + "; ".join(f"`{step}`" for step in r["cycle"])
        if r["fix"]:
            text += f"<br>fix: {r['fix']}"
        if r["type"] in searches:
            count, ms, slices, longest = searches[r["type"]]
            text += f" ({count} object, {ms:.1f} ms, {slices} lát, lát dài nhất {longest:.1f} ms)"
        wanted = spec.get("causes") or CAUSE_EXPECTED.get(spec["expectation"])
        marker = "" if wanted is None else (" ✅" if cause_matches(r["cause"], wanted) else " ⚠️")
        cells.append(text + marker)
    return "<br>".join(cells)

rows, failures, claimed = [], 0, set()
for spec in scenarios:
    classes = {o["className"] for o in spec["objects"]}
    leaking = {o["className"] for o in spec["objects"] if o["leaks"]}
    mine = [r for r in reports if r["type"] in classes or (r["root"] in classes and r["type"] not in all_classes)]
    claimed.update(id(r) for r in mine)
    good = [r for r in mine if wanted(spec["expectation"], r)]
    problems = []
    if spec["id"] not in opened:
        problems.append("không được mở")
    missing = leaking - {r["type"] for r in good} if spec["expectation"] not in ("no_leak", "allowed") else set()
    if missing:
        problems.append("không báo " + ", ".join(f"`{m}`" for m in sorted(missing)))
    if spec["expectation"] in ("leak_task", "leak_subscription") and not good:
        problems.append(f"không {EXPECTED[spec['expectation']]}")
    seen = sorted({w["pattern"] for w in warnings if w["root"] in classes})
    expected_warnings = sorted(spec.get("warnings", []))
    problems += [f"thiếu cảnh báo `{w}`" for w in expected_warnings if w not in seen]
    problems += [f"cảnh báo thừa `{w}`" for w in seen if w not in expected_warnings]
    problems += [f"báo thừa {describe(r)}" for r in mine if r not in good]
    for o in spec["objects"]:
        died = o["log"] in deinits
        if o["leaks"] and died:
            problems.append(f"`{o['log']}` deinit dù phải còn sống")
        if not o["leaks"] and not died:
            problems.append(f"`{o['log']}` không deinit")
    failures += bool(problems)
    actual = "<br>".join(describe(r) for r in mine) or "không báo"
    warning_cell = "<br>".join(f"`{w}`" for w in seen) or "—"
    rows.append(f"| {spec['id']} | {spec['name']} | `{spec['expectation']}`: {EXPECTED[spec['expectation']]} "
                f"| {actual} | {'✅' if not problems else '❌ ' + '; '.join(problems)} | {cause_cell(spec, mine)} | {warning_cell} |")

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
    "| Case | Scenario | Mong đợi | Thực tế | Kết quả | Nguyên nhân (graph ở T1) | Cảnh báo |",
    "|---|---|---|---|---|---|---|",
    *rows,
    "",
    "## Lệch đã chấp nhận",
    "",
    "- Leak `leak_cycle` và `leak_rooted` đều được báo với `kind: screen`. Đúng thiết kế: `kind` là điều quan sát được,",
    "  còn nguyên nhân nằm ở cột \"Nguyên nhân\" (ADR 003). Cột này không làm fail: ⚠️ là chỗ graph chưa thấy đúng nguyên nhân.",
    "- Cycle certain được báo ngay ở T1 (khoảng 2s), các leak còn lại ở T2 (khoảng 8s).",
    "- Graph chạy trên main thread từng lát: \"lát dài nhất\" là lâu nhất một frame phải chờ. Số object và thời gian",
    "  cộng cả hai lần tìm: cycle, rồi thứ đang giữ object (task, timer, observer…).",
    "- Z05: cycle giữa hai màn hình được báo thành hai report, mỗi màn một report.",
    "- Z08: VC giữ token của observer, nên nguyên nhân là cycle qua token; NotificationCenter cũng giữ token.",
    "- Z10: biến static không phải root mà tool biết, nên chỉ ghi \"không có cycle\".",
    "- Cảnh báo (cột cuối) được ghi lúc màn hình đóng, trước khi biết có leak hay không: Z26 không leak nhưng vẫn phải có.",
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
