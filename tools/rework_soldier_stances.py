#!/usr/bin/env python3
"""One-shot rework of the player's weapon stances in soldier_animated.glb.

Applied once to the GLB as of commit ae4688b; running it again on the reworked
file would apply the changes twice. Needs numpy and scipy.

    python3 tools/rework_soldier_stances.py <source.glb> <output.glb>

1. Right fingers curl into a grip in every clip (the authored clips kept the
   relaxed rest hand, so long arm turns showed a flat, splayed palm).
2. Shotgun/launcher clips: the right arm bones lose their authored 26% stretch,
   the clavicle keeps 35% of its shrug, and a two-bone IK lowers the elbow from
   shoulder height. Both wrists keep their orientation; the weapon is tucked
   back along the body axis only as far as the unstretched arm needs. Half of
   the extreme wrist twist moves into the forearm.
3. Skin weights: the torso below the armpits (the vest flanks and back panel)
   no longer follows the arm or clavicle; the edited band is smoothed so the
   vest does not tear or turn into a spike when the shoulder turns.
"""

from __future__ import annotations

import json
import struct
import sys

import numpy as np
from scipy.sparse import coo_matrix, diags
from scipy.spatial.transform import Rotation as R

COMPONENTS = {5126: np.float32, 5123: np.uint16, 5121: np.uint8, 5125: np.uint32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

CLAVICLE_KEPT = 0.35
ELBOW_DROP = 3.0
WRIST_TWIST_TO_FOREARM = 0.5
REACH = 0.88
# The auto-rig names are mirrored: 'Index' bones sit on the little-finger edge
# and 'Pinky' bones next to the thumb, so 'Pinky' is the trigger finger.
CURL = {
    "Index1": 80, "Index2": 85, "Middle1": 76, "Middle2": 88, "Ring1": 72,
    "Ring2": 85, "Pinky1": 30, "Pinky2": 25, "Thumb1": 30, "Thumb2": 35,
}
PALM = np.array([0.0, -1.0, 0.0])
THUMB_WRAP = np.array([0.0, -0.4, -1.0])
# Torso volume released from the arms (bind space, metres): full release inside
# |x| < 0.20 below y 0.36, none past |x| 0.29 or above y 0.46; below the armpit
# the release reaches the vest's side flaps.
TORSO = (0.20, 0.29, 0.36, 0.46)
CLAVICLE_RELEASE = 0.5
SMOOTHING_PASSES = 6


class Glb:
    def __init__(self, path: str) -> None:
        data = open(path, "rb").read()
        length = struct.unpack("<I", data[12:16])[0]
        self.json = json.loads(data[20:20 + length])
        offset = 20 + length
        self.bin = bytearray(data[offset + 8:offset + 8 + struct.unpack("<I", data[offset:offset + 4])[0]])

    def read(self, index: int) -> np.ndarray:
        accessor = self.json["accessors"][index]
        view = self.json["bufferViews"][accessor["bufferView"]]
        dtype = COMPONENTS[accessor["componentType"]]
        width = WIDTH[accessor["type"]]
        assert view.get("byteStride", 0) in (0, width * np.dtype(dtype).itemsize)
        offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        return np.frombuffer(bytes(self.bin), dtype, accessor["count"] * width, offset).reshape(-1, width).copy()

    def write(self, index: int, values: np.ndarray) -> None:
        accessor = self.json["accessors"][index]
        view = self.json["bufferViews"][accessor["bufferView"]]
        offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        raw = np.ascontiguousarray(values.astype(COMPONENTS[accessor["componentType"]])).tobytes()
        self.bin[offset:offset + len(raw)] = raw

    def append(self, values: np.ndarray, template: int) -> int:
        """Adds a float accessor shaped like template; animation outputs are shared between clips."""
        while len(self.bin) % 4:
            self.bin.append(0)
        raw = np.ascontiguousarray(values.astype(np.float32)).tobytes()
        self.json["bufferViews"].append({"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(raw)})
        self.bin += raw
        accessor = dict(self.json["accessors"][template])
        accessor.pop("byteOffset", None)
        accessor.update(bufferView=len(self.json["bufferViews"]) - 1, count=len(values))
        if "min" in accessor:
            accessor.update(min=values.min(0).tolist(), max=values.max(0).tolist())
        self.json["accessors"].append(accessor)
        self.json["buffers"][0]["byteLength"] = len(self.bin)
        return len(self.json["accessors"]) - 1

    def save(self, path: str) -> None:
        text = json.dumps(self.json, separators=(",", ":")).encode()
        text += b" " * (-len(text) % 4)
        body = bytes(self.bin) + b"\0" * (-len(self.bin) % 4)
        header = struct.pack("<4sII", b"glTF", 2, 28 + len(text) + len(body))
        with open(path, "wb") as out:
            out.write(header + struct.pack("<I4s", len(text), b"JSON") + text)
            out.write(struct.pack("<I4s", len(body), b"BIN\0") + body)


class Rig:
    def __init__(self, glb: Glb) -> None:
        self.nodes = glb.json["nodes"]
        self.id = {node["name"]: index for index, node in enumerate(self.nodes)}
        self.parent = {child: index for index, node in enumerate(self.nodes) for child in node.get("children", [])}

    def rest(self, node: int) -> tuple[np.ndarray, np.ndarray]:
        data = self.nodes[node]
        return np.array(data.get("translation", [0, 0, 0]), float), np.array(data.get("rotation", [0, 0, 0, 1]), float)

    def world(self, node: int, pose: dict) -> np.ndarray:
        result = np.eye(4)
        while node is not None:
            translation, rotation = self.rest(node)
            local = np.eye(4)
            local[:3, :3] = R.from_quat(pose.get(node, {}).get("rotation", rotation)).as_matrix()
            local[:3, 3] = pose.get(node, {}).get("translation", translation)
            result = local @ result
            node = self.parent.get(node)
        return result


def basis(matrix: np.ndarray) -> R:
    return R.from_matrix(matrix[:3, :3])


def swing(start: R, local_axis: np.ndarray, target: np.ndarray) -> R:
    axis = start.apply(local_axis)
    axis /= np.linalg.norm(axis)
    target = target / np.linalg.norm(target)
    normal = np.cross(axis, target)
    sine = np.linalg.norm(normal)
    return start if sine < 1e-9 else R.from_rotvec(normal / sine * np.arctan2(sine, axis.dot(target))) * start


class StanceEditor:
    def __init__(self, glb: Glb) -> None:
        self.glb = glb
        self.rig = Rig(glb)

    def sampler(self, clip: dict, node: int, path: str) -> dict:
        for channel in clip["channels"]:
            if channel["target"]["node"] == node and channel["target"]["path"] == path:
                return clip["samplers"][channel["sampler"]]
        raise KeyError((clip["name"], node, path))

    def get(self, clip: dict, node: int, path: str = "rotation") -> np.ndarray:
        values = self.glb.read(self.sampler(clip, node, path)["output"])
        assert np.abs(values - values[0]).max() < 1e-5, "upper-body stance tracks are constant"
        return values[0].astype(float)

    def put(self, clip: dict, node: int, value: np.ndarray, path: str = "rotation") -> None:
        sampler = self.sampler(clip, node, path)
        count = self.glb.json["accessors"][sampler["output"]]["count"]
        sampler["output"] = self.glb.append(np.tile(value, (count, 1)), sampler["output"])

    def pose(self, clip: dict) -> dict:
        pose: dict = {}
        for channel in clip["channels"]:
            values = self.glb.read(clip["samplers"][channel["sampler"]]["output"])
            pose.setdefault(channel["target"]["node"], {})[channel["target"]["path"]] = values[0].astype(float)
        return pose

    def curl_deltas(self) -> dict[int, R]:
        deltas = {}
        for finger, degrees in CURL.items():
            node = self.rig.id["Right" + finger]
            world = basis(self.rig.world(node, {}))
            child = self.rig.nodes[node]["children"][0]
            direction = world.apply(np.array(self.rig.nodes[child]["translation"], float))
            axis = np.cross(direction, THUMB_WRAP if finger.startswith("Thumb") else PALM)
            axis /= np.linalg.norm(axis)
            deltas[node] = world.inv() * R.from_rotvec(axis * np.radians(degrees)) * world
        return deltas

    def solve_arm(self, pose: dict, side: str, wrist: np.ndarray, drop: float, twist: float, lengths: list) -> dict:
        """Two-bone IK that keeps the wrist world transform; returns local rotations."""
        ids = [self.rig.id[side + part] for part in ("Shoulder", "Arm", "ForeArm", "Wrist")]
        shoulder, arm, forearm, wrist_node = ids
        old_arm = self.rig.world(arm, pose)
        old_elbow = self.rig.world(forearm, pose)[:3, 3]
        for node, translation in zip((forearm, wrist_node), lengths):
            pose[node]["translation"] = translation
        shoulder_world = self.rig.world(shoulder, pose)
        joint = self.rig.world(arm, pose)[:3, 3]
        upper, lower = (np.linalg.norm(t) for t in lengths)
        target = wrist[:3, 3]
        distance = np.linalg.norm(target - joint)
        assert distance < upper + lower
        reach = (target - joint) / distance
        along = (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
        pole = old_elbow - joint
        pole -= reach * pole.dot(reach)
        down = PALM - reach * PALM.dot(reach)
        pole = pole / np.linalg.norm(pole) + drop * down / np.linalg.norm(down)
        elbow = joint + reach * along + pole / np.linalg.norm(pole) * np.sqrt(upper * upper - along * along)
        arm_world = swing(basis(old_arm), lengths[0], elbow - joint)
        kept = basis(wrist) * R.from_quat(pose[wrist_node]["rotation"]).inv()
        relaxed = basis(wrist) * R.from_quat(self.rig.rest(wrist_node)[1]).inv()
        forearm_start = kept * R.from_rotvec((kept.inv() * relaxed).as_rotvec() * twist)
        forearm_world = swing(forearm_start, lengths[1], target - elbow)
        return {
            arm: basis(shoulder_world).inv() * arm_world,
            forearm: arm_world.inv() * forearm_world,
            wrist_node: forearm_world.inv() * basis(wrist),
        }

    def rework_long_gun(self, clip: dict, relaxed_shoulder: R) -> None:
        rig = self.rig
        pose = self.pose(clip)
        right_wrist = rig.world(rig.id["RightWrist"], pose)
        left_wrist = rig.world(rig.id["LeftWrist"], pose)
        authored = R.from_quat(self.get(clip, rig.id["RightShoulder"]))
        shoulder = relaxed_shoulder * R.from_rotvec((relaxed_shoulder.inv() * authored).as_rotvec() * CLAVICLE_KEPT)
        pose[rig.id["RightShoulder"]]["rotation"] = shoulder.as_quat()
        rest_lengths = [rig.rest(rig.id["RightForeArm"])[0], rig.rest(rig.id["RightWrist"])[0]]
        joint = rig.world(rig.id["RightArm"], pose)[:3, 3]
        reach = REACH * sum(np.linalg.norm(t) for t in rest_lengths)
        low, high = 0.0, 0.3
        for _ in range(50):
            middle = (low + high) / 2.0
            if np.linalg.norm(right_wrist[:3, 3] - [0.0, 0.0, middle] - joint) > reach:
                low = middle
            else:
                high = middle
        tuck = np.eye(4)
        tuck[2, 3] = -high
        left_lengths = [pose[rig.id["LeftForeArm"]]["translation"], pose[rig.id["LeftWrist"]]["translation"]]
        left_pose = {node: dict(tracks) for node, tracks in pose.items()}
        rotations = self.solve_arm(left_pose, "Left", tuck @ left_wrist, 0.0, 0.0, left_lengths)
        rotations.update(self.solve_arm(pose, "Right", tuck @ right_wrist, ELBOW_DROP, WRIST_TWIST_TO_FOREARM, rest_lengths))
        rotations[rig.id["RightShoulder"]] = shoulder
        for node, rotation in rotations.items():
            self.put(clip, node, rotation.as_quat())
        for node, translation in zip((rig.id["RightForeArm"], rig.id["RightWrist"]), rest_lengths):
            self.put(clip, node, translation, "translation")
        print(f"{clip['name']}: weapon tucked {high:.3f} m")

    def run(self) -> None:
        clips = self.glb.json["animations"]
        pistol = next(clip for clip in clips if clip["name"] == "Idle_Pistol_TwoHand_Loop")
        relaxed_shoulder = R.from_quat(self.get(pistol, self.rig.id["RightShoulder"]))
        deltas = self.curl_deltas()
        for clip in clips:
            for node, delta in deltas.items():
                self.put(clip, node, (R.from_quat(self.get(clip, node)) * delta).as_quat())
            if "Shotgun" in clip["name"] or "Launcher" in clip["name"]:
                self.rework_long_gun(clip, relaxed_shoulder)


def smoothstep(x: np.ndarray, edge0: float, edge1: float) -> np.ndarray:
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def release_torso(glb: Glb) -> None:
    primitive = glb.json["meshes"][0]["primitives"][0]
    attributes = primitive["attributes"]
    names = [glb.json["nodes"][i]["name"] for i in glb.json["skins"][0]["joints"]]
    positions = glb.read(attributes["POSITION"])
    joints = glb.read(attributes["JOINTS_0"]).astype(int)
    count = len(positions)
    weights = np.zeros((count, len(names)))
    np.add.at(weights, (np.repeat(np.arange(count), 4), joints.ravel()), glb.read(attributes["WEIGHTS_0"]).ravel())
    width, height = np.abs(positions[:, 0]), positions[:, 1]
    inner, outer, low, high = TORSO
    inside = np.maximum(
        smoothstep(width, outer, inner) * smoothstep(height, high, low),
        smoothstep(width, 0.37, 0.33) * smoothstep(height, 0.39, 0.33),
    )
    moved = np.zeros(count)
    for side in ("Right", "Left"):
        for bone, share in ((side + "Arm", 1.0), (side + "ForeArm", 1.0), (side + "Shoulder", CLAVICLE_RELEASE)):
            column = names.index(bone)
            delta = weights[:, column] * inside * share
            weights[:, column] -= delta
            moved += delta
    weights[:, names.index("Spine2")] += moved
    weights = smooth_band(glb, primitive, positions, weights, (inside > 0.01) & (inside < 0.99))
    top = np.argsort(-weights, 1)[:, :4]
    kept = np.maximum(np.take_along_axis(weights, top, 1), 0.0)
    kept /= kept.sum(1, keepdims=True)
    glb.write(attributes["JOINTS_0"], np.where(kept > 0, top, 0))
    glb.write(attributes["WEIGHTS_0"], kept)


def smooth_band(glb: Glb, primitive: dict, positions: np.ndarray, weights: np.ndarray, band: np.ndarray) -> np.ndarray:
    """Laplacian-smooths weights over the welded mesh around the release band."""
    _, welded = np.unique(np.round(positions, 5), axis=0, return_inverse=True)
    welded = welded.ravel()
    size = welded.max() + 1
    faces = glb.read(primitive["indices"]).reshape(-1, 3)
    edges = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
    a, b = welded[edges[:, 0]], welded[edges[:, 1]]
    adjacency = coo_matrix((np.ones(2 * len(edges)), (np.r_[a, b], np.r_[b, a])), shape=(size, size)).tocsr()
    adjacency.data[:] = 1.0
    adjacency = adjacency + diags(np.ones(size))
    average = diags(1.0 / np.asarray(adjacency.sum(1)).ravel()) @ adjacency
    zone = np.zeros(size)
    np.maximum.at(zone, welded, band.astype(float))
    for _ in range(3):
        zone = np.minimum(1.0, (average @ zone) * 3.0)
    shared = np.zeros((size, weights.shape[1]))
    np.add.at(shared, welded, weights)
    shared /= np.bincount(welded, minlength=size)[:, None]
    for _ in range(SMOOTHING_PASSES):
        shared += zone[:, None] * (average @ shared - shared) * 0.5
    return np.where(zone[welded][:, None] > 0, shared[welded], weights)


def main() -> None:
    glb = Glb(sys.argv[1])
    StanceEditor(glb).run()
    release_torso(glb)
    glb.save(sys.argv[2])


if __name__ == "__main__":
    main()
