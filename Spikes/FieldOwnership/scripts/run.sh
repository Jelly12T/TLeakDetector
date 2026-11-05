#!/usr/bin/env bash
# SPIKE — runs the report test on an iOS destination and saves SPIKE| lines to results/<label>.txt
#
#   scripts/run.sh <label> <destination> [xcodebuild build settings...]
#
#   scripts/run.sh sim-all       'platform=iOS Simulator,name=iPhone 17'
#   scripts/run.sh sim-nonames   'platform=iOS Simulator,name=iPhone 17' SWIFT_REFLECTION_METADATA_LEVEL=without-names
#   scripts/run.sh sim-debugger  'platform=iOS Simulator,name=iPhone 17' OTHER_SWIFT_FLAGS='-Xfrontend -reflection-metadata-for-debugger-only'
#   scripts/run.sh sim-none      'platform=iOS Simulator,name=iPhone 17' SWIFT_REFLECTION_METADATA_LEVEL=none
#   scripts/run.sh device-all    'platform=iOS,id=<udid>' -allowProvisioningUpdates DEVELOPMENT_TEAM=<team>
set -euo pipefail
cd "$(dirname "$0")/.."
LABEL="$1"; DEST="$2"; shift 2
LOG="$(mktemp -t spike).log"
DD="${TMPDIR:-/tmp}/field-ownership-spike-$LABEL"

xcodebuild test -scheme FieldOwnershipSpike-Package -destination "$DEST" -derivedDataPath "$DD" \
  -only-testing:FieldOwnershipSpikeTests/FieldOwnershipSpikeTests/testReport "$@" > "$LOG" 2>&1 || {
  tail -30 "$LOG"; echo "xcodebuild failed, full log: $LOG"; exit 1; }

{
  echo "# label: $LABEL"
  echo "# destination: $DEST"
  echo "# settings: ${*:-<default: all reflection metadata>}"
  echo "# xcode: $(xcodebuild -version | head -1)"
  grep -E '^SPIKE\|' "$LOG"
} > "results/$LABEL.txt"
grep -E '^SPIKE\|(ENV|SUMMARY)' "results/$LABEL.txt"
