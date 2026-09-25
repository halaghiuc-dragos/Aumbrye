#!/usr/bin/env python3
"""Verify all registered generated outputs against owner and input fingerprints."""

from __future__ import annotations

import json

from generated_manifest import load_manifest, validate_manifest

issues = validate_manifest()
summary = {
    "registeredOutputs": len(load_manifest()),
    "issues": len(issues),
    "findings": issues,
}
print(json.dumps(summary, indent=2))
raise SystemExit(1 if issues else 0)
