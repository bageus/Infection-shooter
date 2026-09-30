"""Check workstation authoring data against the actual model package."""

import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "game/bootstrap/app/workstations"
MODELS = ROOT / "models/objects/enviroments"
SCRIPT = (ROOT / "game/bootstrap/app/workstation_templates.gd").read_text()
DESK_CATALOG = dict(re.findall(
    r'"(\d\d_[A-Za-z0-9_]+)": "([a-z0-9_]+)"',
    SCRIPT.split("const DESKS := {", 1)[1].split("\n}", 1)[0],
))


class WorkstationTemplatesTest(unittest.TestCase):
    def test_all_desks_and_computer_setups_are_authored(self):
        desks = list((DATA / "desks").glob("*.json"))
        setups = list((DATA / "setups").glob("*.json"))
        self.assertEqual({path.stem for path in desks}, set(DESK_CATALOG.values()))
        self.assertEqual(len(setups), 5)
        for path in desks:
            with self.subTest(profile=path.stem):
                profile = json.loads(path.read_text())
                self.assertGreater(profile["height"], 0)
                self.assertTrue(profile["stations"])
                for station in profile["stations"]:
                    for key in ("grid_width", "grid_depth"):
                        self.assertGreater(station[key], 0, key)
                    for key in ("usable_width", "usable_depth", "zone_width", "zone_depth"):
                        if key in station:
                            self.assertGreater(station[key], 0, key)
                    self.assertGreater(station.get("grid_height", profile["height"]), 0)

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
