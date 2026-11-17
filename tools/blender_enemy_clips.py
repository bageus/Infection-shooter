# Enemy clips authored in Blender (Vadim, 17.11.2026) on the Mixamo rig, then retargeted by
# tools/build_hunger_clips.gd like the other Mixamo clips (EXTRA "Throw" and "Slam").
#   /opt/bpy/bin/python tools/blender_enemy_clips.py
# Writes into models/objects/characters/enemy/clips/:
#   Titan Throw.fbx    the Titan bends down, picks a rock off the floor with its throwing hand,
#                      straightens up, then throws like its AttackLeft (Zombie Attack, played whole).
#   Colossus Slam.fbx  both fists go up over the head, then down onto the floor in front, and it stands up.
# Each pose is keyed from a source frame (hips lowered and pitched, spine bent, head kept on the
# target), then IK puts the hands on their marks and keeps the feet planted, and it is all baked.
import bpy, os, math
from mathutils import Matrix, Vector

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models", "objects", "characters", "enemy")
P = "mixamorig:"
# Forward bend of each bone per unit of `bend` (degrees); negative bend leans back.
BEND = {"Hips": 24.0, "Spine": 18.0, "Spine1": 18.0, "Spine2": 14.0, "Neck": -12.0, "Head": -18.0}
# Blender world, metres, -Y is the Mixamo front.
ROCK = Vector((-0.12, -0.55, 0.16))
# above the head but in front of it: straight up, the shoulder hump of the Colossus stretches into the armpits
OVERHEAD = {"LeftHand": Vector((0.2, -0.3, 1.68)), "RightHand": Vector((-0.2, -0.3, 1.68))}
FLOOR = {"LeftHand": Vector((0.17, -0.62, 0.14)), "RightHand": Vector((-0.17, -0.62, 0.14))}

CLIPS = [
    # source, output, frames before the source pose, source frames kept after it (None: all),
    # body keys (frame, hips drop m, bend), hand keys {hand: [(frame, mark or None = own place, IK weight)]}
    {"source": "hunger_clips/Zombie Attack.fbx", "output": "Titan Throw.fbx", "lead": 38, "tail": None,
     "body": [(0, 0.0, 0.0), (16, 0.36, 1.0), (22, 0.36, 1.0), (38, 0.0, 0.0)],
     "hands": {"RightHand": [(0, None, 0.0), (12, ROCK, 1.0), (16, ROCK, 1.0), (22, ROCK, 1.0), (24, ROCK, 1.0), (36, None, 0.0)]}},
    {"source": "clips/Mutant Idle.fbx", "output": "Colossus Slam.fbx", "lead": 58, "tail": 0,
     "body": [(0, 0.0, 0.0), (16, -0.02, -0.6), (20, -0.02, -0.6), (27, 0.42, 1.25), (36, 0.42, 1.2), (58, 0.0, 0.0)],
     "hands": {h: [(0, None, 0.0), (14, OVERHEAD[h], 1.0), (20, OVERHEAD[h], 1.0), (27, FLOOR[h], 1.0), (36, FLOOR[h], 1.0), (54, None, 0.0)]
               for h in ("LeftHand", "RightHand")}},
]


def curves(act):
    if hasattr(act, "fcurves"):
        return list(act.fcurves)
    return [c for layer in act.layers for strip in layer.strips for bag in strip.channelbags for c in bag.fcurves]


def smooth(keys, t, index):
    for (t0, *a), (t1, *b) in zip(keys, keys[1:]):
        if t0 <= t <= t1:
            x = (t - t0) / (t1 - t0) if t1 > t0 else 1.0
            x = x * x * (3.0 - 2.0 * x)
            return a[index] + (b[index] - a[index]) * x
    return keys[-1][1 + index]


def author(clip):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT, clip["source"]))
    scene = bpy.context.scene
    scene.render.fps = 30
    arm = [o for o in scene.objects if o.type == 'ARMATURE'][0]
    pb = arm.pose.bones
    first, last = (int(x) for x in arm.animation_data.action.frame_range)
    lead = clip["lead"]
    for curve in curves(arm.animation_data.action):
        for key in curve.keyframe_points:
            key.co.x += lead
            key.handle_left.x += lead
            key.handle_right.x += lead
    source = first + lead # the source's first pose
    end = source + (last - first if clip["tail"] is None else clip["tail"])
    world = arm.matrix_world
    down = world.inverted().to_3x3() @ Vector((0, 0, -1))
    for f in range(first, source):
        scene.frame_set(source)
        drop, bend = smooth(clip["body"], f - first, 0), smooth(clip["body"], f - first, 1)
        for name, degrees in BEND.items():
            bone = pb[P + name]
            head = bone.matrix.translation.copy()
            # about the armature's left-right axis (X) at the bone's head; armature space is Y-up, +Z front
            turn = Matrix.Translation(head) @ Matrix.Rotation(math.radians(degrees * bend), 4, 'X') @ Matrix.Translation(-head)
            if name == "Hips":
                turn = Matrix.Translation(down * drop) @ turn
            bone.matrix = turn @ bone.matrix
            bpy.context.view_layer.update()
        for bone in pb:
            bone.keyframe_insert("location", frame=f)
            bone.keyframe_insert("rotation_quaternion", frame=f)

    scene.frame_set(source)
    marks = []

    def ik(bone, target, chain, keys):
        c = pb[P + bone].constraints.new('IK')
        c.target = target
        c.chain_count = chain
        for f, value in keys:
            c.influence = value
            c.keyframe_insert("influence", frame=f)

    def empty(name, at):
        e = bpy.data.objects.new(name, None)
        scene.collection.objects.link(e)
        e.location = at
        marks.append(e)
        return e

    for side in ("Left", "Right"): # feet stay where they stand until the source plays
        ik(side + "Leg", empty(side + "Foot", world @ pb[P + side + "Foot"].head), 2, ((first, 1.0), (source, 1.0), (source + 1, 0.0)))
    for hand, keys in clip["hands"].items():
        own = world @ pb[P + hand].head
        target = empty(hand, own)
        for f, mark, _ in keys:
            target.location = own if mark is None else mark
            target.keyframe_insert("location", frame=first + f)
        ik(hand.replace("Hand", "ForeArm"), target, 3, [(first + f, w) for f, _, w in keys])

    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.select_all(action='SELECT')
    bpy.ops.nla.bake(frame_start=first, frame_end=end, only_selected=False, visual_keying=True,
                     clear_constraints=True, use_current_action=True, bake_types={'POSE'})
    bpy.ops.object.mode_set(mode='OBJECT')
    # check: hands on their marks, feet not sliding
    for f in sorted({first + k[0] for keys in clip["hands"].values() for k in keys}):
        scene.frame_set(f)
        print("%s frame %3d hips %.2f hands %s feet %s" % (clip["output"], f - first, (world @ pb[P + "Hips"].head).z,
              [tuple(round(x, 2) for x in world @ pb[P + h].head) for h in clip["hands"]],
              [tuple(round(x, 2) for x in world @ pb[P + s + "Foot"].head) for s in ("Left", "Right")]))
    for e in marks:
        bpy.data.objects.remove(e)
    scene.frame_start, scene.frame_end = first, end
    output = os.path.join(ROOT, "clips", clip["output"])
    bpy.ops.export_scene.fbx(filepath=output, object_types={'ARMATURE'}, add_leaf_bones=False, bake_anim=True,
                             bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False, bake_anim_force_startend_keying=True)
    print("%s: %d frames -> %s" % (clip["output"], end - first + 1, output))


for clip in CLIPS:
    author(clip)
