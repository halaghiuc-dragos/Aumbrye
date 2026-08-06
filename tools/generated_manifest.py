"""Track SHA-256 hashes of generator output for idempotent writes."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "tools" / ".generated-manifest.json"


def load_manifest() -> dict[str, str]:
    if not MANIFEST_PATH.is_file():
        return {}
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def save_manifest(manifest: dict[str, str]) -> None:
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def rel_path(path: Path) -> str:
    return path.resolve().relative_to(ROOT).as_posix()


def prepare_write(path: Path, new_content: str, *, force: bool, dry_run: bool) -> bool:
    """Return True when the file should be written."""
    key = rel_path(path)
    if dry_run:
        print(f"would write {key}")
        return False
    if not path.is_file():
        return True
    existing = path.read_text(encoding="utf-8")
    if existing == new_content:
        return True
    manifest = load_manifest()
    if key in manifest and manifest[key] == sha256_text(existing):
        return True
    if force:
        return True
    raise SystemExit(
        f"Refusing to overwrite {key}: content differs from last generator output. "
        "Pass --force to overwrite."
    )


def record_write(path: Path, content: str) -> None:
    manifest = load_manifest()
    manifest[rel_path(path)] = sha256_text(content)
    save_manifest(manifest)
