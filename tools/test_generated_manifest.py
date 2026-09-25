from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import generated_manifest as manifest


class GeneratedManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="aumbrye-generator-manifest-")
        self.root = Path(self.temp.name)
        self.tools = self.root / "tools"
        self.tools.mkdir()
        self.source = self.tools / "generator.py"
        self.source.write_text("GENERATOR_VERSION = 1\n", encoding="utf-8")
        self.input = self.root / "input.json"
        self.input.write_text('{"source":true}\n', encoding="utf-8")
        self.manifest_path = self.tools / ".generated-manifest.json"
        self.lock_path = self.tools / ".generated-manifest.lock"
        self.patches = [
            patch.object(manifest, "ROOT", self.root),
            patch.object(manifest, "MANIFEST_PATH", self.manifest_path),
            patch.object(manifest, "MANIFEST_LOCK_PATH", self.lock_path),
        ]
        for active_patch in self.patches:
            active_patch.start()

    def tearDown(self) -> None:
        for active_patch in reversed(self.patches):
            active_patch.stop()
        self.temp.cleanup()

    def test_staged_json_records_owner_and_source_hashes(self) -> None:
        output = self.root / "content" / "generated.json"
        content = '{"generated":true}\n'
        self.assertTrue(manifest.write_generated_text(
            output,
            content,
            generator=self.source,
            sources=[self.input],
            force=False,
            dry_run=False,
            seed=73,
        ))
        self.assertEqual(json.loads(output.read_text(encoding="utf-8")), {"generated": True})
        entry = manifest.load_manifest()["content/generated.json"]
        self.assertEqual(entry["generator"], "tools/generator.py")
        self.assertEqual(entry["generatorSha256"], hashlib.sha256(self.source.read_bytes()).hexdigest())
        self.assertEqual(entry["sources"]["input.json"], hashlib.sha256(self.input.read_bytes()).hexdigest())
        self.assertEqual(entry["seed"], 73)
        self.assertFalse(entry["manualOverride"])

    def test_manual_changes_are_protected_and_force_is_recorded(self) -> None:
        output = self.root / "content" / "generated.json"
        output.parent.mkdir()
        output.write_text('{"authored":true}\n', encoding="utf-8")
        with self.assertRaises(SystemExit):
            manifest.write_generated_text(
                output, '{"generated":true}\n', generator=self.source, sources=[self.input],
                force=False, dry_run=False,
            )
        self.assertEqual(json.loads(output.read_text(encoding="utf-8")), {"authored": True})
        manifest.write_generated_text(
            output, '{"generated":true}\n', generator=self.source, sources=[self.input],
            force=True, dry_run=False,
        )
        self.assertTrue(manifest.load_manifest()["content/generated.json"]["manualOverride"])

    def test_legacy_hash_manifest_entries_remain_compatible(self) -> None:
        output = self.root / "content" / "legacy.txt"
        content = "generated\n"
        output.parent.mkdir()
        output.write_text(content, encoding="utf-8")
        self.manifest_path.write_text(
            json.dumps({"content/legacy.txt": manifest.sha256_text(content)}), encoding="utf-8"
        )
        self.assertTrue(manifest.prepare_write(output, "updated\n", force=False, dry_run=False))

    def test_manifest_audit_detects_generator_and_input_drift(self) -> None:
        output = self.root / "content" / "generated.json"
        manifest.write_generated_text(
            output, '{"generated":true}\n', generator=self.source, sources=[self.input],
            force=False, dry_run=False,
        )
        self.assertEqual(manifest.validate_manifest(), [])
        self.source.write_text("GENERATOR_VERSION = 2\n", encoding="utf-8")
        self.input.write_text('{"source":false}\n', encoding="utf-8")
        drift = {(issue["kind"], issue["detail"]) for issue in manifest.validate_manifest()}
        self.assertIn(("stale-generator", "tools/generator.py"), drift)
        self.assertIn(("stale-source", "input.json"), drift)

    def test_empty_manifest_is_not_reported_as_a_clean_audit(self) -> None:
        self.assertEqual(manifest.validate_manifest()[0]["kind"], "empty-manifest")

    def test_missing_input_is_rejected_before_staging(self) -> None:
        output = self.root / "content" / "not-written.json"
        with self.assertRaises(FileNotFoundError):
            manifest.write_generated_text(
                output, '{"generated":true}\n', generator=self.source,
                sources=[self.root / "missing.json"], force=False, dry_run=False,
            )
        self.assertFalse(output.exists())

    def test_dry_run_detects_manual_edits_without_writing(self) -> None:
        output = self.root / "content" / "dry-run.json"
        output.parent.mkdir()
        authored = '{"authored":true}\n'
        output.write_text(authored, encoding="utf-8")
        with self.assertRaises(SystemExit):
            manifest.prepare_write(output, '{"generated":true}\n', force=False, dry_run=True)
        self.assertEqual(output.read_text(encoding="utf-8"), authored)

    def test_binary_ogg_outputs_are_staged_hashed_and_protected(self) -> None:
        output = self.root / "assets" / "sound.ogg"
        ogg = b"OggS" + bytes(32)
        self.assertTrue(manifest.write_generated_bytes(
            output, ogg, generator=self.source, sources=[self.input],
            force=False, dry_run=False, seed=11,
        ))
        self.assertEqual(output.read_bytes(), ogg)
        self.assertEqual(
            manifest.load_manifest()["assets/sound.ogg"]["outputSha256"],
            hashlib.sha256(ogg).hexdigest(),
        )
        authored = b"OggS" + bytes([1]) * 32
        output.write_bytes(authored)
        with self.assertRaises(SystemExit):
            manifest.write_generated_bytes(
                output, ogg, generator=self.source, sources=[self.input],
                force=False, dry_run=True,
            )
        self.assertEqual(output.read_bytes(), authored)

    def test_binary_set_preflights_every_manual_output_before_writing(self) -> None:
        owned = self.root / "assets" / "new.ogg"
        authored = self.root / "assets" / "manual.ogg"
        authored.parent.mkdir()
        authored_bytes = b"OggS" + bytes([2]) * 32
        authored.write_bytes(authored_bytes)
        with self.assertRaises(SystemExit):
            manifest.write_generated_bytes_set(
                [(owned, b"OggS" + bytes(32)), (authored, b"OggS" + bytes(32))],
                generator=self.source, sources=[self.input], force=False, dry_run=False,
            )
        self.assertFalse(owned.exists())
        self.assertEqual(authored.read_bytes(), authored_bytes)


if __name__ == "__main__":
    unittest.main()
