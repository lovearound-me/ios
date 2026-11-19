#!/bin/bash
# While the watch UI tests run in CI, takes a 2-second sample of the watch
# app's threads every 20 seconds. When a test hangs (the app stays busy and
# XCUITest times out), the samples show what the app was busy with.
#   scripts/ci-sample-watch.sh build/samples &
out=${1:-build/samples}
mkdir -p "$out"
i=0
while true; do
    for pid in $(pgrep -f '/LoveAround\.app/LoveAround$'); do
        i=$((i + 1))
        stamp=$(date +%H%M%S)
        ps -o pid=,%cpu=,etime=,command= -p "$pid" > "$out/$stamp-$i-ps.txt" 2>&1
        sample "$pid" 2 -mayDie -file "$out/$stamp-$i-sample.txt" >/dev/null 2>&1
    done
    sleep 20
done
