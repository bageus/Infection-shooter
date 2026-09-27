"""Check workstation authoring data against the actual model package."""

import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "game/bootstrap/app/workstations"
MODELS = ROOT / "models/objects/enviroments"
SCRIPT = (ROOT / "game/bootstrap/app/workstation_templates.gd").read_text()


class WorkstationTemplatesTest(unittest.TestCase):
    def test_all_desks_and_computer_setups_are_authored(self):
        desks = list((DATA / "desks").glob("*.json"))
        setups = list((DATA / "setups").glob("*.json"))
        self.assertEqual(len(desks), 5)
        self.assertEqual(len(setups), 5)
        self.assertEqual(
            sorted(len(json.loads(path.read_text())["stations"]) for path in desks),
            [1, 1, 1, 1, 2],
        )
        for path in desks:
            profile = json.loads(path.read_text())
            self.assertGreater(profile["height"], 0.6)
            self.assertLess(profile["height"], 1.0)
            self.assertIn("chair", profile)
            self.assertIn("bin", profile)

    def test_each_setup_has_a_readable_computer_configuration(self):
        expected = {
            "laptop": ["laptop"],
            "laptop_monitor": ["monitor", "laptop"],
            "desktop": ["monitor", "tower", "05_keyboard"],
            "dual_laptop": ["monitor", "monitor", "laptop"],
            "dual_desktop": ["monitor", "monitor", "tower", "05_keyboard"],
        }
        for name, roles in expected.items():
            entries = json.loads((DATA / "setups" / f"{name}.json").read_text())["items"]
            self.assertEqual([entry["model"] for entry in entries], roles)

    def test_every_named_model_exists(self):
        names = set(re.findall(r'"(\d\d_[A-Za-z0-9_]+)"', SCRIPT))
        for folder in (DATA / "desks", DATA / "setups"):
            for path in folder.glob("*.json"):
                names.update(re.findall(r'"(\d\d_[A-Za-z0-9_]+)"', path.read_text()))
        self.assertGreater(len(names), 25)
        for name in names:
            self.assertTrue((MODELS / name[:2] / f"{name}.glb").is_file(), name)


if __name__ == "__main__":
    unittest.main()
