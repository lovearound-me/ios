#!/usr/bin/env python3
"""Prints the udid of a simulator on the newest installed runtime.

  scripts/simulator.py watchOS   any Apple Watch
  scripts/simulator.py iOS       an iPhone, a plain "Pro" one if there is one
"""
import json
import subprocess
import sys


def simctl(*args):
    out = subprocess.run(["xcrun", "simctl", "list", *args, "-j"],
                         check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def version(runtime):
    return tuple(int(p) for p in runtime["version"].split(".") if p.isdigit())


platform = sys.argv[1]
runtimes = sorted((r for r in simctl("runtimes")["runtimes"]
                   if r.get("platform") == platform and r.get("isAvailable", True)),
                  key=version, reverse=True)
devices = simctl("devices", "available")["devices"]
# A version can come as several runtimes (one held only an "iPhone Duo"),
# so pick among all devices of the newest version that has any.
for v in sorted({version(r) for r in runtimes}, reverse=True):
    found = [(d, r) for r in runtimes if version(r) == v
             for d in devices.get(r["identifier"], [])]
    if platform == "iOS":
        found = [(d, r) for d, r in found if d["name"].startswith("iPhone")]
        found.sort(key=lambda dr: not ("Pro" in dr[0]["name"] and "Max" not in dr[0]["name"]))
    if found:
        d, r = found[0]
        print(f"{d['name']} on {platform} {r['version']}", file=sys.stderr)
        print(d["udid"])
        sys.exit()
sys.exit(f"no {platform} simulator")
