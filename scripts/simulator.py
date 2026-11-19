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
for runtime in runtimes:
    found = devices.get(runtime["identifier"], [])
    if platform == "iOS":
        found = [d for d in found if d["name"].startswith("iPhone")]
        found.sort(key=lambda d: not ("Pro" in d["name"] and "Max" not in d["name"]))
    if found:
        print(f"{found[0]['name']} on {platform} {runtime['version']}", file=sys.stderr)
        print(found[0]["udid"])
        sys.exit()
sys.exit(f"no {platform} simulator")
