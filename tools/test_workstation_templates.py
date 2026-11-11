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

    def test_reception_two_heights_has_its_own_template_profile(self):
        key = DESK_CATALOG.get("07_reception_counter_two_heights_2")
        self.assertIsNotNone(key, "The installed reception must expose template editing")
        self.assertNotEqual(key, DESK_CATALOG["07_reception_counter_two_heights"])
        profile = json.loads((DATA / "desks" / f"{key}.json").read_text())
        self.assertEqual([station["grid_height"] for station in profile["stations"]], [0.78, 1.1])

    def test_single_height_reception_grid_matches_its_countertop(self):
        # Measured from the intact mesh of 07_reception_counter_two_heights: the flat top is at
        # y=0.82, x ±0.99, z -0.33..0.51. The grid must sit on it, not sink below or overhang it.
        key = DESK_CATALOG.get("07_reception_counter_two_heights")
        profile = json.loads((DATA / "desks" / f"{key}.json").read_text())
        self.assertAlmostEqual(profile["height"], 0.82)
        station = profile["stations"][0]
        self.assertLessEqual(station["grid_width"], 1.98 + 0.001)
        self.assertLessEqual(station["grid_depth"], 0.84 + 0.001)
        self.assertAlmostEqual(station["z"] - station["grid_depth"] / 2, -0.33 + 0.005, delta=0.01)
        self.assertAlmostEqual(station["z"] + station["grid_depth"] / 2, 0.51 - 0.005, delta=0.01)

    def test_every_named_model_exists(self):
        names = set(re.findall(r'"(\d\d_[A-Za-z0-9_]+)"', SCRIPT))
        for folder in (DATA / "desks", DATA / "setups"):
            for path in folder.glob("*.json"):
                names.update(re.findall(r'"(\d\d_[A-Za-z0-9_]+)"', path.read_text()))
        self.assertGreater(len(names), 25)
        for name in names:
            self.assertTrue(any((MODELS / name[:2]).rglob(f"{name}.glb")), name)


if __name__ == "__main__":
    unittest.main()
