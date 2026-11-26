extends Node3D
## Planner decoration: the hero's body in a death pose. The pose is the last frame of a baked death clip,
## and the weapons and magazines of the model are hidden, so the body lies with nothing in its hands.
const MODEL := preload("res://models/objects/characters/soldier_animated.glb")
const DEATH_CLIPS := preload("res://models/objects/characters/hero_extra_clips.res")
const DEATH_FALL := preload("res://game/features/player/player_death_fall.gd")
## The clip that ends each pose: back falls face up, face down ends face down, side falls to the right.
const CLIPS := {"back": &"Death_HitToBack", "face_down": &"Death_Dying", "side": &"Death_FromRight"}
## Weapon roots in the hand (Weapon_*, hiding them hides their children), their magazines and loose props.
## The backpack, vest and body stay.
const WEAPON_PREFIXES := ["Weapon_", "Mesh_", "Magazine_", "Prop_", "BarrelCluster"]
@export_enum("back", "face_down", "side") var pose := "back"


func _ready() -> void:
	var body := MODEL.instantiate() as Node3D
	body.name = "Body"
	add_child(body)
	for node in body.find_children("*", "Node3D", true, false):
		if WEAPON_PREFIXES.any(func(prefix: String) -> bool: return String(node.name).begins_with(prefix)):
			(node as Node3D).visible = false
	var player := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.add_animation_library("hero", DEATH_CLIPS)
	player.play("hero/" + CLIPS[pose])
	player.seek(player.current_animation_length, true)
	player.pause()
	body.position.y = DEATH_FALL.LIE_LIFT
