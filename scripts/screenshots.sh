#!/bin/bash
# Every screen of the watch or the iPhone app, from a simulator, in Russian
# and English. The app draws each one from made-up data when launched with
# `--demo <name>` (Watch/Demo.swift, Phone/Demo.swift), so nothing here signs
# in or reaches the server. Which app it is comes from where it was built.
#
#   scripts/screenshots.sh build/Build/Products/Debug-watchsimulator/LoveAround.app shots/watch
#   scripts/screenshots.sh build/Build/Products/Debug-iphonesimulator/LoveAround.app shots/phone
set -euo pipefail

app=$1
out=${2:-shots}
case "$app" in
    *iphonesimulator*)
        bundle=me.lovearound.ios
        os=iOS
        screens="signin how notifyIntro home sent anyone empty start signal paused offHere book contact add choose toys board pair device deviceWho deviceDoes deviceBoard settings settingsAccount settingsWho notifyLook"
        ;;
    *)
        bundle=me.lovearound.ios.watchkitapp
        os=watchOS
        screens="signin exists code expired computer connected hive circles named list peek sent anyone empty signal notification settings layout glow delete"
        ;;
esac

# The newest runtime, and the device to show: the biggest plain Apple Watch,
# or the iPhone Pro (not Max, Plus or SE): the size most people hold.
read -r runtime device < <(xcrun simctl list runtimes -j | OS=$os python3 -c '
import json, os, re, sys
want = os.environ["OS"]
# com.apple.CoreSimulator.SimRuntime.iOS-18-2, ….watchOS-11-2
runtimes = [r for r in json.load(sys.stdin)["runtimes"]
            if r["identifier"].split(".")[-1].startswith(want + "-") and r.get("isAvailable")]
if not runtimes:
    sys.exit("no " + want + " simulator runtime")
r = runtimes[-1]
kinds = r.get("supportedDeviceTypes", [])
# Not listed newest last: the newest is the one with the biggest number
# («iPhone 17 Pro», «Apple Watch Series 11 (46mm)»).
def newest(kinds):
    return max(kinds, key=lambda d: int((re.findall(r"\d+", d["name"]) or ["0"])[0]))
if want == "watchOS":
    kinds = [d for d in kinds if "Apple Watch" in d["name"]]
    best = newest([d for d in kinds if "Series" in d["name"] and ("46mm" in d["name"] or "45mm" in d["name"])] or kinds)
else:
    kinds = [d for d in kinds if d["name"].startswith("iPhone")]
    best = newest([d for d in kinds if d["name"].endswith(" Pro")] or kinds)
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
        # The signal shows for 5.5 s with emoji rising, a sent heart's glow
        # starts 1.6 s in (Phone/Demo.swift): catch both mid-way.
        if [ "$screen" = signal ]; then sleep 2; else sleep 3; fi
        xcrun simctl io "$udid" screenshot "$out/$lang/$screen.png" >/dev/null
        echo "$lang/$screen.png"
    done
done
