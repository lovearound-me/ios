#!/bin/bash
# Every screen of the watch app, from a watchOS simulator, in Russian and English.
# The app draws each one from made-up data when launched with `--demo <name>`
# (Watch/Demo.swift), so nothing here signs in or reaches the server.
#
#   scripts/screenshots.sh build/Build/Products/Debug-watchsimulator/LoveAround.app shots
set -euo pipefail

app=$1
out=${2:-shots}
bundle=me.lovearound.ios.watchkitapp
screens="signin exists code expired computer connected circles sent anyone empty signal settings colors delete"

# The newest watchOS runtime, and the biggest Apple Watch it runs.
read -r runtime device < <(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"]
            if "watchOS" in r["identifier"] and r.get("isAvailable")]
if not runtimes:
    sys.exit("no watchOS simulator runtime")
r = runtimes[-1]
kinds = [d for d in r.get("supportedDeviceTypes", []) if "Apple Watch" in d["name"]]
best = ([d for d in kinds if "Ultra" not in d["name"] and ("46mm" in d["name"] or "45mm" in d["name"])] or kinds)[-1]
print(r["identifier"], best["identifier"])
')

udid=$(xcrun simctl create "Love Around shots" "$device" "$runtime")
trap 'xcrun simctl shutdown "$udid" >/dev/null 2>&1; xcrun simctl delete "$udid" >/dev/null 2>&1 || true' EXIT
echo "simulator: $device on $runtime"

xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl status_bar "$udid" override --time 9:41 >/dev/null 2>&1 || true
xcrun simctl install "$udid" "$app"

for lang in ru en; do
    mkdir -p "$out/$lang"
    for screen in $screens; do
        xcrun simctl launch --terminate-running-process "$udid" "$bundle" \
            --demo "$screen" -AppleLanguages "($lang)" -AppleLocale "$lang" >/dev/null
        # The signal shows for 5.5 s with emoji rising: catch it mid-way.
        if [ "$screen" = signal ]; then sleep 2; else sleep 3; fi
        xcrun simctl io "$udid" screenshot "$out/$lang/$screen.png" >/dev/null
        echo "$lang/$screen.png"
    done
done
