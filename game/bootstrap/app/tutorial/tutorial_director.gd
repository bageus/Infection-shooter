extends Node
## Decides when the first-time lessons start and what their steps are, then feeds them to the overlay.
## First run: move to the fire door, shoot the bottles, look for the key, one-way doors, roll and run,
## explore, break the crates, weapon hotkeys. Mutation: scale and antidote, active skill, passive skill and
## locking, control loss, the M menu, gas mask.
## One lesson plays at a time; later ones wait in a queue. A lesson is remembered the moment it starts,
## so it is never shown twice.

const OVERLAY := preload("res://game/bootstrap/app/tutorial/tutorial_overlay.gd")
const PROGRESS := preload("res://game/bootstrap/app/tutorial/tutorial_progress.gd")
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
const TARGET := preload("res://game/presentation/office_floor/public/tutorial_target.gd")
const KEYS := preload("res://game/bootstrap/app/tutorial/tutorial_keys.gd")
const SCALE_TRIGGER := 5.0
const STEP_METERS := 0.8
const DOOR_SPAN := 1.6 # half width, metres along the door, in which a crossing counts
const DOOR_DEPTH := 3.0 # how far from the door a side is recorded
const DOOR_SIDE := 0.5 # clear of the door plane
const CLOUD_RANGE := 5.0
const INHALE_GAIN := 0.5 # meter rise that counts as having inhaled mutagen
const CRATE_SIGHT := 9.0
const LOOK_SECONDS := 0.8
const ADOPT_WINDOW := 30.0 # seconds after start in which a loading map may still add targets
const FIRST_LESSON_DELAY := 2.0
# Maps that replay every lesson regardless of the saved "seen" flags. Empty the list to restore once-only lessons.
const ALWAYS_ON_LEVELS: Array[String] = ["tutorial_lvl"]
const ONE_WAY_MODE := 1 # DoorMode.SWING_ONE_WAY in interactive_door.gd

var overlay: Node
var progress: RefCounted
var current := ""
var _queue: Array[String] = []
var _steps: Array = []
var _runtime: Node
var _hud: Node
var _tree_ui: Node
var _player: Node
var _started_mutation := 0.0
var _host: Node
var _finished := {}
var _walked := 0.0
var _walked_at_end := 0.0
var _last_position := Vector3.INF
var _look_seconds := 0.0
var _rolled := false
var _sprinted_seconds := 0.0
var _key_hunt := false
var _door_clock := 0.0
var _since_start := 0.0
var _adopt_clock := 0.0


func configure(player: Node, hud: Node, tree_ui: Node, progress_state: RefCounted = null, host: Node = null) -> void:
	_host = host
	_player = player
	_hud = hud
	_tree_ui = tree_ui
	_runtime = player.get("infection_runtime")
	progress = progress_state if progress_state != null else PROGRESS.new()
	overlay = OVERLAY.new()
	overlay.name = "TutorialOverlay"
	add_child(overlay)
	overlay.step_finished.connect(_next_step)
	_runtime.mutation_changed.connect(_on_mutation_changed)
	_runtime.skill_available.connect(_on_skill_available)
	_runtime.control_loss_changed.connect(_on_control_loss_changed)


# On a replay level only this run's own lessons count as seen.
func _seen(lesson: String) -> bool:
	if _host != null and str(_host.get("current_level")) in ALWAYS_ON_LEVELS:
		return _finished.has(lesson)
	return progress.is_done(lesson)


func request(lesson: String) -> void:
	if _seen(lesson) or lesson == current or lesson in _queue:
		return
	# Losing control cannot wait: the lesson in progress restarts after it.
	if lesson == "control_loss" and not current.is_empty():
		overlay.call("finish", false)
		_queue.push_front(current)
		current = ""
		_queue.push_front(lesson)
		_start_next()
		return
	_queue.append(lesson)
	if current.is_empty():
		_start_next()


func _process(delta: float) -> void:
	_track_input(delta)
	_since_start += delta
	_adopt_clock -= delta
	if _adopt_clock <= 0.0 and _since_start < ADOPT_WINDOW:
		_adopt_clock = 0.5
		TARGET.adopt_baked(get_tree())
	_door_clock -= delta
	if _door_clock <= 0.0:
		_door_clock = 0.15
		_watch_one_way_doors()
	if _key_hunt and bool(_player.call("has_emergency_key")):
		_end_key_hunt()
	if current.is_empty() and _queue.is_empty() and _since_start >= FIRST_LESSON_DELAY:
		_start_first_run_lesson()


# Walked distance, camera turning, roll and sprint: what the first-run lessons wait for.
func _track_input(delta: float) -> void:
	var position: Vector3 = _player.global_position
	if _last_position.is_finite():
		var moved := Vector2(position.x - _last_position.x, position.z - _last_position.z).length()
		if moved < 3.0: # a teleport is not a walk
			_walked += moved
	_last_position = position
	if Input.is_action_pressed("camera_left") or Input.is_action_pressed("camera_right"):
		_look_seconds += delta
	if Input.is_action_just_pressed("roll"):
		_rolled = true
	if Input.is_action_pressed("sprint"):
		_sprinted_seconds += delta


func _steps_since_last_lesson() -> float:
	return (_walked - _walked_at_end) / STEP_METERS


# A lesson counts as over when it ended this session or an earlier one, and is not playing now.
func _over(lesson: String) -> bool:
	return (_finished.has(lesson) or _seen(lesson)) and lesson != current and not lesson in _queue


func _start_first_run_lesson() -> void:
	if not _over("move"):
		request("move")
		return
	var bottles := TARGET.standing(get_tree(), "bottle")
	if not _over("shoot") and not bottles.is_empty():
		if _steps_since_last_lesson() >= 3.0:
			request("shoot")
		return
	if not _over("look"):
		if _steps_since_last_lesson() >= 5.0:
			request("look")
		return
	if not _over("explore") and bool(_player.call("has_emergency_key")):
		request("explore")
		return
	if _over("explore") and not _over("crates") and not TARGET.standing(get_tree(), "crate").is_empty():
		request("crates")
		return
	if not _over("roll") and (_over("one_way") or _over("explore")) and _steps_since_last_lesson() >= 5.0:
		request("roll")
		return
	if not _over("weapons") and _occupied_weapon_slots() >= 2:
		request("weapons")
	if not _over("armor") and float(_player.get("armor")) > 0.0:
		request("armor")


func _occupied_weapon_slots() -> int:
	var count := 0
	for slot in 3:
		if int(_player.call("get_weapon_in_slot", slot)) >= 0:
			count += 1
	return count


# One-way doors tell the player once, on the first approach from the closed side.
func _watch_one_way_doors() -> void:
	for node in get_tree().get_nodes_in_group("interactive_doors"):
		var door := node as Node3D
		if door == null or int(door.get("mode")) != ONE_WAY_MODE:
			continue
		var local := door.to_local(_player.global_position)
		var closed_side := signf(local.z) != signf(float(door.get("one_way_allowed_side")))
		if closed_side and Vector2(local.x, local.z).length() <= float(door.get("trigger_distance")):
			request("one_way")
			return


func _on_mutation_changed(amount: float, _limit: float) -> void:
	if amount >= SCALE_TRIGGER and not bool(_runtime.call("is_control_lost")):
		request("mutation_scale")


func _on_skill_available() -> void:
	if bool(_runtime.call("is_control_lost")) or bool(_runtime.call("is_defeated")):
		return
	if bool(_runtime.call("can_upgrade_skill", "power_strike")):
		request("active_skill")
	elif (current == "active_skill" or _seen("active_skill") or _finished.has("active_skill")) and bool(_runtime.call("can_upgrade_skill", "muscle_memory")):
		request("passive_skill")


func _on_control_loss_changed(active: bool) -> void:
	if active:
		request("control_loss")


func _start_next() -> void:
	if _queue.is_empty():
		current = ""
		return
	current = _queue.pop_front()
	if current == "one_way":
		_end_key_hunt() # "find another way" is now the active objective, not the key
	progress.mark_done(current)
	_walked_at_end = _walked
	_steps = _build_steps(current)
	_reveal_targets(current)
	_started_mutation = float(_runtime.call("get_mutation"))
	_look_seconds = 0.0
	_rolled = false
	_sprinted_seconds = 0.0
	if current == "active_skill" or current == "passive_skill":
		_tree_ui.call("open_tree")
	_next_step()


# Each stage shows only its own markers, the moment the stage starts.
func _reveal_targets(lesson: String) -> void:
	match lesson:
		"move":
			TARGET.reveal(get_tree(), ["door"])
		"shoot":
			TARGET.reveal(get_tree(), ["bottle", "extinguisher"])
		"crates":
			TARGET.reveal(get_tree(), ["crate"])


func _next_step() -> void:
	_hud.call("set_tutorial_objective", "")
	if _steps.is_empty():
		_end_lesson()
		return
	var step: Dictionary = _steps.pop_front()
	_hud.call("set_tutorial_objective", str(step.get("objective", "")))
	overlay.call("play", step)


func _end_lesson() -> void:
	var lesson := current
	_finished[lesson] = true
	_walked_at_end = _walked
	match lesson:
		"move":
			for door in TARGET.standing(get_tree(), "door"):
				TARGET.configure(door, false) # the fire door has been reached
		"look":
			_begin_key_hunt()
		"control_loss":
			request("open_menu")
			request("gas_mask")
	_start_next()


# The look lesson ends quickly; the arrow keeps pointing at the key until it is taken.
func _begin_key_hunt() -> void:
	if bool(_player.call("has_emergency_key")) or get_tree().get_nodes_in_group("mission_key").is_empty():
		return
	_key_hunt = true
	if _host != null:
		_host.call("set_tutorial_hint", _key_goal)


func _end_key_hunt() -> void:
	_key_hunt = false
	if _host != null:
		_host.call("set_tutorial_hint", Callable())


func _key_goal() -> Vector3:
	var best := Vector3.INF
	var best_distance := INF
	for key: Node3D in get_tree().get_nodes_in_group("mission_key"):
		var distance := key.global_position.distance_squared_to(_player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = key.global_position
	return best


func _build_steps(lesson: String) -> Array:
	var mutation := _hud_rect.bind("mutation")
	var antidote := _hud_rect.bind("antidote")
	var antidote_key := KEYS.binding("antidote")
	match lesson:
		"move":
			var doors := TARGET.standing(get_tree(), "door")
			if doors.is_empty():
				return _task(TEXT.t("tutMoveFree"), TEXT.t("objMoveFree"), KEYS.movement(), "cycle", func() -> bool: return _steps_since_last_lesson() >= 5.0)
			var door: Node3D = doors[0]
			return _task(TEXT.t("tutMove"), TEXT.t("objMove"), KEYS.movement(), "cycle", _through([door]))
		"shoot":
			return _task(TEXT.t("tutShoot") % KEYS.binding("fire"), TEXT.t("objShoot"), KEYS.row(["fire"]), "all",
					func() -> bool: return TARGET.standing(get_tree(), "bottle").is_empty())
		"look":
			return _task(TEXT.t("tutLook") % [KEYS.binding("camera_left"), KEYS.binding("camera_right")], TEXT.t("objLook"),
					KEYS.row(["camera_left", "camera_right"]), "cycle",
					func() -> bool: return _look_seconds >= LOOK_SECONDS)
		"one_way":
			return [_click(TEXT.t("tutOneWay"), [])] + _task(TEXT.t("tutOneWayFind"), TEXT.t("objOneWay"), [], "cycle", _through_any_door())
		"roll":
			return (_task(TEXT.t("tutRoll") % KEYS.binding("roll"), TEXT.t("objRoll") % KEYS.binding("roll"), KEYS.row(["roll"]), "all", func() -> bool: return _rolled)
					+ _task(TEXT.t("tutSprint") % KEYS.binding("sprint"), TEXT.t("objSprint") % KEYS.binding("sprint"), KEYS.row(["sprint"]), "all", func() -> bool: return _sprinted_seconds >= 0.5))
		"explore":
			return _task(TEXT.t("tutExplore"), TEXT.t("objExplore"), [], "cycle", func() -> bool: return _crate_in_sight() or TARGET.standing(get_tree(), "crate").is_empty())
		"crates":
			return _task(TEXT.t("tutCrates") % KEYS.binding("melee"), TEXT.t("objCrates"), KEYS.row(["melee"]), "all",
					func() -> bool: return TARGET.standing(get_tree(), "crate").is_empty())
		"weapons":
			return [_click(TEXT.t("tutWeapons") % [KEYS.binding("weapon_1"), KEYS.binding("weapon_2"), KEYS.binding("weapon_3")], [_hud_rect.bind("weapons")])]
		"armor":
			return [{"text": TEXT.t("tutArmor"), "targets": [_hud_rect.bind("armor")], "mode": "click", "picture": true,
					"armor": float(_player.get("armor")) / maxf(float(_player.get("max_armor")), 1.0)}]
		"mutation_scale":
			return [
				_click(TEXT.t("tutMeterGrow"), [mutation]),
				_picture(TEXT.t("tutMeterLimit")),
				_click(TEXT.t("tutAntidote") % antidote_key, [antidote]),
				_click(TEXT.t("tutAntidoteWise"), [antidote]),
			] + _task(TEXT.t("tutInhale"), TEXT.t("objInhale"), [], "cycle", _inhaled_all())
		"active_skill":
			return [
				_click(TEXT.t("tutBranches"), [_tree_rect.bind("active"), _tree_rect.bind("passive")], _tree_open),
				_click(TEXT.t("tutActive"), [_tree_rect.bind("active")], _tree_open),
				_click(TEXT.t("tutPassive"), [_tree_rect.bind("passive")], _tree_open),
				_wait(TEXT.t("tutPickPower"), [_tree_rect.bind("skill:power_strike")], _power_strike_chosen, _tree_open, true),
			] + _task(TEXT.t("tutKillActive") % KEYS.binding("skill_1"), TEXT.t("objKill") % KEYS.binding("skill_1"), [], "cycle", _skill_ready.bind("muscle_memory"))
		"passive_skill":
			return [
				_wait(TEXT.t("tutPickReload"), [_tree_rect.bind("skill:muscle_memory")], _skill_learned.bind("muscle_memory"), _tree_open, true),
				_click(TEXT.t("tutLock"), [_tree_rect.bind("skill:lock:muscle_memory")], _tree_open),
			]
		"control_loss":
			return [
				_click(TEXT.t("tutLostControl"), [mutation]),
				_wait(TEXT.t("tutUseAntidote") % antidote_key, [antidote], _antidote_used, Callable(), true),
				_click(TEXT.t("tutAntidoteEffect"), [mutation]),
			]
		"open_menu":
			return _task(TEXT.t("tutOpenMenu") % KEYS.binding("mutation_tree"), TEXT.t("objOpenMenu") % KEYS.binding("mutation_tree"), [], "cycle", _tree_open) + [
				_wait(TEXT.t("tutPassiveUse"), [_tree_rect.bind("passive")], func() -> bool: return not _tree_open(), _tree_open, false),
			]
		"gas_mask":
			return [_click(TEXT.t("tutGasMask") % "TAB", [_hud_rect.bind("gas_mask")])]
	return []


func _click(text: String, targets: Array, requires: Callable = Callable()) -> Dictionary:
	return {"text": text, "targets": targets, "mode": "click", "requires": requires}


func _picture(text: String) -> Dictionary:
	return {"text": text, "targets": [], "mode": "click", "picture": true,
		"mutation": _runtime.call("get_mutation"), "threshold": _runtime.call("get_critical_threshold")}


# A task: first a full-screen overlay that pauses the game and shows the key caps, then the task sits in
# the HUD objective banner (the game runs) until `done` is true.
func _task(text: String, objective: String, keys: Array, keys_mode: String, done: Callable) -> Array:
	var intro := {"text": text, "targets": [], "mode": "click", "requires": Callable()}
	if not keys.is_empty():
		intro["keys"] = keys
		intro["keys_mode"] = keys_mode
	var pending := {"text": objective, "targets": [], "mode": "wait", "done": done, "objective": objective,
			"requires": func() -> bool: return false}
	return [intro, pending]


func _wait(text: String, targets: Array, done: Callable, requires: Callable, arrow: bool, dim: bool = true) -> Dictionary:
	return {"text": text, "targets": targets, "mode": "wait", "done": done, "requires": requires, "arrow": arrow, "dim": dim}


# True once the player has walked through one of the doors, from one side of its plane to the other.
func _through(targets: Array) -> Callable:
	var sides := {}
	return func() -> bool:
		for target: Node3D in targets:
			if not is_instance_valid(target):
				return true
			var frame: Node3D = target.get_node_or_null("DoorController")
			if frame == null:
				frame = target
			var local := frame.to_local(_player.global_position)
			var id := frame.get_instance_id()
			if absf(local.x) > DOOR_SPAN or absf(local.z) > DOOR_DEPTH:
				sides.erase(id) # far from the opening: a walk around does not count
			elif absf(local.z) >= DOOR_SIDE:
				var side := signf(local.z)
				if sides.has(id) and sides[id] != side:
					return true
				sides[id] = side
		return false


# "Find another way": the player gets through some door (a one-way door's closed side cannot be passed).
func _through_any_door() -> Callable:
	return _through(get_tree().get_nodes_in_group("interactive_doors"))


func _crate_in_sight() -> bool:
	for crate: Node3D in TARGET.standing(get_tree(), "crate"):
		var from: Vector3 = _player.global_position
		if Vector2(crate.global_position.x - from.x, crate.global_position.z - from.z).length() <= CRATE_SIGHT:
			return true
	return false


# The player has taken mutagen in since the task began (the meter went up), or every cloud near at the start is spent.
func _inhaled_all() -> Callable:
	var start := float(_runtime.call("get_mutation"))
	var clouds: Array = []
	for cloud: Node3D in get_tree().get_nodes_in_group("mutagen_clouds"):
		if cloud.global_position.distance_to(_player.global_position) <= CLOUD_RANGE:
			clouds.append(cloud)
	return func() -> bool:
		if float(_runtime.call("get_mutation")) >= start + INHALE_GAIN:
			return true
		return not clouds.is_empty() and clouds.all(func(cloud: Node3D) -> bool: return not is_instance_valid(cloud) or bool(cloud.call("is_spent")))


func _hud_rect(kind: String) -> Rect2:
	return _hud.call("tutorial_rect", kind)


func _tree_rect(kind: String) -> Rect2:
	return _tree_ui.call("tutorial_rect", kind)


func _tree_open() -> bool:
	return bool(_tree_ui.call("is_tree_open"))


func _skill_learned(skill_id: String) -> bool:
	return bool(_runtime.call("skill_learned", skill_id))


# The first point is spent: on Power Strike, or on whatever else the player preferred.
func _power_strike_chosen() -> bool:
	return _skill_learned("power_strike") or int(_runtime.call("mutation_points")) <= 0


func _skill_ready(skill_id: String) -> bool:
	return bool(_runtime.call("can_upgrade_skill", skill_id)) or _skill_learned(skill_id)


# Control is back and the dose was spent: mutation dropped, or nothing was left to spend.
func _antidote_used() -> bool:
	if float(_runtime.call("get_mutation")) < _started_mutation - 0.5:
		return true
	return not bool(_runtime.call("is_control_lost")) and _player.antidotes <= 0 and not _player.infinite_antidotes
