#!/usr/bin/env python3
"""Start/stop only the dedicated routing container with a pinned image and graph."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "apps/c67-local-server-lab/fixtures/routing/valhalla-runtime.json"


def command(config, *args):
    return ["docker", "--context", config["dockerContext"], *args]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["start", "stop", "status"])
    parser.add_argument("--graph", type=Path)
    args = parser.parse_args()
    config = json.loads(CONFIG.read_text())
    if args.action == "status":
        subprocess.run(command(config, "ps", "-a", "--filter", "name=^/" + config["container"] + "$"), check=True)
        return
    if args.action == "stop":
        subprocess.run(command(config, "stop", config["container"]), check=True)
        return
    if not args.graph or not (args.graph / "jakarta.osm.pbf").is_file():
        parser.error("--graph must contain the extracted jakarta.osm.pbf")
    # Never replace an existing container/volume or switch the user's Docker context.
    existing = subprocess.check_output(command(config, "ps", "-a", "--filter", "name=^/" + config["container"] + "$", "--format", "{{.Names}}"), text=True).strip()
    if existing:
        info = json.loads(subprocess.check_output(command(config, "inspect", config["container"]), text=True))[0]
        mounts = [m.get("Source") for m in info.get("Mounts", []) if m.get("Destination") == "/custom_files"]
        if info["Config"]["Image"] != config["image"] or mounts != [str(args.graph.resolve())]:
            parser.error("Existing container image/graph differs; inspect it instead of replacing it")
        if not info["State"]["Running"]:
            subprocess.run(command(config, "start", config["container"]), check=True)
        else:
            print("Dedicated container already running with the same image/graph")
        return
    subprocess.run(command(config, "run", "-d", "--name", config["container"], "--cpus", str(config["cpus"]), "--memory", f"{config['memoryGiB']}g",
                           "-p", config["listen"] + ":8002", "-v", str(args.graph.resolve()) + ":/custom_files",
                           "-e", "server_threads=4", "-e", "build_admins=False", "-e", "build_time_zones=False", "-e", "build_elevation=False",
                           config["image"]), check=True)


if __name__ == "__main__":
    main()
