"""Shared writer for the asset generators: publish only the outputs whose bytes changed."""

from __future__ import annotations

from pathlib import Path


def write_bytes_set(outputs: list[tuple[Path, bytes]], *, dry_run: bool = False) -> list[Path]:
    """Writes each `(path, bytes)` that differs from what is on disk and returns the paths it changed
    (the ones it would change, under `dry_run`)."""
    changed: list[Path] = []
    for path, data in outputs:
        if path.is_file() and path.read_bytes() == data:
            continue
        changed.append(path)
        if not dry_run:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    return changed
