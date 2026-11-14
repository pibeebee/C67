#!/usr/bin/env python3
"""Validate immutable import evidence and explicitly reviewed maintained-source changes."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SHA256 = re.compile(r"[0-9a-f]{64}")


def maintained_path(path, owner="publication-manifest.json"):
    """Functional evolution is allowed only for maintained implementation/guide files."""
    parts = PurePosixPath(path).parts
    if not parts or PurePosixPath(path).is_absolute() or ".." in parts:
        return False
    if owner == "context-lab-publication.json":
        # The user maintains this decision log; other imported source records stay archival.
        if path == "docs/source-records/CBL.md":
            return True
        prefix = "apps/c67-local-server-lab/"
        if not path.startswith(prefix):
            return False
        tail = path[len(prefix):]
        return (tail in {"Package.swift", "README.md", "ContextHarness/README.md", "ContextHarness/project.yml"}
                or (tail.endswith(".swift") and tail.startswith(("Sources/", "Tests/", "ContextHarness/App/", "ContextHarness/UITests/", "ContextHarness/Tests/"))))
    if owner != "publication-manifest.json":
        return False
    if path in {"apps/c67-foundation-lab/App/VisitTimingModel.swift", "apps/c67-foundation-lab/UITests/QualityLabUITests.swift", "apps/c67-foundation-lab/App/QualityLabViews.swift"}:
        return True
    prefix = "apps/c67-trip-integration/"
    if not path.startswith(prefix):
        return False
    tail = path[len(prefix):]
    return (tail in {"README.md", "docs/VENDOR.md", "Packages/TripIntegration/Package.swift"}
            or (tail.endswith(".swift") and tail.startswith(("App/", "UITests/", "Packages/TripIntegration/Sources/"))))


def safe_file(root, path):
    if not isinstance(path, str) or not path or PurePosixPath(path).is_absolute() or ".." in PurePosixPath(path).parts:
        return False
    return (root / path).resolve().is_relative_to(root.resolve()) and (root / path).is_file()


def validate(root, manifest, development=None, published_paths=None, additional_manifests=()):
    issues = []
    imports = {}
    owners = {}
    for index, source in enumerate((manifest, *additional_manifests)):
        for entry in source["files"]:
            if entry["disposition"] != "included":
                continue
            path = entry["publicationPath"]
            if path in imports:
                issues.append(f"{path}: duplicate publication path")
                continue
            imports[path] = entry
            owners[path] = "publication-manifest.json" if index == 0 else "context-lab-publication.json"
    changes = {}
    if development is not None:
        if development.get("schemaVersion") != 1 or not isinstance(development.get("changes"), list):
            return ["development ledger: unsupported schema"]
        for change in development["changes"]:
            if not isinstance(change, dict):
                issues.append("development ledger: invalid entry"); continue
            path = change.get("publicationPath")
            owner = change.get("publicationManifest", "publication-manifest.json")
            if not isinstance(path, str) or path in changes or owners.get(path) != owner or not maintained_path(path, owner):
                issues.append(f"{path}: duplicate, unknown or archival development path"); continue
            baseline = imports[path]["publishedSHA256"]
            current = change.get("currentSHA256", "")
            if (change.get("importedPublishedSHA256") != baseline
                    or not isinstance(current, str) or SHA256.fullmatch(current) is None or current == baseline
                    or not isinstance(change.get("reason"), str) or not change["reason"].strip()
                    or not safe_file(root, change.get("verification"))):
                issues.append(f"{path}: invalid baseline, current hash, reason or verification reference"); continue
            changes[path] = change
    for path, entry in imports.items():
        if not safe_file(root, path):
            issues.append(path + ": missing or unsafe publication copy"); continue
        if published_paths is not None and "poc-journey/" + path not in published_paths:
            issues.append(path + ": included file is ignored or absent from the publication tree")
        digest = hashlib.sha256((root / path).read_bytes()).hexdigest()
        expected = changes[path]["currentSHA256"] if path in changes else entry["publishedSHA256"]
        if digest != expected:
            issues.append(path + (": maintained-source hash changed" if path in changes else ": publication hash changed"))
    return issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh-publication-hashes", action="store_true", help="Deprecated; import hashes are immutable")
    args = parser.parse_args()
    if args.refresh_publication_hashes:
        parser.error("Import hashes are immutable. Record reviewed functional changes in development-manifest.json.")
    manifest = json.loads((ROOT / "evidence/publication-manifest.json").read_text())
    context_manifest = ROOT / "evidence/context-lab-publication.json"
    additional = [json.loads(context_manifest.read_text())] if context_manifest.exists() else []
    ledger = ROOT / "evidence/development-manifest.json"
    development = json.loads(ledger.read_text()) if ledger.exists() else None
    published_paths = set(subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "poc-journey"],
        cwd=ROOT.parent,
    ).decode().split("\0"))
    issues = validate(ROOT, manifest, development, published_paths, additional)
    if issues:
        raise SystemExit("\n".join(issues))
    included = sum(entry["disposition"] == "included" for source in [manifest, *additional] for entry in source["files"])
    print(f"PASS: {included} imported publication copies; {len(development['changes']) if development else 0} reviewed maintained-source changes. Original/import hashes remain unchanged.")


if __name__ == "__main__":
    main()
