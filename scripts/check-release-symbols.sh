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
# a) Module and product names and the compile flag, matched as SUBSTRINGS.
#    Swift mangled names embed the module name ($s8LeakCore12LeakRegistryC...), so these
#    catch every Swift symbol, nested types included. They have no word boundary
#    (a digit precedes them), hence substring matching.
MODULES=("TLeakDetector" "LEAK_DETECTOR")
for dir in "$ROOT"/Sources/*/; do MODULES+=("$(basename "$dir")"); done
# b) Top-level type names declared in Sources/, matched as WHOLE WORDS, to catch plain
#    strings (e.g. an ObjC-visible class name). Nested types are skipped: they are covered
#    by (a), and their names are often generic words ("Item", "Found" would hit "Foundation").
TYPES=()
while IFS= read -r t; do TYPES+=("$t"); done < <(
  grep -rhE '^(@[A-Za-z]+ +)*((public|package|internal|private|fileprivate|open|final) +)*(class|struct|enum|protocol|actor) +[A-Z][A-Za-z0-9_]{3,}' "$ROOT/Sources" \
    | sed -E 's/.*(class|struct|enum|protocol|actor) +([A-Za-z0-9_]+).*/\2/' | sort -u
)
MODULE_REGEX="$(IFS='|'; echo "${MODULES[*]}")"
TYPE_REGEX="$(IFS='|'; echo "${TYPES[*]:-__no_types__}")"
echo "==> Substring patterns: ${MODULES[*]}"
echo "==> Whole-word types:   ${TYPES[*]:-<none>}"


# ---------------------------------------------------------------------------
# 3. Scan every Mach-O inside the .app (main binary, frameworks, extensions)
# ---------------------------------------------------------------------------
HITS=""
SCANNED=0
while IFS= read -r -d '' f; do
  file -b "$f" | grep -q 'Mach-O' || continue
  SCANNED=$((SCANNED + 1))
  rel="${f#"$ARCHIVE"/}"
  syms="$(nm -a "$f" 2>/dev/null || true)"
  strs="$(strings -a "$f" 2>/dev/null || true)"
  sym_hits="$( { grep -E "$MODULE_REGEX" <<<"$syms"; grep -wE "$TYPE_REGEX" <<<"$syms"; } | sort -u | head -20 || true)"
  str_hits="$( { grep -E "$MODULE_REGEX" <<<"$strs"; grep -wE "$TYPE_REGEX" <<<"$strs"; } | sort -u | head -20 || true)"
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
