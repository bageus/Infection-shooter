#!/usr/bin/env python3
"""Regression cases for CI registration drift, using small temporary repositories."""
import json
from pathlib import Path
import tempfile
import unittest

from validate_ci_suites import MANIFEST, SPECIAL, WORKFLOW, validate


class CoverageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.a = "game/features/example/tests/run_a_tests.gd"
        self.b = "game/features/example/tests/run_b_tests.gd"
        for path in [self.a, self.b]:
            self.write(path, "extends SceneTree\n")
        self.write(MANIFEST, self.a + "\n")
        self.write(SPECIAL, json.dumps({self.b: {
            "workflow": WORKFLOW, "job": "native", "mode": "native", "reason": "Needs pixels"}}))
        self.workflow = (
            "on:\n  pull_request:\njobs:\n  runtime:\n    steps:\n      - run: |\n"
            f"          tools/run_runtime_suites.sh {MANIFEST} /tmp/suites 3\n"
            "  native:\n    steps:\n      - run: |\n"
            f"          timeout 120 godot --script res://{self.b}\n")
        self.write(WORKFLOW, self.workflow)

    def write(self, path, text):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text)

    def errors(self):
        return validate(self.root)[0]

    def test_valid_manifest_and_direct_special_job(self):
        self.assertEqual(self.errors(), [])

    def test_new_suite_requires_registration(self):
        self.write("game/features/other/tests/run_new_tests.gd", "extends SceneTree")
        self.assertTrue(any("Unregistered" in error for error in self.errors()))

    def test_deleted_suite_and_duplicate_entry_are_rejected(self):
        self.write(MANIFEST, self.a + "\n" + self.a + "\ngame/tests/run_deleted.gd\n")
        errors = self.errors()
        self.assertTrue(any("Duplicate" in error for error in errors))
        self.assertTrue(any("Stale" in error for error in errors))

    def test_equal_basenames_cannot_share_runner_logs_or_user_data(self):
        path = "game/features/other/tests/run_a_tests.gd"
        self.write(path, "extends SceneTree")
        self.write(MANIFEST, self.a + "\n" + path + "\n")
        self.assertTrue(any("collision" in error for error in self.errors()))

    def test_comment_or_trigger_does_not_replace_runtime_command(self):
        for replacement in [f"# tools/run_runtime_suites.sh {MANIFEST} /tmp/suites 3", "echo skipped"]:
            self.write(WORKFLOW, self.workflow.replace(
                f"tools/run_runtime_suites.sh {MANIFEST} /tmp/suites 3", replacement)
                + f"\n# {MANIFEST}\n")
            self.assertTrue(any("canonical manifest" in error for error in self.errors()))

    def test_special_comment_echo_filter_and_other_job_do_not_count(self):
        for replacement in [f"# timeout 120 godot --script res://{self.b}",
                            f"echo --script {self.b}", "echo skipped"]:
            self.write(WORKFLOW, self.workflow.replace(
                f"timeout 120 godot --script res://{self.b}", replacement).replace(
                    "  pull_request:", f"  pull_request:\n    paths: [{self.b}]")
                + f"\n# {self.b}\n  other:\n    steps:\n      - run: godot --script {self.b}\n")
            self.assertTrue(any("does not execute suite" in error for error in self.errors()))

    def test_nested_renderer_loop_is_supported(self):
        command = ("for renderer in gl_compatibility forward_plus; do\n"
                   f"          for suite in {self.b}; do\n"
                   '            timeout 300 xvfb-run -a godot --script "$suite"\n'
                   "          done\n          done")
        self.write(WORKFLOW, self.workflow.replace(f"timeout 120 godot --script res://{self.b}", command))
        self.assertEqual(self.errors(), [])

    def test_loop_with_no_script_execution_is_rejected(self):
        command = f'for suite in {self.b}; do\n            echo "$suite"\n          done'
        self.write(WORKFLOW, self.workflow.replace(f"timeout 120 godot --script res://{self.b}", command))
        self.assertTrue(any("does not execute suite" in error for error in self.errors()))

    def test_special_mode_reason_and_workflow_are_required(self):
        valid = json.loads((self.root / SPECIAL).read_text())
        for key, value in [("reason", ""), ("mode", "skip"), ("job", "missing"),
                           ("workflow", "../outside.yml")]:
            data = json.loads(json.dumps(valid))
            data[self.b][key] = value
            self.write(SPECIAL, json.dumps(data))
            self.assertTrue(self.errors(), key)

    def test_special_cannot_overlap_headless_list(self):
        self.write(MANIFEST, self.a + "\n" + self.b + "\n")
        self.assertTrue(any("both lists" in error for error in self.errors()))

    def test_support_and_profile_files_are_not_run_suites(self):
        self.write("game/features/example/tests/profile_blood.gd", "extends SceneTree")
        self.write("game/features/example/tests/helper.gd", "extends RefCounted")
        self.assertEqual(self.errors(), [])


if __name__ == "__main__":
    unittest.main()
