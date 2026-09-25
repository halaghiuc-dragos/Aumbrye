"""Track generated outputs, their owners and source fingerprints."""

from __future__ import annotations

import hashlib
import json
import os
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "tools" / ".generated-manifest.json"
MANIFEST_LOCK_PATH = ROOT / "tools" / ".generated-manifest.lock"


def load_manifest() -> dict[str, object]:
    if not MANIFEST_PATH.is_file():
        return {}
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def save_manifest(manifest: dict[str, object]) -> None:
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    temp_path = MANIFEST_PATH.with_suffix(".tmp")
    temp_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temp_path, MANIFEST_PATH)


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def rel_path(path: Path) -> str:
    return path.resolve().relative_to(ROOT).as_posix()


def _output_hash(entry: object) -> str:
    if isinstance(entry, str):  # Backward compatibility with the original hash-only manifest.
        return entry
    if isinstance(entry, dict):
        return str(entry.get("outputSha256", ""))
    return ""


def validate_manifest() -> list[dict[str, str]]:
    """Return missing or stale output/owner/input records without modifying the manifest."""
    issues: list[dict[str, str]] = []
    manifest = load_manifest()
    if not manifest:
        return [{"kind": "empty-manifest", "path": "tools/.generated-manifest.json", "detail": "no generated outputs are registered"}]
    for output_key, entry in sorted(manifest.items()):
        if not isinstance(entry, dict):
            issues.append({"kind": "legacy-entry", "path": output_key, "detail": "output has no provenance metadata"})
            continue
        output_path = ROOT / output_key
        if not output_path.is_file():
            issues.append({"kind": "missing-output", "path": output_key, "detail": "generated output is missing"})
        elif hashlib.sha256(output_path.read_bytes()).hexdigest() != _output_hash(entry):
            issues.append({"kind": "modified-output", "path": output_key, "detail": "output differs from its recorded hash"})
        generator_key = str(entry.get("generator", ""))
        generator_path = ROOT / generator_key if generator_key else None
        if generator_path is None or not generator_path.is_file():
            issues.append({"kind": "missing-generator", "path": output_key, "detail": generator_key or "generator is not recorded"})
        elif hashlib.sha256(generator_path.read_bytes()).hexdigest() != str(entry.get("generatorSha256", "")):
            issues.append({"kind": "stale-generator", "path": output_key, "detail": generator_key})
        source_hashes = entry.get("sources", {})
        if not isinstance(source_hashes, dict):
            issues.append({"kind": "invalid-sources", "path": output_key, "detail": "source hashes are malformed"})
            continue
        for source_key, expected_hash in sorted(source_hashes.items()):
            source_path = ROOT / str(source_key)
            if not source_path.is_file():
                issues.append({"kind": "missing-source", "path": output_key, "detail": str(source_key)})
            elif hashlib.sha256(source_path.read_bytes()).hexdigest() != str(expected_hash):
                issues.append({"kind": "stale-source", "path": output_key, "detail": str(source_key)})
    return issues


def prepare_write(path: Path, new_content: str, *, force: bool, dry_run: bool) -> bool:
    """Return True when the file should be written."""
    key = rel_path(path)
    if not path.is_file():
        if dry_run:
            print(f"would write {key}")
            return False
        return True
    existing = path.read_text(encoding="utf-8")
    if existing == new_content:
        if dry_run:
            print(f"already matches generated content: {key}")
            return False
        return True
    manifest = load_manifest()
    if key in manifest and _output_hash(manifest[key]) == sha256_text(existing):
        if dry_run:
            print(f"would update generator-owned output: {key}")
            return False
        return True
    if force:
        if dry_run:
            print(f"would force-update {key}")
            return False
        return True
    raise SystemExit(
        f"Refusing to overwrite {key}: content differs from last generator output. "
        "Pass --force to overwrite."
    )


def write_generated_text(
    path: Path,
    content: str,
    *,
    generator: Path,
    sources: list[Path],
    force: bool,
    dry_run: bool,
    seed: int | None = None,
) -> bool:
    """Stage one output beside its destination, validate it, then atomically replace the target."""
    if not generator.is_file():
        raise FileNotFoundError(f"Generator source does not exist: {generator}")
    for source in sources:
        if not source.is_file():
            raise FileNotFoundError(f"Generated input source does not exist: {source}")
    rel_path(path)
    rel_path(generator)
    for source in sources:
        rel_path(source)
    if not prepare_write(path, content, force=force, dry_run=dry_run):
        return False
    if dry_run:
        return False
    if not content.strip():
        raise ValueError(f"Refusing to stage empty generated output: {rel_path(path)}")
    if path.suffix.lower() == ".json":
        json.loads(content)
    previous_exists = path.is_file()
    previous_content = path.read_text(encoding="utf-8") if previous_exists else ""
    previous_entry = load_manifest().get(rel_path(path)) if previous_exists else None
    previous_owned = previous_exists and _output_hash(previous_entry) == sha256_text(previous_content)
    manual_override = previous_exists and previous_content != content and not previous_owned and force
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".stage", dir=path.parent)
    staged_path = Path(temp_name)
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as staged_file:
        staged_file.write(content)
        staged_file.flush()
        os.fsync(staged_file.fileno())
    if staged_path.read_text(encoding="utf-8") != content:
        raise IOError(f"Staged output failed byte-for-byte check: {rel_path(path)}")
    os.replace(staged_path, path)
    record_write(
        path,
        content,
        generator=generator,
        sources=sources,
        seed=seed,
        manual_override=manual_override,
    )
    return True


def write_generated_bytes(
    path: Path,
    content: bytes,
    *,
    generator: Path,
    sources: list[Path],
    force: bool,
    dry_run: bool,
    seed: int | None = None,
) -> bool:
    """Stage one binary output atomically while preserving unowned/manual assets by default."""
    if not generator.is_file():
        raise FileNotFoundError(f"Generator source does not exist: {generator}")
    for source in sources:
        if not source.is_file():
            raise FileNotFoundError(f"Generated input source does not exist: {source}")
    rel_path(path)
    rel_path(generator)
    for source in sources:
        rel_path(source)
    if not content:
        raise ValueError(f"Refusing to stage empty generated output: {rel_path(path)}")
    if path.suffix.lower() == ".ogg" and (len(content) < 28 or content[:4] != b"OggS"):
        raise ValueError(f"Generated Ogg output has an invalid container header: {rel_path(path)}")
    if path.suffix.lower() == ".json":
        json.loads(content.decode("utf-8"))

    key = rel_path(path)
    previous = path.read_bytes() if path.is_file() else None
    manifest = load_manifest()
    old_hash = _output_hash(manifest.get(key))
    owned = previous is not None and old_hash == sha256_bytes(previous)
    if previous == content:
        if dry_run:
            print(f"already matches generated content: {key}")
        elif owned:
            # A source/generator revision can leave bytes unchanged while the ownership
            # fingerprints become stale. Refresh those fingerprints without replacing the
            # output, but never adopt an identical unowned/manual file as generated.
            old_entry = manifest.get(key, {})
            record_write(
                path,
                content,
                generator=generator,
                sources=sources,
                seed=seed,
                manual_override=bool(old_entry.get("manualOverride", False)),
            )
        return False
    if previous is not None and not owned and not force:
        raise SystemExit(
            f"Refusing to overwrite {key}: content differs from last generator output. "
            "Pass --force to overwrite."
        )
    if dry_run:
        print(f"would {'force-' if previous is not None and not owned else ''}write {key}")
        return False

    manual_override = previous is not None and not owned and force
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".stage", dir=path.parent)
    staged_path = Path(temp_name)
    with os.fdopen(fd, "wb") as staged_file:
        staged_file.write(content)
        staged_file.flush()
        os.fsync(staged_file.fileno())
    if staged_path.read_bytes() != content:
        raise IOError(f"Staged output failed byte-for-byte check: {key}")
    os.replace(staged_path, path)
    record_write(
        path,
        content,
        generator=generator,
        sources=sources,
        seed=seed,
        manual_override=manual_override,
    )
    return True


def write_generated_bytes_set(
    outputs: list[tuple[Path, bytes]],
    *,
    generator: Path,
    sources: list[Path],
    force: bool,
    dry_run: bool,
    seed: int | None = None,
) -> list[Path]:
    """Preflight a complete binary output set before atomically replacing any individual file."""
    seen: set[str] = set()
    for path, content in outputs:
        key = rel_path(path)
        if key in seen:
            raise ValueError(f"Duplicate generated output path: {key}")
        seen.add(key)
        write_generated_bytes(
            path, content, generator=generator, sources=sources,
            force=force, dry_run=True, seed=seed,
        )
    if dry_run:
        return []
    written: list[Path] = []
    for path, content in outputs:
        if write_generated_bytes(
            path, content, generator=generator, sources=sources,
            force=force, dry_run=False, seed=seed,
        ):
            written.append(path)
    return written


def record_write(
    path: Path,
    content: str | bytes,
    *,
    generator: Path | None = None,
    sources: list[Path] | None = None,
    seed: int | None = None,
    manual_override: bool = False,
) -> None:
    deadline = time.monotonic() + 15.0
    lock_fd: int | None = None
    while lock_fd is None:
        try:
            lock_fd = os.open(MANIFEST_LOCK_PATH, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        except FileExistsError:
            try:
                holder = int(MANIFEST_LOCK_PATH.read_text(encoding="ascii").strip())
                os.kill(holder, 0)
            except (ValueError, ProcessLookupError):
                MANIFEST_LOCK_PATH.unlink(missing_ok=True)
                continue
            except PermissionError:
                pass
            if time.monotonic() >= deadline:
                raise RuntimeError("Timed out waiting for generated manifest lock")
            time.sleep(0.05)
    try:
        os.write(lock_fd, str(os.getpid()).encode("ascii"))
        manifest = load_manifest()
        content_bytes = content.encode("utf-8") if isinstance(content, str) else content
        entry: dict[str, object] = {"outputSha256": sha256_bytes(content_bytes)}
        if generator is not None:
            entry["generator"] = rel_path(generator)
            entry["generatorSha256"] = sha256_bytes(generator.read_bytes())
        if sources is not None:
            entry["sources"] = {
                rel_path(source): hashlib.sha256(source.read_bytes()).hexdigest()
                for source in sorted(sources, key=lambda item: rel_path(item))
            }
        entry["seed"] = seed
        entry["manualOverride"] = manual_override
        manifest[rel_path(path)] = entry
        save_manifest(manifest)
    finally:
        os.close(lock_fd)
        try:
            MANIFEST_LOCK_PATH.unlink()
        except FileNotFoundError:
            pass
