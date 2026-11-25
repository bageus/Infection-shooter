extends Node3D
## Planner decoration: the hero's body lying dead (on back, on side, face down). It is the pose the death fall
## ends in (player_death_fall.gd): the model turned a quarter about its X axis, lifted by its thickness.
const DEATH_FALL := preload("res://game/features/player/player_death_fall.gd")
const MODEL := preload("res://models/objects/characters/soldier_animated.glb")
## Turn of the standing model: back and face down about X (it faces +Z), side about Z.
const TURNS := {"back": Vector3(-PI * 0.5, 0.0, 0.0), "face_down": Vector3(PI * 0.5, 0.0, 0.0), "side": Vector3(0.0, 0.0, PI * 0.5)}
@export_enum("back", "face_down", "side") var pose := "back"


func _ready() -> void:
	var body := MODEL.instantiate() as Node3D
	body.name = "Body"
	body.basis = Basis.from_euler(TURNS[pose])
	body.position.y = DEATH_FALL.LIE_LIFT
	add_child(body)
