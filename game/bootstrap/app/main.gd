extends Node3D

const CAMPAIGN := preload("res://game/bootstrap/app/campaign_config.gd")
const PLATFORM := preload("res://game/infrastructure/platform/public/platform.gd")
const BLOOD_PLACEMENT := preload("res://game/bootstrap/app/planning_blood_placement.gd")
const EXPLOSION_TRACE := preload("res://game/features/combat/public/explosion_trace.gd")
const AMBIENT_SOUNDS := preload("res://game/presentation/office_floor/public/ambient_prop_sounds.gd")
const DISPLAY_WALL := preload("res://game/presentation/office_floor/public/display_wall.gd")
const WORLD_BINDINGS := preload("res://game/bootstrap/app/world_bindings.gd")
const IMPACT_POOL := preload("res://game/features/combat/public/impact_effects.gd")

const FALL_DEATH_Y: float = -4.0
const PlanningMode = preload("res://game/bootstrap/app/planning_mode.gd")
const WorldActivation = preload("res://game/bootstrap/app/world_activation.gd")
const TEST_CLOUD := preload("res://game/features/infection_source/public/mutagen_cloud.tscn")
@export var progression_level_id := "prototype_floor"
const MUTATION_UI := preload("res://game/bootstrap/app/mutation_tree_ui.gd")
const BLOOD_EFFECTS := preload("res://game/presentation/office_floor/public/blood_effects_3d.tscn")
const SHADER_WARMUP := preload("res://game/bootstrap/app/shader_warmup.gd")
const HIT_EFFECT_WARMUP := preload("res://game/presentation/office_floor/public/hit_effect_warmup.gd")
const GRENADE_EXPLOSION := preload("res://game/features/combat/public/grenade_explosion.gd")
const BLAST_FEEDBACK := preload("res://game/bootstrap/app/blast_feedback.gd")
const DEBUG_OVERLAY := preload("res://game/bootstrap/app/runtime_debug_overlay.gd")
const OCCLUSION := preload("res://game/bootstrap/app/occlusion_effects.gd")
const MISSION_LAYOUT := preload("res://game/bootstrap/app/mission_layout.gd")
const LEVEL_ENTRIES := preload("res://game/bootstrap/app/level_entry_runtime.gd")
const WAVE_DIRECTOR := preload("res://game/features/spawning/public/wave_director.gd")

@onready var player: Node3D = $Gameplay/Player
@onready var enemies: Node3D = $Gameplay/Enemies
@onready var game_over: Control = $Menus/GameOver
@onready var pause_menu: Control = $Menus/PauseMenu
@onready var planning_ui: Control = $PlanningUI
@onready var planning_root: Node3D = $PlanningObjects
@onready var gameplay: Node3D = $Gameplay
@onready var mutation_choice: Control = $MutationChoice
@onready var infection_runtime: Node = $Gameplay/Player/InfectionRuntime

var world_bindings: RefCounted
var mission_objects: Node3D
var impact_pool: Node3D

var defer_layout_loading := false
## Name of the saved map being played; the level chain uses it to find its neighbours.
var current_level := "":
	set(value):
		current_level = value
		_sync_endless()
var _mission_loading := false
var _ad_showing := false
var _ended := false
var completion_music: Node
var _music_handed_off := false
var _pause_open := false
var planning_mode: Node
var world_activation: Node
var wave_director: Node
var planning_lighting: Node
var mutation_tree_ui: CanvasLayer
var mission_layout: Node3D
var blood_effects: Node3D


# Before any child reads user://: carry saves over from the old project name.
func _init() -> void:
	preload("res://game/bootstrap/app/user_data_migration.gd").run()


func _ready() -> void:
	get_window().title = "Infection Shooter"
	add_child(preload("res://game/bootstrap/app/mission_music.gd").new())
	process_mode = Node.PROCESS_MODE_PAUSABLE
	game_over.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	planning_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	game_over.connect("action_requested", _on_menu_action)
	pause_menu.connect("action_requested", _on_menu_action)
	game_over.hide()
	pause_menu.hide()
	planning_ui.hide()
	_setup_world_bindings()
	$Crosshair.call("configure", player)
	mutation_choice.hide()
	mutation_choice.process_mode = Node.PROCESS_MODE_ALWAYS
	infection_runtime.ability_choice_requested.connect(_on_mutation_choice_requested)
	infection_runtime.ability_changed.connect(_on_mutation_ability_changed)
	infection_runtime.defeated.connect(_on_mutation_defeated)
	mutation_tree_ui = MUTATION_UI.new()
	add_child(mutation_tree_ui)
	infection_runtime.call("begin_control_level", progression_level_id)
	mutation_tree_ui.call("configure", infection_runtime)
	if DisplayServer.get_name() != "headless": # lessons pause the game; automated runs skip them
		var tutorial := preload("res://game/bootstrap/app/tutorial/tutorial_director.gd").new()
		add_child(tutorial)
		tutorial.call("configure", player, $PrototypeHUD, mutation_tree_ui, null, self)
	$MutationChoice/Panel/VBox/Choices/FastHands.pressed.connect(_choose_fast_hands)
	$MutationChoice/Panel/VBox/Choices/LegMutation.pressed.connect(_choose_leg_mutation)
	$MutationChoice/Panel/VBox/Choices/EnhancedAmmo.pressed.connect(_choose_enhanced_ammo)
	planning_mode = PlanningMode.new()
	add_child(planning_mode)
	planning_mode.process_mode = Node.PROCESS_MODE_ALWAYS
	planning_mode.setup(self, planning_root, planning_ui, not defer_layout_loading)
	if OS.is_debug_build(): # Alt camera editing stays out of release exports
		var camera_tuning := preload("res://game/bootstrap/app/gameplay_camera_tuning.gd").new()
		add_child(camera_tuning)
		camera_tuning.setup(player)
	world_activation = WorldActivation.new()
	world_activation.name = "WorldActivation"
	add_child(world_activation)
	world_activation.setup([planning_root, $Structure])
	wave_director = WAVE_DIRECTOR.new()
	wave_director.name = "WaveDirector"
	add_child(wave_director)
	wave_director.call("configure", enemies, player)
	_sync_endless()
	planning_lighting = $PlanningLighting
	planning_lighting.setup($WorldEnvironment, $PlanningUI/Panel/VBox/LightingPreview, $PlanningUI/Panel/VBox/LocalLights)
	mission_layout = MISSION_LAYOUT.new()
	mission_layout.name = "MissionLayout"
	gameplay.add_child(mission_layout)
	mission_layout.call("setup", self, player, infection_runtime)
	var entries := LEVEL_ENTRIES.new()
	entries.name = "LevelEntries"
	add_child(entries)
	entries.setup(self, player, planning_mode)
	planning_mode.controls.hud_layout.setup(planning_mode.controls)
	var occlusion := OCCLUSION.new()
	occlusion.name = "OcclusionEffects"
	add_child(occlusion)
	occlusion.setup(player, player.get("camera") as Camera3D, self)
	if OS.is_debug_build(): # F3 diagnostics stay out of release exports
		var debug := DEBUG_OVERLAY.new()
		debug.name = "RuntimeDebug"
		add_child(debug)
		debug.setup(infection_runtime, occlusion)
	var feedback := BLAST_FEEDBACK.new()
	feedback.name = "BlastFeedback"
	add_child(feedback)
	feedback.configure(player)
	_setup_blood_effects()
	SHADER_WARMUP.new().setup(player.get("camera") as Camera3D)
	EXPLOSION_TRACE.start()
	var hit_warmup := HIT_EFFECT_WARMUP.new()
	hit_warmup.setup(self)
	GRENADE_EXPLOSION.warm_up(hit_warmup, Vector3(0.0, 0.0, -2.0))
	if player.has_method("warm_up_skill_fx"):
		player.call("warm_up_skill_fx", hit_warmup)
	for enemy in enemies.get_children():
		if enemy.has_method("watch_target"):
			enemy.call("watch_target", player)


## The platform's endless level plays endless rounds instead of the authored triggers.
func _sync_endless() -> void:
	if not is_instance_valid(wave_director):
		return
	var campaign := CAMPAIGN.new()
	campaign.load_file()
	wave_director.set("endless", not current_level.is_empty() and current_level == campaign.endless_level(PLATFORM.detect_id()))


func refresh_control_labels() -> void:
	if mutation_tree_ui != null:
		mutation_tree_ui.call("_refresh")


func set_enemy_gameplay_modes(ignore_player: bool, no_damage: bool) -> void:
	player.set_meta("enemy_gameplay_modes_v1", {"ignore_player": ignore_player, "no_damage": no_damage})


func set_test_mutagen_enabled(enabled: bool) -> void:
	var existing := gameplay.get_node_or_null("PermanentTestMutagen")
	if existing != null:
		existing.set_physics_process(enabled)
		existing.set_deferred("monitoring", enabled)
		existing.visible = enabled
		return
	if not enabled:
		return
	var cloud := TEST_CLOUD.instantiate()
	cloud.name = "PermanentTestMutagen"
	cloud.set("permanent", true)
	gameplay.add_child(cloud)
	cloud.global_position = Vector3.ZERO
	cloud.call("activate")


func set_infinite_antidotes_enabled(enabled: bool) -> void:
	player.set("infinite_antidotes", enabled)


## Settings: floor chevrons that point toward the emergency key and the exit.
## Settings: light camera shake on shots.
func set_camera_shake_enabled(enabled: bool) -> void:
	player.call("set_camera_shake_enabled", enabled)


## Tutorial: points the floor chevrons at a lesson goal until called with an invalid callable.
func set_tutorial_hint(target: Callable) -> void:
	if is_instance_valid(mission_layout):
		mission_layout.call("set_tutorial_hint", target)


func set_floor_hints_enabled(enabled: bool) -> void:
	if is_instance_valid(mission_layout):
		mission_layout.call("set_floor_hints_enabled", enabled)


## Settings: blood level 0..3 (green at 0, amount, flight distance) and own procedural blood instead of the decal atlases.
func set_blood_level(level: int, procedural_style: bool) -> void:
	if blood_effects != null:
		blood_effects.call("set_blood_level", level, procedural_style)


## Settings: dodge animation, 0 = dive roll, 1 = strafe jump.
func set_dodge_animation_style(style: int) -> void:
	player.call("set_dodge_animation_style", style)


func set_walk_tuning(speed_multiplier: float, animation_multiplier: float) -> void:
	player.call("set_walk_tuning", speed_multiplier, animation_multiplier)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if mutation_tree_ui != null and bool(mutation_tree_ui.call("is_tree_open")):
			mutation_tree_ui.call("close_tree")
			get_viewport().set_input_as_handled()
			return
		if planning_mode.active:
			planning_mode.exit()
			return
		if _ended:
			return
		if _pause_open:
			_resume_game()
		else:
			_open_pause_menu()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _ended or _pause_open or planning_mode.active:
		return
	if mission_layout.call("goal_reached", player.global_position):
		_end_run("MISSION COMPLETE")
		return
	if bool(infection_runtime.call("is_defeated")):
		_end_run("MUTATION OVERTOOK YOU")
		return
	if player.global_position.y < FALL_DEATH_Y:
		_end_run("YOU FELL OUTSIDE THE FLOOR")
		return
	var health_value: Variant = player.get("health")
	if health_value != null and float(health_value) <= 0.0:
		_end_run("YOU DIED")


func _open_pause_menu() -> void:
	_pause_open = true
	pause_menu.call("show_screen", "pause")
	pause_menu.move_to_front()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume_game() -> void:
	_pause_open = false
	pause_menu.hide()
	get_tree().paused = false


func _on_resume_pressed() -> void:
	_resume_game()


func _on_planning_pressed() -> void:
	_pause_open = false
	pause_menu.hide()
	planning_mode.enter()


func _on_mutation_choice_requested() -> void:
	# Keep the older single-choice runtime compatible with saved games.
	infection_runtime.call("select_ability", 1)
	# Only skill_available opens the tree; legacy reactivation must not prompt.


func _on_mutation_ability_changed(choice: int) -> void:
	if choice == 0:
		mutation_choice.hide()
		if not _pause_open and not planning_mode.active and not _ended and not bool(mutation_tree_ui.call("is_tree_open")):
			get_tree().paused = false


func _select_mutation(choice: int) -> void:
	if infection_runtime.call("select_ability", choice):
		mutation_choice.hide()
		get_tree().paused = false


func _choose_fast_hands() -> void:
	_select_mutation(1)


func _choose_leg_mutation() -> void:
	_select_mutation(2)


func _choose_enhanced_ammo() -> void:
	_select_mutation(3)


func _end_run(reason: String) -> void:
	_ended = true
	var kind := "complete" if reason == "MISSION COMPLETE" else "failed"
	var reason_key: String = {"MUTATION OVERTOOK YOU": "failedMutation",
		"YOU FELL OUTSIDE THE FLOOR": "failedFall", "YOU DIED": "failedHealth"}.get(reason, "")
	if kind == "complete" and not is_instance_valid(completion_music):
		$MissionMusic.call("finish_mission")
		completion_music = preload("res://game/bootstrap/app/completion_music.gd").new()
		get_tree().root.add_child(completion_music)
		game_over.get("_music").set("completion_music", completion_music)
	if kind == "failed":
		var boom := AudioStreamPlayer.new()
		boom.stream = preload("res://assets/audio/music/music_cinematic_boom.ogg")
		boom.process_mode = Node.PROCESS_MODE_ALWAYS # the tree is paused below
		boom.finished.connect(boom.queue_free)
		add_child(boom)
		boom.play()
	game_over.call("show_screen", kind, reason_key)
	game_over.move_to_front()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	if kind == "complete" and int(infection_runtime.call("complete_control_level", progression_level_id)) > 0:
		var notice := Label.new()
		notice.text = tr("ampuleRecovered")
		notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		game_over.add_child(notice)
		notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		notice.offset_top = -100
		notice.offset_bottom = -40


func drop_weapon_pickup(index: int, world_position: Vector3) -> bool:
	if not is_instance_valid(mission_layout):
		return false
	return bool(mission_layout.call("spawn_weapon", index, world_position))


func _on_menu_action(action: String) -> void:
	if _mission_loading:
		return
	match action:
		"resume":
			_on_resume_pressed()
		"planning":
			_on_planning_pressed()
		"continue":
			_on_continue_pressed()
		"restart":
			_after_ad(_on_restart_pressed)
		"start":
			_on_restart_pressed()
		"steam":
			var url := str(game_over.get("steam_url"))
			if url.begins_with("https://"):
				OS.shell_open(url)
		"main", "quit":
			get_tree().paused = false
			if is_instance_valid(completion_music):
				_music_handed_off = true
				preload("res://game/bootstrap/app/menu/music_navigation.gd").show_main(get_tree(), self, completion_music)
			else:
				get_tree().change_scene_to_file("res://game/bootstrap/app/menu/front_end.tscn")


## Platforms with ads show one fullscreen advertisement (sound muted) before `next` runs.
func _after_ad(next: Callable) -> void:
	var platform := get_tree().root.get_node_or_null("Platform")
	var campaign := CAMPAIGN.new()
	campaign.load_file()
	if _ad_showing:
		return
	if platform == null or not campaign.shows_ads(str(platform.get("id"))):
		next.call()
		return
	_ad_showing = true
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), true)
	platform.call("show_ad")
	await platform.ad_finished
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), false)
	_ad_showing = false
	next.call()


func _on_restart_pressed() -> void:
	if _mission_loading:
		return
	if has_node("LevelEntries") and $LevelEntries.chain.index_of(current_level) >= 0:
		travel_to_level(current_level, {})
		return
	_mission_loading = true
	var loader := preload("res://game/bootstrap/app/menu/mission_loader.gd").new()
	add_child(loader)
	loader.set("completion_music", completion_music)
	_music_handed_off = is_instance_valid(completion_music)
	loader.completed.connect(func(_success: bool) -> void: _mission_loading = false)
	loader.start()


## What travels between maps (weapons, control threshold); applied by the loader to the new mission.
func apply_carry(carry: Dictionary) -> void:
	player.call("import_loadout", carry.get("loadout", {}))
	infection_runtime.call("restore_critical_threshold", float(carry.get("threshold", 0.0)))
	infection_runtime.call("restore_control_progress", carry.get("control", {}))


## Level chain: reload the scene with another saved map, arriving at `arrival` ({x, z} or {}).
func travel_to_level(map_name: String, arrival: Dictionary) -> void:
	if _mission_loading:
		return
	_mission_loading = true
	var loader := preload("res://game/bootstrap/app/menu/mission_loader.gd").new()
	add_child(loader)
	loader.set("completion_music", completion_music)
	_music_handed_off = is_instance_valid(completion_music)
	loader.completed.connect(func(_success: bool) -> void: _mission_loading = false)
	var carry := {"loadout": player.call("export_loadout"), "threshold": infection_runtime.call("get_critical_threshold"), "control": infection_runtime.call("export_control_progress")}
	loader.start_map(planning_mode.storage.read_map_path(map_name), map_name, arrival, carry)


func _setup_blood_effects() -> void:
	blood_effects = BLOOD_EFFECTS.instantiate() as Node3D
	add_child(blood_effects)
	blood_effects.call("configure_world", mission_objects, impact_pool)
	impact_pool.connect("penetration_blood", Callable(blood_effects, "splatter_exit"))
	var blood_surfaces: Array[Node] = [$Structure, $Floor, $FloorBody, planning_root]
	blood_effects.call("configure_environment", blood_surfaces)
	enemies.child_entered_tree.connect(_bind_enemy_blood)
	for enemy in enemies.get_children():
		_bind_enemy_blood(enemy)
	_bind_enemy_blood(player)


func _bind_enemy_blood(enemy: Node) -> void:
	bind_world_object(enemy)
	if blood_effects == null or not enemy.has_signal("projectile_blood"):
		return
	if enemy != player:
		var music_callback := Callable($MissionMusic, "notify_monster_hit")
		if not enemy.is_connected("projectile_blood", music_callback):
			enemy.connect("projectile_blood", music_callback)
	var bindings := {
		"projectile_blood": "splatter_hit", "blood_wounded": "small_stain",
		"wounded_moved": "drops_trail", "body_dragged": "smear_drag", "blood_death": "death_pool",
		"limb_severed": "severed_burst"
	}
	if enemy.has_signal("blood_pool_ready"):
		bindings.erase("blood_death")
		bindings["blood_pool_ready"] = "death_pool"
	for event in bindings:
		if not enemy.has_signal(event):
			continue
		var callback := Callable(blood_effects, bindings[event])
		if not enemy.is_connected(event, callback):
			enemy.connect(event, callback)
	enemy.set("blood_drop_distance", blood_effects.call("movement_spacing"))


func _on_mutation_defeated() -> void:
	if _ended:
		return
	if mutation_tree_ui != null and mutation_tree_ui.call("is_tree_open"):
		mutation_tree_ui.call("close_tree")
	_end_run("MUTATION OVERTOOK YOU")


func _setup_world_bindings() -> void:
	mission_objects = Node3D.new()
	mission_objects.name = "MissionObjects"
	add_child(mission_objects)
	# The scene already holds the impact pool; a second one doubled the
	# mark and retained-debris budgets.
	impact_pool = get_node_or_null("ImpactEffects") as Node3D
	if impact_pool == null:
		impact_pool = Node3D.new()
		impact_pool.name = "ImpactEffects"
		impact_pool.set_script(IMPACT_POOL)
		add_child(impact_pool)
	impact_pool.call("register_surface", $FloorBody, $Floor)
	$Floor.call("configure_surface_decals", planning_root.get_meta("surface_decals_v1", {}))
	impact_pool.set("surface_hit", Callable($Floor, "bake_surface_hit"))
	impact_pool.set("surface_step", Callable($Floor, "bake_step"))
	var display_wall := DISPLAY_WALL.new()
	display_wall.name = "DisplayWall"
	add_child(display_wall)
	var ambient := AMBIENT_SOUNDS.new()
	ambient.name = "AmbientPropSounds"
	ambient.player = player
	add_child(ambient)
	world_bindings = WORLD_BINDINGS.new(mission_objects, impact_pool, player, drop_weapon_pickup, display_wall, player.get("camera") as Camera3D)
	world_bindings.set("debris_floor", $Floor)
	world_bindings.call("bind_scene", player)
	for branch in [$Structure, planning_root, enemies]:
		world_bindings.call("bind_scene", branch)
	BLOOD_PLACEMENT.restore_attachments([$Structure, planning_root], impact_pool)


func bind_world_object(node: Node) -> void:
	# The planner catalog binds what it creates; the enemies root binds again
	# when the node enters it. Once is enough.
	if world_bindings != null and not node.has_meta(&"world_bound"):
		node.set_meta(&"world_bound", true)
		world_bindings.call("bind_scene", node)


func set_electronic_particles_enabled(enabled: bool) -> void:
	if world_bindings != null:
		world_bindings.call("set_electronic_particles_enabled", enabled)


func _on_continue_pressed() -> void:
	if has_node("LevelEntries"):
		var chain: RefCounted = $LevelEntries.chain
		var index: int = chain.index_of(current_level)
		if not str(chain.neighbour(index, 1)).is_empty():
			$LevelEntries.travel(index, 1)
			return
	# A standalone prototype has no next authored map; retain its restart route.
	_on_restart_pressed()


func _exit_tree() -> void:
	if is_instance_valid(completion_music) and not _music_handed_off:
		completion_music.call("dispose")
