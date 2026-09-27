"""Check that authored broken glass openings remain wide enough for the player."""

import json
from pathlib import Path
import struct
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCENES = ROOT / "game/presentation/office_floor/public/structural"
MODELS = ROOT / "models/objects/enviroments/01"
PAIRS = (
    ("glass_partition_half", "01_glass_partition_half_breakable"),
    ("glass_partition_blinds", "01_glass_partition_blinds_breakable"),
    ("glass_wall_full", "01_glass_wall_full_breakable"),
)


class GlassOpeningTest(unittest.TestCase):
    def test_frames_keep_walkable_openings_when_glass_breaks(self):
        for scene_name, model_name in PAIRS:
            scene = (SCENES / f"{scene_name}.tscn").read_text()
            self.assertIn("preserve_open_frame = true", scene)
            self.assertIn(f"{model_name}.glb", scene)
            data = (MODELS / f"{model_name}.glb").read_bytes()
            json_size = struct.unpack_from("<I", data, 12)[0]
            gltf = json.loads(data[20 : 20 + json_size])
            parents = {
                child: index
                for index, node in enumerate(gltf["nodes"])
                for child in node.get("children", [])
            }
            glass_index = next(
                index for index, node in enumerate(gltf["nodes"])
                if "mesh" in node and node.get("name", "").lower().startswith("glass")
                and not node["name"].startswith("GlassShard")
            )
            glass = gltf["nodes"][glass_index]
            world = gltf["nodes"][parents[glass_index]]
            accessor = gltf["accessors"][gltf["meshes"][glass["mesh"]]["primitives"][0]["attributes"]["POSITION"]]
            width = (
                (accessor["max"][0] - accessor["min"][0])
                * glass.get("scale", [1, 1, 1])[0]
                * world.get("scale", [1, 1, 1])[0]
            )
            # The player capsule diameter is 0.9 m; leave clearance for movement.
            self.assertGreater(width, 1.05, model_name)


if __name__ == "__main__":
    unittest.main()
