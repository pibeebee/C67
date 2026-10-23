"""Print an available iPhone Simulator destination for xcodebuild."""
import json
import subprocess
state = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
for runtime, devices in state["devices"].items():
    if ".iOS-" not in runtime:
        continue
    for device in devices:
        if device["name"].startswith("iPhone") and device.get("isAvailable"):
            print("platform=iOS Simulator,id=" + device["udid"])
            raise SystemExit(0)
raise SystemExit("No available iPhone Simulator runtime; install one in Xcode Settings.")
