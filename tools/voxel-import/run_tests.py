"""Minimal runner for the voxel-import tests.

`test_convert.py` is written as plain functions rather than `unittest.TestCase`
subclasses, so `python -m unittest` does not discover them. This keeps the tests
in their existing style while giving CI (C-40) an exit code to gate on.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import test_convert  # noqa: E402


def main() -> int:
    failures = 0
    for name in sorted(dir(test_convert)):
        if not name.startswith("test_"):
            continue
        try:
            getattr(test_convert, name)()
        except Exception as exc:  # noqa: BLE001 - report every failure, not the first
            failures += 1
            print(f"FAIL {name}: {type(exc).__name__}: {exc}")
        else:
            print(f"PASS {name}")
    print(f"failures: {failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
