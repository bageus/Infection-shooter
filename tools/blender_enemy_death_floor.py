# Death clips whose last pose lies on the floor (Vadim, 17.11.2026): in the Mixamo sources the
# corpse ends with a foot, hand or the head lifted into the air. Over the last frames IK pulls
# every limb that is above its floor height down to it, and the result is baked.
#   /opt/bpy/bin/python tools/blender_enemy_death_floor.py
# Reads clips/Zombie Dying, hunger_clips/Stumble Backwards, clips/Zombie Stumbling and writes
# "<name> Floor.fbx" next to the source; tools/build_hunger_clips.gd retargets those (EXTRA Death*).
import bpy, os
from mathutils import Vector

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models", "objects", "characters", "enemy")
P = "mixamorig:"
RAMP = 22  # most frames over which the limbs come down, finished a few frames before the end
LANDED = 0.3  # the limbs only start down once the hips are this low, so the fall itself stays as authored
SETTLED = 4
# bone whose head is the marked point, IK bone, chain length, highest allowed world z (m)
LIMBS = [("LeftHand", "LeftForeArm", 3, 0.07), ("RightHand", "RightForeArm", 3, 0.07),
         ("LeftFoot", "LeftLeg", 2, 0.09), ("RightFoot", "RightLeg", 2, 0.09),
         ("Head", "Neck", 2, 0.13)]
SOURCES = ["clips/Zombie Dying", "hunger_clips/Stumble Backwards", "clips/Zombie Stumbling"]


def author(source):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT, source + ".fbx"))
    scene = bpy.context.scene
    scene.render.fps = 30
    arm = [o for o in scene.objects if o.type == 'ARMATURE'][0]
    pb = arm.pose.bones
    first, last = (int(x) for x in arm.animation_data.action.frame_range)
    world = arm.matrix_world
    # The exporter writes the pose at the first frame as the skeleton's rest pose, and the retarget
    # reads the rest pose as the T-pose. So the clip gets one extra first frame in the T-pose
    # (the build skips it with "from"), and starts at first - 1.
    for bone in pb:
        bone.location = (0, 0, 0)
        bone.rotation_quaternion = (1, 0, 0, 0)
        bone.scale = (1, 1, 1)
        bone.keyframe_insert("location", frame=first - 1)
        bone.keyframe_insert("rotation_quaternion", frame=first - 1)
        bone.keyframe_insert("scale", frame=first - 1)
    start = first - 1
    hips = []
    for f in range(first, last + 1):
        scene.frame_set(f)
        hips.append((world @ pb[P + "Hips"].head).z)
    # first frame from which the hips stay on the floor
    landed = next(f for f in range(first, last + 1) if all(z <= LANDED for z in hips[f - first:]))
    ramp = max(SETTLED + 2, min(RAMP, last - landed))
    marks = []
    for point, tip, chain, cap in LIMBS:
        target = bpy.data.objects.new(point, None)
        scene.collection.objects.link(target)
        marks.append(target)
        for f in range(start, last + 1):
            scene.frame_set(f)
            at = world @ pb[P + point].head
            x = min(1.0, max(0.0, (f - (last - ramp)) / (ramp - SETTLED)))
            x = x * x * (3.0 - 2.0 * x)
            at.z = at.z + (min(at.z, cap) - at.z) * x
            target.location = at
            target.keyframe_insert("location", frame=f)
        c = pb[P + tip].constraints.new('IK')
        c.target = target
        c.chain_count = chain
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.select_all(action='SELECT')
    bpy.ops.nla.bake(frame_start=start, frame_end=last, only_selected=False, visual_keying=True,
                     clear_constraints=True, use_current_action=True, bake_types={'POSE'})
    bpy.ops.object.mode_set(mode='OBJECT')
    scene.frame_set(last)
    print(source, "last frame z:", {p: round((world @ pb[P + p].head).z, 2) for p, *_ in LIMBS},
          "toes", [round((world @ pb[P + s + "ToeBase"].head).z, 2) for s in ("Left", "Right")])
    scene.frame_set(start)  # the exporter writes the current pose as the rest pose: the T-pose frame
    for e in marks:
        bpy.data.objects.remove(e)
    scene.frame_start, scene.frame_end = start, last
    output = os.path.join(ROOT, source + " Floor.fbx")
    bpy.ops.export_scene.fbx(filepath=output, object_types={'ARMATURE'}, add_leaf_bones=False, bake_anim=True,
                             bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False, bake_anim_force_startend_keying=True)


for source in SOURCES:
    author(source)
