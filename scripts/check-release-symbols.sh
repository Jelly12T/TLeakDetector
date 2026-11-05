#!/usr/bin/env bash
#
# Archives the app and fails if any symbol, type name or string of TLeakDetector
# is in the shipped binaries. Reused by CI (S8).
#
# Usage:
#   scripts/check-release-symbols.sh [options]
#
# Options:
#   --project PATH         .xcodeproj to archive   (default: Examples/HostApp/HostApp.xcodeproj)
#   --workspace PATH       .xcworkspace to archive (instead of --project)
#   --scheme NAME          scheme                  (default: HostApp)
#   --configuration NAME   build configuration     (default: Release)
#   --archive PATH         check an existing .xcarchive, do not build
#   --expect-present       invert: FAIL if the symbols are NOT found
#                          (sanity check on a Debug build that the scan works)
#
# Exit codes: 0 = clean, 1 = tool symbols found (or missing with --expect-present),
#             2 = usage/build error.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Examples/HostApp/HostApp.xcodeproj"
WORKSPACE=""
SCHEME="HostApp"
CONFIGURATION="Release"
ARCHIVE=""
EXPECT_PRESENT=0

die() { echo "error: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)        PROJECT="$2"; shift 2 ;;
    --workspace)      WORKSPACE="$2"; PROJECT=""; shift 2 ;;
    --scheme)         SCHEME="$2"; shift 2 ;;
    --configuration)  CONFIGURATION="$2"; shift 2 ;;
    --archive)        ARCHIVE="$2"; shift 2 ;;
    --expect-present) EXPECT_PRESENT=1; shift ;;
    -h|--help)        sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                die "unknown option: $1" ;;
  esac
done

# ---------------------------------------------------------------------------
# 1. Archive
# ---------------------------------------------------------------------------
if [[ -z "$ARCHIVE" ]]; then
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/leak-symbols.XXXXXX")"
  trap 'rm -rf "$WORK"' EXIT
  ARCHIVE="$WORK/App.xcarchive"
  if [[ -n "$WORKSPACE" ]]; then SRC=(-workspace "$WORKSPACE"); else SRC=(-project "$PROJECT"); fi

  echo "==> Archiving scheme '$SCHEME' ($CONFIGURATION)"
  if ! xcodebuild archive "${SRC[@]}" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination 'generic/platform=iOS' \
        -archivePath "$ARCHIVE" \
        -derivedDataPath "$WORK/DerivedData" \
        CODE_SIGNING_ALLOWED=NO \
        > "$WORK/xcodebuild.log" 2>&1; then
    tail -40 "$WORK/xcodebuild.log" >&2
    die "archive failed (full log above)"
  fi
fi

[[ -d "$ARCHIVE" ]] || die "archive not found: $ARCHIVE"
APPS=("$ARCHIVE"/Products/Applications/*.app)
[[ -d "${APPS[0]}" ]] || die "no .app in $ARCHIVE/Products/Applications"

# ---------------------------------------------------------------------------
# 2. What to look for
# ---------------------------------------------------------------------------
# Module and product names, the compile flag, plus every type declared in Sources/.
# Swift mangled names embed the module name (e.g. $s8LeakCore...), so module
# names catch any Swift symbol; type names catch ObjC runtime names and strings.
PATTERNS=("TLeakDetector" "LEAK_DETECTOR")
for dir in "$ROOT"/Sources/*/; do PATTERNS+=("$(basename "$dir")"); done
while IFS= read -r t; do PATTERNS+=("$t"); done < <(
  grep -rhoE '\b(class|struct|enum|protocol|actor)[[:space:]]+[A-Z][A-Za-z0-9_]{3,}' "$ROOT/Sources" \
    | awk '{print $2}' | sort -u
)
PATTERNS=($(printf '%s\n' "${PATTERNS[@]}" | sort -u))
REGEX="$(IFS='|'; echo "${PATTERNS[*]}")"
echo "==> Patterns: ${PATTERNS[*]}"

# ---------------------------------------------------------------------------
# 3. Scan every Mach-O inside the .app (main binary, frameworks, extensions)
# ---------------------------------------------------------------------------
HITS=""
SCANNED=0
while IFS= read -r -d '' f; do
  file -b "$f" | grep -q 'Mach-O' || continue
  SCANNED=$((SCANNED + 1))
  rel="${f#"$ARCHIVE"/}"
  sym_hits="$(nm -a "$f" 2>/dev/null | grep -E "$REGEX" | head -20 || true)"
  str_hits="$(strings -a "$f" 2>/dev/null | grep -E "$REGEX" | head -20 || true)"
  [[ -n "$sym_hits" ]] && HITS+=$'\n'"[nm]      $rel"$'\n'"$sym_hits"
  [[ -n "$str_hits" ]] && HITS+=$'\n'"[strings] $rel"$'\n'"$str_hits"
done < <(find "${APPS[@]}" -type f -print0)

[[ $SCANNED -gt 0 ]] || die "no Mach-O binary found in ${APPS[*]}"
echo "==> Scanned $SCANNED Mach-O file(s)"

if [[ $EXPECT_PRESENT -eq 1 ]]; then
  if [[ -n "$HITS" ]]; then
    echo "OK: tool symbols are present in '$CONFIGURATION', as expected."; exit 0
  fi
  echo "FAIL: expected tool symbols in '$CONFIGURATION' but found none." >&2; exit 1
fi

if [[ -n "$HITS" ]]; then
  echo "FAIL: TLeakDetector found in '$CONFIGURATION' build:" >&2
  echo "$HITS" >&2
  exit 1
fi
echo "OK: no TLeakDetector symbol or string in '$CONFIGURATION' build."
