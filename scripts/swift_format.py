"""Run the repository-pinned macOS SwiftFormat (Python 3.11+, no pip dependencies)."""
from pathlib import Path
import argparse
import hashlib
import io
import json
import platform
import subprocess
import tempfile
import zipfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
mode = parser.add_mutually_exclusive_group(required=True)
mode.add_argument("--check", action="store_true", help="Fail if Swift files need formatting")
mode.add_argument("--write", action="store_true", help="Format repository Swift files")
args = parser.parse_args()
if platform.system() != "Darwin":
    raise SystemExit("The pinned tool is macOS-only. Run this check on your Mac or the style CI job.")
manifest = json.loads((root / "tools/swiftformat.json").read_text())
cache = root / ".tools/swiftformat" / manifest["version"]
binary = cache / "swiftformat"
if not binary.exists():
    print("Downloading SwiftFormat " + manifest["version"], flush=True)
    # macOS curl uses the system trust store, including locally managed certificates.
    try:
        archive_data = subprocess.check_output([
            "/usr/bin/curl", "--fail", "--location", "--silent", "--show-error",
            "--connect-timeout", "10", "--max-time", "60", manifest["macos_archive_url"],
        ])
    except subprocess.CalledProcessError as error:
        raise SystemExit("SwiftFormat download failed; check network/TLS access and retry.") from error
    if hashlib.sha256(archive_data).hexdigest() != manifest["macos_archive_sha256"]:
        raise SystemExit("SwiftFormat archive checksum mismatch; no executable installed.")
    with zipfile.ZipFile(io.BytesIO(archive_data)) as archive:
        executable = archive.read("swiftformat")
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=cache, delete=False) as temporary:
        temporary.write(executable)
        temporary_path = Path(temporary.name)
    temporary_path.chmod(0o755)
    temporary_path.replace(binary)
version = subprocess.check_output([str(binary), "--version"], text=True).strip()
if version != manifest["version"]:
    raise SystemExit("Cached formatter version differs from tools/swiftformat.json; remove its local cache and retry.")
# Use Git's tracked + unignored file inventory; never recurse into build/dependency caches.
paths = subprocess.check_output(
    ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root
).decode().split("\0")
sources = sorted({p for p in paths if p.endswith(".swift") and (root / p).is_file()})
if not sources:
    raise SystemExit("No Swift source files found.")
command = [str(binary), *sources, "--config", str(root / ".swiftformat"), "--cache", "ignore"]
if args.check:
    command.append("--lint")
raise SystemExit(subprocess.call(command, cwd=root))
