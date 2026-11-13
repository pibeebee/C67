#!/usr/bin/env python3
"""Extract a bounded Jakarta graph and cafe sample from a local Geofabrik PBF.

Requires osmium==4.2.0 in an isolated Python environment. OSM inputs and generated
graphs stay in ignored verification storage. POI centers are never entrance proof.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

AREAS = [
    ("Blok M", -6.2445, 106.800), ("Cikini", -6.190, 106.840),
    ("Tebet", -6.233, 106.853), ("Senayan-SCBD", -6.224, 106.807),
    ("Kemang", -6.261, 106.814), ("Kebon Jeruk", -6.194, 106.773),
    ("Ragunan", -6.295, 106.824), ("Kuningan", -6.229, 106.831),
]
BOUNDS = (-6.45, 106.62, -6.08, 107.0)


def select_venues(cafes):
    venues, used = [], set()
    for area, lat, lon in AREAS:
        candidates = sorted(cafes, key=lambda p: ((p["latitude"] - lat) ** 2 + (p["longitude"] - lon) ** 2, p["id"]))
        for cafe in candidates:
            if cafe["id"] in used or (cafe["latitude"] - lat) ** 2 + (cafe["longitude"] - lon) ** 2 > .02 ** 2:
                continue
            used.add(cafe["id"])
            venues.append({"id": cafe["id"], "name": cafe["name"], "area": area,
                           "displayPoint": {"latitude": cafe["latitude"], "longitude": cafe["longitude"]},
                           "accesses": [], "sourceURL": cafe["sourceURL"]})
            if sum(v["area"] == area for v in venues) == 2:
                break
    return venues


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(data)
    return h.hexdigest()


def main():
    import osmium
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    destination = args.output / "jakarta.osm.pbf"
    if destination.exists():
        parser.error("Use a fresh output graph directory")
    writer = osmium.SimpleWriter(str(destination))

    class Extract(osmium.SimpleHandler):
        def __init__(self):
            super().__init__()
            self.nodes, self.ways, self.cafes = {}, set(), []

        def cafe(self, tags, ident, kind, lat, lon):
            if tags.get("amenity") == "cafe" and tags.get("name"):
                self.cafes.append({"id": f"osm-{kind}-{ident}", "name": tags["name"], "latitude": lat, "longitude": lon,
                                   "sourceURL": f"https://www.openstreetmap.org/{kind}/{ident}"})

        def node(self, node):
            lat, lon = node.location.lat, node.location.lon
            if BOUNDS[0] <= lat <= BOUNDS[2] and BOUNDS[1] <= lon <= BOUNDS[3]:
                self.nodes[node.id] = (lat, lon)
                writer.add_node(node)
                self.cafe(node.tags, node.id, "node", lat, lon)

        def way(self, way):
            refs = [n.ref for n in way.nodes]
            if refs and all(n in self.nodes for n in refs):
                self.ways.add(way.id)
                writer.add_way(way)
                if way.tags.get("amenity") == "cafe":
                    coordinates = [self.nodes[n] for n in refs]
                    self.cafe(way.tags, way.id, "way", sum(p[0] for p in coordinates) / len(coordinates), sum(p[1] for p in coordinates) / len(coordinates))

        def relation(self, relation):
            if relation.tags.get("type") == "restriction" and all(
                (m.type == "n" and m.ref in self.nodes) or (m.type == "w" and m.ref in self.ways)
                for m in relation.members
            ):
                writer.add_relation(relation)

    handler = Extract()
    try:
        handler.apply_file(str(args.source))
    finally:
        writer.close()
    venues = select_venues(handler.cafes)
    manifest = {"schemaVersion": 1, "evidenceMode": "OSM_SOURCE_ONLY_ENTRANCES_UNVERIFIED", "sourceURL": "https://download.geofabrik.de/asia/indonesia/java.html",
                "sourceFile": args.source.name, "downloadedAt": datetime.fromtimestamp(args.source.stat().st_mtime, timezone.utc).isoformat(), "preparedAt": datetime.now(timezone.utc).isoformat(),
                "licenseURL": "https://opendatacommons.org/licenses/odbl/1-0/", "attribution": "OpenStreetMap contributors",
                "sourceSHA256": digest(args.source), "graphInputSHA256": digest(destination), "bounds": BOUNDS,
                "extractionPolicy": "Keep nodes inside bounds, ways with all references retained, complete turn restrictions. Boundary-crossing ways omitted; do not benchmark at the cut boundary.",
                "note": "Nearest distinct named cafes, two per area. POI centers are not public entrance or parking evidence; no Apple/Google pins inferred.", "venues": venues}
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"nodes": len(handler.nodes), "ways": len(handler.ways), "cafes": len(handler.cafes), "sample": len(venues), "graphBytes": destination.stat().st_size}))
    if len(venues) != 16:
        raise SystemExit("Insufficient cafes: preserve the partial sample and report coverage")


if __name__ == "__main__":
    main()
