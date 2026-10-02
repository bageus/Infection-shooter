extends Node

@export var character_path: NodePath = NodePath("..")
@export var model_path: NodePath = NodePath("Body")
@export var run_speed_threshold := 6.8

var character: CharacterBody3D
var animation_player: AnimationPlayer
var _current := ""
var _animations: Dictionary = {}
var _clip_selector: Callable
var _missing_clips: Dictionary = {}


# Public animation_selection_v1: optional presentation-only selector.
func configure_clip_selector(selector: Callable) -> void:
	var changed := _clip_selector != selector
	_clip_selector = selector
	if animation_player != null and selector.is_valid():
		if changed:
			_configure_looping_clips()
		_play_selected_clip()

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
		if _clip_selector.is_valid():
			_configure_looping_clips()
		_play_semantic(["idle", "stand"])

func _process(_delta: float) -> void:
	if character == null or animation_player == null:
		return
	if _play_selected_clip():
		return
	var horizontal_speed := Vector2(character.velocity.x, character.velocity.z).length()
	if horizontal_speed > run_speed_threshold:
		_play_semantic(["run", "sprint"])
	elif horizontal_speed > 0.15:
		_play_semantic(["walk", "walking", "locomotion"])
	else:
		_play_semantic(["idle", "stand"])

func _play_selected_clip() -> bool:
	if not _clip_selector.is_valid():
		return false
	var requested := StringName(_clip_selector.call())
	if animation_player.has_animation(requested):
		_play_clip(String(requested))
		return true
	if not requested.is_empty() and not _missing_clips.has(requested):
		_missing_clips[requested] = true
		push_warning("Character animation clip unavailable: %s" % requested)
	return false


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
					_play_clip(actual)
				return
	var list := animation_player.get_animation_list()
	if not list.is_empty() and _current.is_empty():
		_current = list[0]
		animation_player.play(_current)


func _play_clip(actual: String) -> void:
	if _current == actual:
		return
	_current = actual
	animation_player.play(actual, 0.12)


func _configure_looping_clips() -> void:
	# Configure instance-owned copies once; never mutate imported shared resources.
	for library_name in animation_player.get_animation_library_list():
		var library := animation_player.get_animation_library(library_name).duplicate(false) as AnimationLibrary
		for clip_name in library.get_animation_list():
			if not (String(clip_name).begins_with("Idle_") or String(clip_name).begins_with("Walk_")):
				continue
			var animation := library.get_animation(clip_name).duplicate(false) as Animation
			animation.loop_mode = Animation.LOOP_LINEAR
			library.remove_animation(clip_name)
			library.add_animation(clip_name, animation)
		animation_player.remove_animation_library(library_name)
		animation_player.add_animation_library(library_name, library)


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
