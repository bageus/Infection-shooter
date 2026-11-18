extends RefCounted
## The hero's baked body clips (ADR-0070), played by the animation driver over the base clip on all bones but the arms
## (they keep their grip): the kick and the turns on the spot. Death clips are picked here too.

const KICK := &"Kick"
const TURN := {&"left": &"Turn_Left", &"right": &"Turn_Right"}
const DEATHS := [&"Death_FromRight", &"Death_Dying", &"Death_HitToBack"]
## The death clip that ends in a ragdoll (the fall backward).
const RAGDOLL_AFTER := &"Death_HitToBack"
## One pass of a turn clip (it turns the hero 45 degrees) lasts this many seconds. The clip keeps looping, its seam
## blended, for as long as the hero is still turning, and the body swings round at the matching rate (player_body_aim.gd).
const TURN_SECONDS := 0.5
## Per second rate at which the turn pose follows its clip (a low-pass that takes the flicks out of the quick steps).
const TURN_SMOOTH := 20.0
## Seconds of the clip over which the end of a pass is blended into its start.
const TURN_LOOP_BLEND := 0.25
const KICK_SPEED := 1.6
const BODY_BONES := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
## A turn on the spot drives only the pelvis and legs (the steps): the game already swings the torso, arms and head with the aim,
## and a second clip on them made the head jerk (Vadim).
const TURN_BONES := ["Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
const ARM_BONES := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]
const RAGDOLL := preload("res://game/features/character_animation/hero_ragdoll.gd")
const OVERLAY := preload("res://game/features/character_animation/clip_overlay.gd")


static func has_kick(driver: Node) -> bool:
	return driver.animation_player != null and driver.animation_player.has_animation(KICK)


static func running(driver: Node) -> bool:
	return driver.body_clip != null and bool(driver.body_clip.call("is_playing"))


## Seconds from the start of a strike to its impact, from the Kick clip's impact_time; `fallback` for anything else.
static func impact_time(driver: Node, kind: StringName, fallback: float) -> float:
	if kind == &"kick" and has_kick(driver):
		return float(driver.clip_meta(KICK, &"impact_time", fallback * KICK_SPEED * 0.5)) / KICK_SPEED
	return fallback


## Plays `clip` over the body; returns its length in seconds, 0.0 when the skeleton is missing.
static func play(driver: Node, clip: StringName, clip_speed: float, kind: StringName) -> float:
	if driver.body_clip == null:
		var skeletons: Array = driver.animation_player.get_parent().find_children("*", "Skeleton3D", true, false)
		if skeletons.is_empty():
			return 0.0
		var overlay := OVERLAY.new()
		overlay.name = "BodyClip"
		overlay.held = ARM_BONES
		overlay.fade_in = 0.12
		overlay.fade_out = 0.2
		(skeletons[0] as Node).add_child(overlay)
		driver.body_clip = overlay
	var animation: Animation = driver.animation_player.get_animation(clip)
	driver.body_clip.bones = TURN_BONES if kind == &"turn" else BODY_BONES
	driver.body_clip.speed = clip_speed
	driver.body_clip.loop_blend = TURN_LOOP_BLEND if kind == &"turn" else 0.0
	driver.body_clip.smooth = TURN_SMOOTH if kind == &"turn" else 0.0
	driver.body_clip.play(animation, animation.length / clip_speed)
	driver.set_meta(&"body_clip_kind", kind)
	return animation.length / clip_speed


static func is_kicking(driver: Node) -> bool:
	return driver.get_meta(&"body_clip_kind", &"") == &"kick" and running(driver)


## The turn clip for `side`, unless one already runs; false without the clip.
static func turn(driver: Node, side: StringName) -> bool:
	if driver.animation_player == null or not TURN.has(side) or not driver.animation_player.has_animation(TURN[side]):
		return false
	if running(driver):
		driver.body_clip.hold() # still turning: the clip goes on instead of fading out and starting again
		return true
	var clip: StringName = TURN[side]
	return play(driver, clip, driver.animation_player.get_animation(clip).length / TURN_SECONDS, &"turn") > 0.0


## A random death clip the player has, or &"" without any.
static func pick_death(driver: Node) -> StringName:
	var choices: Array[StringName] = []
	for clip in DEATHS:
		if driver.animation_player.has_animation(clip):
			choices.append(clip)
	return choices[randi() % choices.size()] if not choices.is_empty() else &""


## A new skeleton modifier from `script` under the player's first skeleton; null without a skeleton.
static func attach(player: AnimationPlayer, script: GDScript, node_name: String) -> SkeletonModifier3D:
	var skeletons := player.get_parent().find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	var modifier := script.new() as SkeletonModifier3D
	modifier.name = node_name
	(skeletons[0] as Node).add_child(modifier)
	return modifier


## Merges `extra` into the player's default library (same names win).
static func merge_clips(player: AnimationPlayer, extra: AnimationLibrary) -> void:
	var merged := player.get_animation_library(&"").duplicate(false) as AnimationLibrary
	for clip_name in extra.get_animation_list():
		if merged.has_animation(clip_name):
			merged.remove_animation(clip_name)
		merged.add_animation(clip_name, extra.get_animation(clip_name))
	player.remove_animation_library(&"")
	player.add_animation_library(&"", merged)


## Makes the idle/walk/run clips of every library loop; works on instance-owned copies, never on imported shared resources.
static func loop_clips(player: AnimationPlayer, looping: Array, blocked: Array) -> void:
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name).duplicate(false) as AnimationLibrary
		for clip_name in library.get_animation_list():
			var lower := String(clip_name).to_lower()
			if blocked.any(func(token: String) -> bool: return token in lower) or not looping.any(func(token: String) -> bool: return token in lower):
				continue
			var animation := library.get_animation(clip_name).duplicate(false) as Animation
			animation.loop_mode = Animation.LOOP_LINEAR
			library.remove_animation(clip_name)
			library.add_animation(clip_name, animation)
		player.remove_animation_library(library_name)
		player.add_animation_library(library_name, library)


## Lets the dead hero go limp: the bones turn into a ragdoll that settles on the floor.
static func release_ragdoll(driver: Node) -> void:
	var skeletons: Array = driver.animation_player.get_parent().find_children("*", "Skeleton3D", true, false) if is_instance_valid(driver.animation_player) else []
	if skeletons.is_empty():
		return
	driver.ragdoll = RAGDOLL.start(skeletons[0] as Skeleton3D, driver.character)
	if driver.ragdoll != null:
		driver.animation_player.active = false # the simulation owns the bones now
