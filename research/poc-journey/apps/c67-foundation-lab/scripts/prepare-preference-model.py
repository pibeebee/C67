#!/usr/bin/env python3
"""Download pinned, public MIT E5 assets; verify bytes before bundling. No user data is uploaded."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "Packages/PreferenceLearning/Sources/PreferenceLearning/Resources/Model"
REVISION = "614241f622f53c4eeff9890bdc4f31cfecc418b3"
FILES = {
    "model.onnx": ("onnx/model_qint8_avx512_vnni.onnx", "sha256", "dd476dd0c2514e9b9be83aeb3853fac0763e0bdf4a71645407587d77c48a2d88"),
    "tokenizer.json": ("tokenizer.json", "sha256", "0b44a9d7b51c3c62626640cda0e2c2f70fdacdc25bbbd68038369d14ebdf4c39"),
    "tokenizer_config.json": ("tokenizer_config.json", "git", "059214673d9d6d2ee319411e2ffec8c024b816d5"),
    "config.json": ("config.json", "git", "60a2a84020f1d74cc53ea9e8c4e91cf4af6c2b68"),
}

def digest(data, kind):
    return hashlib.sha256(data).hexdigest() if kind == "sha256" else hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()

DEST.mkdir(parents=True, exist_ok=True)
manifest = {"model": "intfloat/multilingual-e5-small", "revision": REVISION,
            "artifact": "onnx/model_qint8_avx512_vnni.onnx", "license": "MIT", "files": {}}
for name, (remote, kind, expected) in FILES.items():
    path = DEST / name
    url = f"https://huggingface.co/intfloat/multilingual-e5-small/resolve/{REVISION}/{remote}"
    if not path.exists() or digest(path.read_bytes(), kind) != expected:
        with tempfile.NamedTemporaryFile(dir=DEST, suffix=".partial", delete=False) as temporary:
            temp = Path(temporary.name)
        try:
            print("Downloading", remote, flush=True)
            subprocess.run(["/usr/bin/curl", "-fL", "--retry", "2", "--max-time", "600", "-o", str(temp), url], check=True)
            data = temp.read_bytes()
            if digest(data, kind) != expected:
                raise RuntimeError(f"Integrity mismatch: {remote}")
            temp.replace(path)
        finally:
            temp.unlink(missing_ok=True)
    data = path.read_bytes()
    manifest["files"][name] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data), "source": url}
    print("Verified", name, len(data), flush=True)
(DEST / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
