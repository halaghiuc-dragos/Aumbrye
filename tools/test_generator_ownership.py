from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
import json
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent / "voxel-import"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
sys.path.insert(0, str(Path(__file__).resolve().parent / "icon-gen"))
import cli as voxel_import_cli
import convert as voxel_source_generator
from vox_io import VoxelModel, encode_vox, write_vox
import generate_ui_assets
import audio_synth
import generate_ui_skin_assets
import atlas_build


class GeneratorOwnershipTests(unittest.TestCase):
    def test_item_atlas_adds_new_items_without_moving_or_redrawing_existing_cells(self) -> None:
        root = Path(__file__).resolve().parents[1]
        old_image = atlas_build.Image.open(
            root / "apps" / "game" / "client" / "assets" / "ui" / "item_icons.png"
        ).convert("RGBA")
        old_manifest = json.loads(
            (root / "content" / "ui" / "item_icon_atlas.json").read_text(encoding="utf-8")
        )
        cells = atlas_build.item_cells()
        hunter_cell = old_manifest["cells"].pop("hunters_lure")
        with tempfile.TemporaryDirectory(prefix="aumbrye-item-atlas-test-") as temp_dir:
            temp = Path(temp_dir)
            assets, content_ui = temp / "assets", temp / "content-ui"
            assets.mkdir()
            content_ui.mkdir()
            candidate_baseline = old_image.copy()
            x, y = hunter_cell["col"] * 16, hunter_cell["row"] * 16
            candidate_baseline.paste((0, 0, 0, 0), (x, y, x + 16, y + 16))
            candidate_baseline.save(assets / "item_icons.png")
            (content_ui / "item_icon_atlas.json").write_text(
                json.dumps(old_manifest), encoding="utf-8"
            )
            with (
                patch.object(atlas_build, "ASSETS", assets),
                patch.object(atlas_build, "CONTENT_UI", content_ui),
                patch.object(atlas_build, "item_cells", return_value=cells),
            ):
                candidate, candidate_manifest = atlas_build.build_item_atlas()
            self.assertEqual(candidate_manifest["cells"]["hunters_lure"], hunter_cell)
            for key, cell in old_manifest["cells"].items():
                self.assertEqual(candidate_manifest["cells"][key], cell)
                box = (cell["col"] * 16, cell["row"] * 16,
                       (cell["col"] + 1) * 16, (cell["row"] + 1) * 16)
                self.assertEqual(candidate.crop(box).tobytes(), old_image.crop(box).tobytes())

    def test_ogg_helper_refuses_unowned_direct_writes(self) -> None:
        with self.assertRaisesRegex(ValueError, "requires generator and source paths"):
            audio_synth.write_ogg(Path("content/audio/unowned.ogg"), audio_synth.silence(0.001))

    def test_retired_cuboid_writer_cannot_overwrite_canonical_character_assets(self) -> None:
        with self.assertRaisesRegex(SystemExit, "sole character-voxel owner"):
            generate_ui_assets.generate_character_assets()

    def test_retired_icon_publishers_cannot_bypass_canonical_atlas_owner(self) -> None:
        root = Path(__file__).resolve().parents[1]
        retired_publishers = [
            root / "tools" / "icon-gen" / "item_icons.py",
            root / "tools" / "icon-gen" / "status_icons.py",
        ]
        for publisher in retired_publishers:
            with self.subTest(publisher=publisher.name):
                result = subprocess.run(
                    [sys.executable, str(publisher)],
                    cwd=root,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("retired", result.stderr)
                self.assertIn("atlas", result.stderr.lower())

    def test_retired_voxel_generate_all_cannot_overwrite_character_manifests(self) -> None:
        root = Path(__file__).resolve().parents[1]
        result = subprocess.run(
            [sys.executable, str(root / "tools" / "voxel-import" / "cli.py"), "generate-all"],
            cwd=root,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("generate-all is retired", result.stderr)
        self.assertIn("generate_character_voxels.py", result.stderr)

    def test_voxel_convert_stages_candidates_through_owned_writer(self) -> None:
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix="aumbrye-voxel-ownership-test-") as temp_dir:
            source_root = Path(temp_dir) / "source"
            source_path = source_root / "sample.vox"
            model = VoxelModel(size=(1, 1, 1))
            model.palette[1] = (0.8, 0.3, 0.2)
            model.set_voxel(0, 0, 0, 1)
            source_path.parent.mkdir(parents=True, exist_ok=True)
            source_path.write_bytes(encode_vox(model))
            output_root = root / "apps" / "game" / "client" / "assets" / "characters" / "unused_audit"
            with patch.object(voxel_import_cli, "write_generated_bytes_set") as writer:
                voxel_import_cli.convert_vox_tree(
                    source_root, output_root, dry_run=True
                )
            self.assertEqual(writer.call_count, 1)
            outputs = writer.call_args.args[0]
            self.assertEqual(len(outputs), 1)
            output_path, output_bytes = outputs[0]
            self.assertEqual(output_path, output_root / "sample.tres")
            self.assertTrue(output_bytes.startswith(b'[gd_resource type="ArrayMesh"'))
            self.assertEqual(writer.call_args.kwargs["sources"], [source_path])
            self.assertTrue(writer.call_args.kwargs["dry_run"])

    def test_legacy_voxel_writers_fail_closed(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "direct .vox writes are retired"):
            write_vox(Path("art-source/characters/unowned.vox"), VoxelModel())
        with self.assertRaisesRegex(SystemExit, "legacy per-archetype voxel publishing is retired"):
            voxel_import_cli.generate_archetype(object())

    def test_voxel_source_generation_uses_owned_dry_run_publication(self) -> None:
        from types import SimpleNamespace

        model = VoxelModel(size=(1, 1, 1))
        part = SimpleNamespace(name="Head", size=(1, 1, 1), accent_band=False)
        spec = SimpleNamespace(
            id="ownership_fixture", theme_index=0, parts=[part]
        )
        with tempfile.TemporaryDirectory(prefix="aumbrye-vox-source-test-") as temp_dir:
            with (
                patch.object(voxel_source_generator, "ARCHETYPES", [spec]),
                patch.object(voxel_source_generator, "EQUIPMENT_VISUALS", {}),
                patch.object(voxel_source_generator, "ART_SOURCE", Path(temp_dir)),
                patch.object(voxel_source_generator, "_palette_colours", return_value=((0.5, 0.4, 0.3), (0.2, 0.3, 0.4))),
                patch.object(voxel_source_generator, "build_box_model", return_value=model),
                patch.object(voxel_source_generator, "write_generated_bytes_set", return_value=[]) as writer,
            ):
                voxel_source_generator.generate_sources(dry_run=True)
            self.assertEqual(writer.call_count, 1)
            outputs = writer.call_args.args[0]
            self.assertEqual(len(outputs), 1)
            output_path, output_bytes = outputs[0]
            self.assertEqual(output_path, Path(temp_dir) / "ownership_fixture" / "head.vox")
            self.assertTrue(output_bytes.startswith(b"VOX "))
            self.assertTrue(writer.call_args.kwargs["dry_run"])

    def test_ui_skin_generator_stages_validated_candidates_without_direct_writes(self) -> None:
        with patch.object(generate_ui_skin_assets, "write_generated_bytes_set", return_value=[]) as writer:
            generated = generate_ui_skin_assets.make_paperdoll_png()
            generate_ui_skin_assets.validate_png(generated, 96, 160)
            generate_ui_skin_assets.generate(font_source=None, force=False, dry_run=True)
        self.assertEqual(writer.call_count, 1)
        outputs = writer.call_args.args[0]
        self.assertEqual(len(outputs), 1)
        self.assertEqual(outputs[0][0], generate_ui_skin_assets.PNG_PATH)
        self.assertEqual(outputs[0][1], generated)
        self.assertTrue(writer.call_args.kwargs["dry_run"])
        self.assertEqual(writer.call_args.kwargs["sources"], [])

    def test_ui_skin_png_validation_rejects_corrupt_chunks(self) -> None:
        generated = bytearray(generate_ui_skin_assets.make_paperdoll_png())
        generated[-8] ^= 1
        with self.assertRaisesRegex(ValueError, "checksum"):
            generate_ui_skin_assets.validate_png(bytes(generated), 96, 160)

    def test_ui_skin_can_adopt_only_byte_identical_existing_png(self) -> None:
        expected = generate_ui_skin_assets.make_paperdoll_png()
        self.assertEqual(generate_ui_skin_assets.PNG_PATH.read_bytes(), expected)
        with (
            patch.object(generate_ui_skin_assets, "write_generated_bytes_set", return_value=[]),
            patch.object(generate_ui_skin_assets, "load_manifest", return_value={}),
            patch.object(generate_ui_skin_assets, "record_write") as record_write,
        ):
            generate_ui_skin_assets.generate(
                font_source=None, force=False, dry_run=False, adopt_identical=True
            )
        record_write.assert_called_once_with(
            generate_ui_skin_assets.PNG_PATH,
            expected,
            generator=Path(generate_ui_skin_assets.__file__).resolve(),
            sources=[],
        )

    def test_retired_m6_batch_stops_before_any_direct_content_writer(self) -> None:
        root = Path(__file__).resolve().parents[1]
        script = (root / "scripts" / "balance" / "generate-m6-items.ps1").read_text(encoding="utf-8")
        guard, _, historical_body = script.partition("# Historical implementation retained below")
        self.assertIn("throw \"generate-m6-items.ps1 is retired", guard)
        self.assertNotIn("Set-Content", guard)
        self.assertIn("Set-Content", historical_body)


if __name__ == "__main__":
    unittest.main()
