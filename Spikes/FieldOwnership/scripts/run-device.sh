#!/usr/bin/env bash
# SPIKE — builds SpikeHost for a real device, runs it, saves SPIKE| lines to results/<label>.txt
#
#   scripts/run-device.sh <label> <device-udid> <team-id> [xcodebuild build settings...]
#   scripts/run-device.sh device-all 00008101-0006299E0AB9003A DLXR7ZA23L
set -euo pipefail
cd "$(dirname "$0")/.."
LABEL="$1"; UDID="$2"; TEAM="$3"; shift 3
DD="${TMPDIR:-/tmp}/field-ownership-spike-$LABEL"
LOG="$(mktemp -t spike).log"

xcodebuild build -project HostApp/SpikeHost.xcodeproj -scheme SpikeHost -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DD" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" "$@" \
  > "$LOG" 2>&1 || { grep -E "error" "$LOG" | head -20; echo "build failed, full log: $LOG"; exit 1; }

APP="$DD/Build/Products/Debug-iphoneos/SpikeHost.app"
xcrun devicectl device install app --device "$UDID" "$APP" > /dev/null
xcrun devicectl device process launch --device "$UDID" --console --terminate-existing \
  vn.kalapa.TLeakDetector.SpikeHost 2>&1 \
  | tr -d '\r' | sed 's/Launched application with [^ ]* bundle identifier\.//' > "$LOG.run" || true

{
  echo "# label: $LABEL"
  echo "# destination: device $UDID"
  echo "# settings: ${*:-<default: all reflection metadata>}"
  echo "# xcode: $(xcodebuild -version | head -1)"
  grep -E '^SPIKE\|' "$LOG.run" | grep -v '^SPIKE|DONE'
} > "results/$LABEL.txt"
grep -q '^SPIKE|DONE' "$LOG.run" || { echo "app did not finish, see $LOG.run"; tail -20 "$LOG.run"; exit 1; }
grep -E '^SPIKE\|(ENV|SUMMARY)' "results/$LABEL.txt"
