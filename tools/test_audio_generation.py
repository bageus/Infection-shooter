#!/usr/bin/env python3
"""Run real generator entrypoints against isolated roots; never touch project audio."""
import contextlib
import hashlib
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
import audio_generation as safety
import build_sounds as base
import build_weapon_sounds as weapons
import build_destruction_sounds as destruction
import build_added_audio as historical


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encode(_sound, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"generated " + path.name.encode())


class AudioGenerationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.root = self.directory / "audio/sfx"
        self.root.mkdir(parents=True)
        self.manifest = self.directory / "manifest.json"
        self.credits = self.root.parent / "CREDITS.md"
        self.original_credits = "# Credits\r\n\r\n## Owner recordings\r\nKeep this text: Автор.\r\n\r\n".encode()
        self.credits.write_bytes(self.original_credits)
        self.outputs = {
            "build_sounds": ["hit_metal/hit_metal_1.ogg", "hit_wood/hit_wood_1.ogg"],
            "build_weapon_sounds": [f"m4_fire/m4_fire_{i}.ogg" for i in range(1, 4)] + ["ak_fire/ak_fire_1.ogg", "dna_pickup/dna_pickup_1.ogg", "dna_pickup/dna_pickup_2.ogg"],
            "build_destruction_sounds": [f"break_lamp/break_lamp_{i}.ogg" for i in (1, 2)],
        }
        data = {"version": 1, "protected_events": ["extinguisher_burst", "key_pickup", "minigun_spin"],
                "retired_events": ["scream_zombie", "roar_heavy"], "generators": {}}
        for owner, outputs in self.outputs.items():
            data["generators"][owner] = {}
            for relative in outputs:
                path = self.root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                content = b"old " + relative.encode()
                path.write_bytes(content)
                data["generators"][owner][relative] = sha(content)
        self.manifest.write_text(json.dumps(data))
        self.protected = ["extinguisher_burst/extinguisher_burst_1.ogg", "key_pickup/key_pickup_1.ogg", "minigun_spin/minigun_spin_1.ogg", "custom/owner.ogg", "hit_metal/custom.ogg", "key_pickup/key_pickup_1.ogg.import"]
        for relative in self.protected:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"authored " + relative.encode())
        self.before = self.snapshot()

    def snapshot(self):
        return {p.relative_to(self.directory).as_posix(): p.read_bytes() for p in self.directory.rglob("*") if p.is_file()}

    def plan(self, owner="build_sounds", only=None):
        return safety.AudioBuild(self.root, owner, only, self.manifest)

    def stage(self, plan):
        stage = self.directory / "stage"
        for relative in plan.outputs:
            encode(None, stage / relative)
        return stage

    def assert_protected(self):
        for relative in self.protected:
            self.assertEqual((self.root / relative).read_bytes(), self.before["audio/sfx/" + relative])
        self.assertTrue(self.credits.read_bytes().startswith(self.original_credits))
        for event in ("scream_zombie", "roar_heavy"):
            self.assertFalse((self.root / event).exists())

    def test_base_full_entrypoint_preserves_foreign_audio_and_credits(self):
        events = {event: [base.Sound(np.zeros(20), ["synthesised"])] for event in ("hit_metal", "hit_wood", "key_pickup", "extinguisher_burst", "scream_zombie", "roar_heavy")}
        with (
            patch.object(base, "OUT", self.root),
            patch.object(base, "MANIFEST", self.manifest),
            patch.object(base, "recipes", return_value=events),
            patch.object(base, "encode", side_effect=encode),
            patch.object(base, "credit_rows", return_value=[]),
            patch.object(sys, "argv", ["build_sounds.py", str(self.directory)]),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(base.main(), 0)
        self.assert_protected()
        self.assertTrue((self.root / self.outputs["build_sounds"][0]).read_bytes().startswith(b"generated"))
        self.plan()  # New output hashes are persisted, so the next run is valid.

    def test_weapon_full_entrypoint_never_calls_retired_synthesis(self):
        with (
            patch.object(weapons, "SFX", self.root),
            patch.object(weapons, "MANIFEST", self.manifest),
            patch.object(weapons, "variants_of", return_value=[np.zeros(20)]),
            patch.object(weapons, "EVENTS", {"m4_fire": (None, lambda: np.zeros(20))}),
            patch.object(weapons, "dna_pickup", return_value=np.zeros(20)),
            patch.object(weapons, "minigun_spin_loop", side_effect=AssertionError("authored spin overwritten")),
            patch.object(weapons, "key_pickup", side_effect=AssertionError("authored key overwritten")),
            patch.object(weapons, "write_ogg", side_effect=lambda p, x: encode(x, p)),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(weapons.main([]), 0)
        self.assert_protected()
        self.plan("build_weapon_sounds")

    def test_destruction_entrypoint_uses_manifest(self):
        def build(event, variant, root):
            encode(None, root / event / f"{event}_{variant + 1}.ogg")
        with (
            patch.object(destruction, "ROOT", self.root),
            patch.object(destruction, "MANIFEST", self.manifest),
            patch.object(destruction, "build", side_effect=build),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(destruction.main([]), 0)
        self.assert_protected()
        self.plan("build_destruction_sounds")

    def test_all_dry_runs_do_not_decode_or_write(self):
        with (
            patch.object(base, "OUT", self.root),
            patch.object(base, "MANIFEST", self.manifest),
            patch.object(base, "recipes", side_effect=AssertionError("decoded")),
            patch.object(sys, "argv", ["build_sounds.py", "--dry-run"]),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(base.main(), 0)
        with (
            patch.object(weapons, "SFX", self.root),
            patch.object(weapons, "MANIFEST", self.manifest),
            patch.object(weapons, "variants_of", side_effect=AssertionError("decoded")),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(weapons.main(["--dry-run"]), 0)
        with (
            patch.object(destruction, "ROOT", self.root),
            patch.object(destruction, "MANIFEST", self.manifest),
            patch.object(destruction, "build", side_effect=AssertionError("decoded")),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(destruction.main(["--dry-run"]), 0)
        self.assertEqual(self.snapshot(), self.before)

    def test_explicit_protected_retired_unknown_or_empty_selection_fails(self):
        for event in ("key_pickup", "minigun_spin", "extinguisher_burst", "scream_zombie", "roar_heavy", "unknown", ""):
            with self.subTest(event=event), self.assertRaises(ValueError):
                self.plan(only={event})
        self.assertEqual(self.snapshot(), self.before)

    def test_manual_edit_aborts_before_encoding(self):
        path = self.root / self.outputs["build_sounds"][0]
        path.write_bytes(b"new owner recording")
        before = self.snapshot()
        with (
            patch.object(base, "OUT", self.root),
            patch.object(base, "MANIFEST", self.manifest),
            patch.object(base, "recipes", side_effect=AssertionError("decoded")),
            patch.object(sys, "argv", ["build_sounds.py", "sources"]),
            self.assertRaises(ValueError),
        ):
            base.main()
        self.assertEqual(self.snapshot(), before)

    def test_failed_encoder_leaves_project_unchanged(self):
        events = {event: [base.Sound(np.zeros(20), ["synthesised"])] for event in ("hit_metal", "hit_wood")}
        def fail(sound, path):
            encode(sound, path)
            raise RuntimeError("encoder failed")
        with (
            patch.object(base, "OUT", self.root),
            patch.object(base, "MANIFEST", self.manifest),
            patch.object(base, "recipes", return_value=events),
            patch.object(base, "encode", side_effect=fail),
            patch.object(sys, "argv", ["build_sounds.py", "sources"]),
            contextlib.redirect_stdout(io.StringIO()),
            self.assertRaises(RuntimeError),
        ):
            base.main()
        self.assertEqual(self.snapshot(), self.before)

    def test_only_updates_selected_audio_and_credit_section(self):
        for event in ("hit_metal", "hit_wood", "hit_metal"):
            plan = self.plan(only={event})
            stage = self.stage(plan)
            other = self.root / ("hit_wood/hit_wood_1.ogg" if event == "hit_metal" else "hit_metal/hit_metal_1.ogg")
            before = other.read_bytes()
            text = self.credits.read_bytes()
            plan.publish(stage, {event: "updated " + event})
            self.assertEqual(other.read_bytes(), before)
            if event == "hit_metal" and b"updated hit_wood" in text:
                self.assertIn(b"updated hit_wood", self.credits.read_bytes())
            shutil.rmtree(stage)
        self.assertEqual(self.credits.read_text().count("<!-- BEGIN GENERATED AUDIO build_sounds:hit_metal -->"), 1)
        self.assert_protected()

    def test_extra_or_missing_recipe_output_is_refused(self):
        for extra in (False, True):
            plan = self.plan()
            stage = self.stage(plan)
            if extra:
                encode(None, stage / "scream_zombie/scream_zombie_1.ogg")
            else:
                (stage / plan.outputs[0]).unlink()
            before = {p: data for p, data in self.snapshot().items() if not p.startswith("stage/")}
            with self.assertRaises(ValueError):
                plan.publish(stage, {event: event for event in plan.events})
            self.assertEqual({p: data for p, data in self.snapshot().items() if not p.startswith("stage/")}, before)
            shutil.rmtree(stage)

    def test_edit_during_encoding_is_preserved(self):
        plan = self.plan()
        stage = self.stage(plan)
        path = self.root / plan.outputs[0]
        path.write_bytes(b"edited while encoding")
        before = self.snapshot()
        with self.assertRaises(ValueError):
            plan.publish(stage, {event: event for event in plan.events})
        self.assertEqual(self.snapshot(), before)

    def test_new_import_receipt_blocks_previously_generated_event(self):
        receipt = self.root.parent / "audio_refresh_processing.json"
        receipt.write_text(json.dumps({"records": [{"output": "assets/audio/sfx/hit_metal/hit_metal_1.ogg"}]}))
        with self.assertRaises(ValueError):
            self.plan()

    def test_manifest_path_hash_and_owner_conflicts_fail_closed(self):
        original = json.loads(self.manifest.read_text())
        for relative, value in (("../outside.ogg", "0" * 64), ("hit_metal/hit_metal_0.ogg", "0" * 64), ("key_pickup/key_pickup_1.ogg", "0" * 64), ("valid/valid_1.ogg", "invalid")):
            data = json.loads(json.dumps(original))
            data["generators"]["build_sounds"][relative] = value
            self.manifest.write_text(json.dumps(data))
            with self.subTest(path=relative), self.assertRaises(ValueError):
                self.plan()
        original["generators"]["build_weapon_sounds"]["hit_metal/hit_metal_1.ogg"] = "0" * 64
        self.manifest.write_text(json.dumps(original))
        with self.assertRaises(ValueError):
            self.plan()

    def test_missing_owned_file_can_be_restored(self):
        path = self.root / self.outputs["build_sounds"][0]
        path.unlink()
        plan = self.plan()
        plan.publish(self.stage(plan), {event: event for event in plan.events})
        self.assertTrue(path.is_file())
        self.assert_protected()

    def test_symlink_destination_fails_closed(self):
        path = self.root / self.outputs["build_sounds"][0]
        path.unlink()
        outside = self.directory / "owner.ogg"
        outside.write_bytes(b"owner")
        path.symlink_to(outside)
        with self.assertRaises(ValueError):
            self.plan()
        self.assertEqual(outside.read_bytes(), b"owner")

    def test_malformed_credits_leave_audio_unchanged(self):
        plan = self.plan()
        stage = self.stage(plan)
        self.credits.write_text("<!-- BEGIN GENERATED AUDIO build_sounds:hit_metal -->")
        before = self.snapshot()
        with self.assertRaises(ValueError):
            plan.publish(stage, {event: event for event in plan.events})
        self.assertEqual(self.snapshot(), before)

    def test_failed_commit_rolls_back_modified_files(self):
        plan = self.plan()
        stage = self.stage(plan)
        before = self.snapshot()
        original = safety._replace
        def fail_once(path, content):
            if path == self.credits:
                raise OSError("simulated disk error")
            original(path, content)
        with patch.object(safety, "_replace", side_effect=fail_once), self.assertRaises(OSError):
            plan.publish(stage, {event: event for event in plan.events})
        self.assertEqual(self.snapshot(), before)

    def test_historical_import_requires_opt_in_and_refuses_current_receipt(self):
        project = self.directory / "historical_project"
        with (
            patch.object(historical, "ROOT", project),
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            historical.main([])
        receipt = project / "assets/audio/audio_refresh_processing.json"
        receipt.parent.mkdir(parents=True)
        receipt.write_text("{}")
        before = self.snapshot()
        with (
            patch.object(historical, "ROOT", project),
            patch.object(historical, "convert", side_effect=AssertionError("converted")),
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            historical.main(["--historical-import"])
        self.assertEqual(self.snapshot(), before)

    def test_repository_manifest_matches_current_generated_audio(self):
        project_root = Path(__file__).resolve().parents[1]
        for owner in ("build_sounds", "build_weapon_sounds", "build_destruction_sounds"):
            plan = safety.AudioBuild(project_root / "assets/audio/sfx", owner)
            self.assertTrue(plan.outputs)


if __name__ == "__main__":
    unittest.main()
