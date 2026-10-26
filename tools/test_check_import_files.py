#!/usr/bin/env python3
"""Godot import gate rejects committed conflict markers before an editor starts."""
import contextlib
import io
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import check_import_files as checker


class ImportMetadataTests(unittest.TestCase):
    def check_metadata(self, text: str) -> tuple[int, str]:
        relative = "assets/icons/game_icon_32.png.import"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / relative
            path.parent.mkdir(parents=True)
            path.write_text(text)
            output = io.StringIO()
            with patch.object(checker, "ROOT", root), patch.object(
                checker.subprocess, "run", return_value=SimpleNamespace(stdout=relative + "\n")
            ), contextlib.redirect_stdout(output):
                result = checker.main()
        return result, output.getvalue()

    def test_uid_merge_conflict_is_rejected(self):
        code, report = self.check_metadata(
            '[remap]\n<<<<<<< HEAD\nuid="uid://old"\n=======\nuid="uid://new"\n>>>>>>> incoming\n'
        )
        self.assertEqual(code, 1)
        self.assertIn("Unresolved merge conflicts", report)
        self.assertIn("assets/icons/game_icon_32.png.import", report)

    def test_diff3_and_incomplete_conflicts_are_rejected(self):
        for marker in ["<<<<<<< HEAD", "||||||| base", "=======", ">>>>>>> incoming"]:
            with self.subTest(marker=marker):
                self.assertEqual(self.check_metadata("[remap]\n" + marker + "\n")[0], 1)

    def test_valid_metadata_remains_accepted(self):
        self.assertEqual(self.check_metadata('[remap]\nuid="uid://old"\n[params]\ndetect_3d/compress_to=0\n')[0], 0)

    def test_quoted_marker_text_is_not_a_conflict(self):
        self.assertEqual(self.check_metadata('[deps]\nsource_file="res://assets/<<<<<<<.png"\n')[0], 0)

    def test_failed_import_remains_rejected(self):
        self.assertEqual(self.check_metadata("[remap]\nvalid=false\n")[0], 1)

    def test_unsafe_recompression_remains_rejected(self):
        self.assertEqual(self.check_metadata("[params]\ndetect_3d/compress_to=1\n")[0], 1)


if __name__ == "__main__":
    unittest.main()
