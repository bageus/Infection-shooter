"""Writes the loose-body-part decoration scenes of the six enemies and prints the palette entries.

    python3 tools/build_decor_parts.py

One scene per body part: head, torso, upper arm, forearm+hand, whole arm, thigh, shin+foot and
whole leg (left and right); the Horde has its body and eight tentacles. Corpses carry a
destruction level instead of a scene per wreck, see infected_corpse_decor.gd.
"""
import pathlib

DIR = pathlib.Path("game/features/infected/public/decor")
SCALES = {"hunger": 1.0, "revenant": 1.0, "brute": 1.1, "titan": 1.35, "colossus": 1.55, "horde": 2.21}
HUMANOID_PARTS = ["head", "torso"] + [f"{p}_{s}" for p in ["upperarm", "forearm", "arm", "thigh", "shin", "leg"] for s in "lr"]
HORDE_PARTS = ["torso"] + [f"tentacle_{i}" for i in range(8)]
TEMPLATE = """[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://game/features/infected/infected_body_part_decor.gd" id="1_script"]
[ext_resource type="PackedScene" path="res://models/objects/characters/enemy/game/{model}_rig.tscn" id="2_res"]

[node name="{node}" type="RigidBody3D"]
script = ExtResource("1_script")
visual_scene = ExtResource("2_res")
visual_scale = {scale}
part = &"{part}"
"""


def main() -> None:
    for old in list(DIR.glob("part_*_arm.tscn")) + list(DIR.glob("part_*_leg.tscn")) + [DIR / "part_horde_tentacle.tscn"]:
        if old.stem.split("_")[1] in SCALES and old.exists():
            old.unlink()
    for old in DIR.glob("corpse_*_mutilated.tscn"):
        if old.stem.split("_")[1] in SCALES:
            old.unlink()
    for enemy, scale in SCALES.items():
        for part in HORDE_PARTS if enemy == "horde" else HUMANOID_PARTS:
            node = "Part" + enemy.capitalize() + "".join(word.capitalize() for word in part.split("_"))
            (DIR / f"part_{enemy}_{part}.tscn").write_text(TEMPLATE.format(model=enemy.capitalize(), node=node, scale=scale, part=part))


if __name__ == "__main__":
    main()
