#!/usr/bin/env python3
"""Architecture regressions for injected mission collaborators."""
import unittest
from pathlib import Path
from validate_architecture import validate_mission_scene_access


class MissionAccessTests(unittest.TestCase):
    def check_source(self, code, layer="features", path="game/features/combat/example.gd"):
        errors = []
        validate_mission_scene_access(Path(path), code, layer, {"bootstrap", "infrastructure"}, errors)
        return errors

    def test_production_lookups_and_aliases_are_rejected(self):
        for code in ("get_tree().current_scene.add_child(effect)", "var tree = get_tree()\nvar world = tree.current_scene"):
            self.assertTrue(self.check_source(code))
            self.assertTrue(self.check_source(code, layer="presentation"))

    def test_composition_and_test_harness_are_allowed(self):
        self.assertFalse(self.check_source("current_scene = stage", layer="bootstrap"))
        self.assertFalse(self.check_source("current_scene = stage", path="game/features/combat/tests/test.gd"))

    def test_authored_text_and_comments_are_not_dependencies(self):
        self.assertFalse(self.check_source('var label = "current_scene" # current_scene\nvar shader = """current_scene"""'))
        self.assertFalse(self.check_source("var value = 'current_scene'\nvar effects: Node3D"))


if __name__ == "__main__":
    unittest.main()
