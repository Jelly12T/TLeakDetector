#!/usr/bin/env bash
#
# Runs every AppDemo scenario on an iOS Simulator (--autorun, TLEAK_MODE=log) and grades what
# TLeakDetector reported, plus which objects deinit, against AppDemo/expected.json.
# Writes the result table to AppDemo/RESULTS.md, keeping the hand-written part after "<!-- analysis -->".
#
# Usage:
#   AppDemo/scripts/demo-autorun.sh [--udid UDID] [--output PATH] [--keep-logs DIR]
#
# Exit codes: 0 = every scenario matches, 1 = mismatch, 2 = setup error.

set -euo pipefail

LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$LAB/.." && pwd)"
OUTPUT="$LAB/RESULTS.md"
UDID=""
KEEP=""
BUNDLE_ID="vn.kalapa.TLeakDetector.AppDemo"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --udid)      UDID="$2"; shift 2 ;;
    --output)    OUTPUT="$2"; shift 2 ;;
    --keep-logs) KEEP="$2"; shift 2 ;;
    -h|--help)   sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           echo "error: unknown option: $1" >&2; exit 2 ;;
  esac
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/demo-autorun.XXXXXX")"
LAUNCHER=""
cleanup() {
  [[ -n "$LAUNCHER" ]] && kill "$LAUNCHER" 2>/dev/null || true
  [[ -n "$UDID" ]] && xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  if [[ -n "$KEEP" ]]; then mkdir -p "$KEEP" && cp "$WORK"/*.log "$WORK"/*.json "$KEEP"/ 2>/dev/null || true; fi
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

echo "==> Building AppDemo (Debug) for $UDID"
xcodebuild build -project "$LAB/AppDemo.xcodeproj" -scheme AppDemo -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$WORK/DerivedData" > "$WORK/build.log" 2>&1 \
  || { tail -30 "$WORK/build.log" >&2; die "build failed"; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl install "$UDID" "$WORK/DerivedData/Build/Products/Debug-iphonesimulator/AppDemo.app"

echo "==> Running every scenario"
START="$(date '+%Y-%m-%d %H:%M:%S')"
SIMCTL_CHILD_TLEAK_MODE=log SIMCTL_CHILD_TLEAK_VERBOSE=1 xcrun simctl launch --console-pty --terminate-running-process \
  "$UDID" "$BUNDLE_ID" --autorun > "$WORK/app.log" 2>&1 &
LAUNCHER=$!
for _ in $(seq 1 400); do
  grep -q "autorun done" "$WORK/app.log" 2>/dev/null && break
  sleep 1
done
grep -q "autorun done" "$WORK/app.log" || die "autorun did not finish within 400 s"
# "autorun done" comes a few seconds after the last close: wait past that close's T2 (8 s).
sleep 8
PID="$(pgrep -n -f "AppDemo.app/AppDemo" || true)"
[[ -n "$PID" ]] || die "AppDemo is no longer running"

xcrun simctl spawn "$UDID" log show --start "$START" --style json --info --debug \
  --predicate "subsystem == \"TLeakDetector\" AND processID == $PID" > "$WORK/reports.json" 2>/dev/null

COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
git -C "$ROOT" diff --quiet HEAD -- Sources 2>/dev/null || COMMIT+="+uncommitted Sources"
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

python3 -I - "$LAB/expected.json" "$WORK/app.log" "$WORK/reports.json" "$OUTPUT" \
  "$COMMIT" "$XCODE" "$SIMULATOR" <<'PY'
import datetime, json, os, re, sys

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

reports, config_errors, warnings = [], [], []
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
    elif entry.get("category") == "leak":
        holder = first(r"(?m)^  held by (?:a running |a scheduled |a |an )?(Task|Timer|CADisplayLink|NotificationCenter observer|URLSession)")
        if holder:
            cause = "held by " + holder
        elif re.search(r"^  Task \(.*\) is still running", message, re.MULTILINE):
            cause = "still running"
        elif re.search(r"^  retain cycle:", message, re.MULTILINE):
            cause = "cycle"
        elif "possible retain cycle" in message:
            cause = "possible cycle"
        elif "no retain cycle through it" in message:
            cause = "no cycle"
        elif "no retain cycle found through it" in message:
            cause = "no cycle found, " + (first(r"(\d+) objects were only partly read") or "?") + " partly read"
        elif "retain cycle search stopped" in message:
            cause = "search stopped at " + (first(r"stopped at the (\w+) limit") or "?")
        else:
            cause = None
        reports.append({
            "type": first(r"LEAK ([\w.]+)"),
            "root": first(r"after \w+ of ([\w.]+)") or first(r"LEAK ([\w.]+)"),
            "kind": first(r"LEAK [\w.]+ \((\w+)\)"),
            "trigger": first(r"still alive [\d.]+s after (\w+)"),
            "age": first(r"still alive ([\d.]+)s"),
            "suppressed": "suppressed until" in message,
            "cause": cause,
            "raw": message,
        })

all_classes = {o["className"] for spec in scenarios for o in spec["objects"]}

def describe(r):
    if r["kind"] == "budget":
        text = f"`{r['type']}` budget"
    elif r["kind"] == "outlived" and r["type"] != r["root"]:
        text = f"`{r['type']}` outlived after {r['trigger']} of `{r['root']}`, {r['age']}s"
    else:
        text = f"`{r['type']}` {r['kind']} after {r['trigger']}, {r['age']}s"
    return text + (" (suppressed)" if r["suppressed"] else "")

EXPECTED = {
    "leak_cycle": "report", "leak_rooted": "report", "leak_budget": "budget report",
    "leak_suppressed": "log only (suppressed)", "leak_task": "Task outlived", "leak_subscription": "subscription outlived",
    "no_leak": "no report", "allowed": "no report",
}

def cause_matches(cause, wanted):
    if cause is None:
        return False
    for w in wanted:
        if cause == w or cause.startswith(w + " ") or cause.startswith(w + ","):
            return True
        if w == "cycle" and cause == "possible cycle":
            return True
    return False

rows, details, passed, cause_ok, cause_bad = [], [], 0, 0, 0
claimed = set()
by_group = {}
for spec in scenarios:
    exp = spec["expectation"]
    classes = {o["className"] for o in spec["objects"]}
    mine = [r for r in reports if r["type"] in classes or (r["root"] in classes and r["type"] not in all_classes)]
    claimed.update(id(r) for r in mine)
    problems, good = [], []
    if spec["id"] not in opened:
        problems.append("not opened")

    if exp in ("leak_cycle", "leak_rooted", "leak_suppressed", "leak_budget"):
        wanted = sorted({(o["className"], o["kind"]) for o in spec["objects"] if o.get("kind")})
        for cls, kind in wanted:
            hits = [r for r in mine if r["type"] == cls and r["kind"] == kind
                    and r["suppressed"] == (exp == "leak_suppressed")]
            if hits:
                good += hits
                continue
            other = [r for r in mine if r["type"] == cls]
            if other:
                problems.append(f"`{cls}` reported as {', '.join(describe(r) for r in other)}, expected {kind}"
                                + (" (suppressed)" if exp == "leak_suppressed" else ""))
            else:
                problems.append(f"no `{kind}` report for `{cls}`")
    elif exp == "leak_task":
        good = [r for r in mine if r["type"] == "Task" and r["kind"] == "outlived" and not r["suppressed"]]
        if not good:
            problems.append("no `Task` outlived report")
    elif exp == "leak_subscription":
        good = [r for r in mine if r["kind"] == "outlived" and r["type"] not in classes and r["type"] != "Task"
                and not r["suppressed"]]
        if not good:
            problems.append("no outlived subscription report")

    claimed_good = {id(r) for r in good}
    problems += [f"extra report: {describe(r)}" for r in mine if id(r) not in claimed_good]

    seen = sorted({w["pattern"] for w in warnings if w["root"] in classes})
    expected_warnings = sorted(spec.get("warnings", []))
    problems += [f"missing warning `{w}`" for w in expected_warnings if w not in seen]
    problems += [f"extra warning `{w}`" for w in seen if w not in expected_warnings]

    for o in spec["objects"]:
        died = o["log"] in deinits
        if o["leaks"] and died:
            problems.append(f"`{o['log']}` deinit although it should stay alive")
        if not o["leaks"] and not died:
            problems.append(f"`{o['log']}` never deinit")

    wanted_cause = spec.get("cause")
    cause_cell = "—"
    shown = good or mine
    if wanted_cause and exp.startswith("leak") and exp != "leak_budget":
        if not shown:
            cause_cell = "— (no report)"
        else:
            matched = any(cause_matches(r["cause"], wanted_cause) for r in shown)
            cause_ok += matched
            cause_bad += not matched
            cause_cell = "<br>".join(f"{r['cause'] or '?'}" for r in shown) + (" ✅" if matched else " ⚠️")
            if not matched:
                cause_cell += f"<br>expected: {' / '.join(wanted_cause)}"

    ok = not problems
    passed += ok
    group = by_group.setdefault(spec["family"], [0, 0])
    group[0] += ok; group[1] += 1
    actual = "<br>".join(describe(r) for r in mine) or "no report"
    warning_cell = "<br>".join(f"`{w}`" for w in seen) or "—"
    rows.append(f"| {spec['id']} | {spec['name']} | {spec['language']} | `{exp}`: {EXPECTED[exp]} | {actual} "
                f"| {'✅' if ok else '❌ ' + '; '.join(problems)} | {cause_cell} | {warning_cell} |")
    if not ok or "⚠️" in cause_cell:
        lines = [f"<details><summary>{spec['id']} {spec['name']}</summary>", ""]
        lines.append(f"Expected: `{exp}`; retain path: {spec.get('retainPath', '—')}")
        lines.append("")
        if mine:
            lines.append("```")
            for r in mine:
                lines += r["raw"].splitlines()[:14]
            lines.append("```")
        else:
            lines.append("No report from TLeakDetector.")
        lines += ["", "</details>", ""]
        details += lines

stray = [r for r in reports if id(r) not in claimed]
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
lines = [
    "# AppDemo results",
    "",
    f"Generated by `AppDemo/scripts/demo-autorun.sh` on {now}: commit `{commit}`, {xcode}, {simulator}.",
    "Every scenario is opened and closed (`--autorun`, `TLEAK_MODE=log`); TLeakDetector's reports and AppDemo's",
    "`deinit` log are compared with [expected.json](expected.json), which states what a *correct* detector says.",
    "",
    f"**Outcome: {passed}/{len(scenarios)} scenarios match.** Cause: {cause_ok} match, {cause_bad} differ "
    "(the cause column never fails a scenario).",
    "",
    "| Family | Match |",
    "|---|---|",
    *[f"| {family} | {g[0]}/{g[1]} |" for family, g in by_group.items()],
    "",
    "| Case | Scenario | Lang | Expected | Actual | Outcome | Cause (graph at T1) | Warnings |",
    "|---|---|---|---|---|---|---|---|",
    *rows,
]
if stray:
    lines += ["", "## Reports that belong to no scenario", ""] + [f"- {describe(r)}" for r in stray]
if config_errors:
    lines += ["", "## Configuration errors", ""] + [f"- {e}" for e in config_errors]
if details:
    lines += ["", "## Report excerpts (mismatches and cause differences)", ""] + details

MARKER = "<!-- analysis -->"
kept = ""
if os.path.exists(output):
    previous = open(output, encoding="utf-8").read()
    if MARKER in previous:
        kept = previous[previous.index(MARKER):]
open(output, "w", encoding="utf-8").write("\n".join(lines) + "\n" + ("\n" + kept if kept else ""))

print("\n".join(rows))
print(f"==> {passed}/{len(scenarios)} match, {len(stray)} stray, {len(config_errors)} config errors; wrote {output}")
sys.exit(0 if passed == len(scenarios) and not stray and not config_errors else 1)
PY
