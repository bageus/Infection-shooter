extends Node

@export var character_path: NodePath = NodePath("..")
@export var model_path: NodePath = NodePath("Body")
@export var run_speed_threshold := 6.8

var character: CharacterBody3D
var animation_player: AnimationPlayer
var _current := ""
var _animations: Dictionary = {}

func _ready() -> void:
	character = get_parent() as CharacterBody3D
	if character == null:
		character = get_node_or_null(character_path) as CharacterBody3D
	var model: Node = null
	if character != null:
		model = character.get_node_or_null(model_path)
	if model == null:
		return
	animation_player = _find_animation_player(model)
	if animation_player != null:
		_index_animations()
		_play_semantic(["idle", "stand"])

func _process(_delta: float) -> void:
	if character == null or animation_player == null:
		return
	var horizontal_speed := Vector2(character.velocity.x, character.velocity.z).length()
	if horizontal_speed > run_speed_threshold:
		_play_semantic(["run", "sprint"])
	elif horizontal_speed > 0.15:
		_play_semantic(["walk", "walking", "locomotion"])
	else:
		_play_semantic(["idle", "stand"])

func _index_animations() -> void:
	_animations.clear()
	for animation_name in animation_player.get_animation_list():
		var normalized := str(animation_name).to_lower().replace(" ", "_").replace("-", "_")
		_animations[normalized] = str(animation_name)


func _play_semantic(tokens: Array[String]) -> void:
	for token in tokens:
		var wanted := token.to_lower()
		for normalized in _animations.keys():
			if wanted in str(normalized):
				var actual := str(_animations[normalized])
				if _current != actual:
					_current = actual
					animation_player.play(actual, 0.12)
				return
	var list := animation_player.get_animation_list()
	if not list.is_empty() and _current.is_empty():
		_current = list[0]
		animation_player.play(_current)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
