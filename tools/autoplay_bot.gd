extends SceneTree
## Autoplay QA bot: plays authored maps through the same inputs as a player (move/fire/roll/reload/antidote
## actions and a mouse cursor), no cheats, and writes a report: script errors, frame spikes, FPS, stuck spots,
## ammo/medkit/antidote sufficiency and a difficulty verdict per map and difficulty.
##
## godot --headless --fixed-fps 60 --path . --script res://tools/autoplay_bot.gd -- maps=level_1,level_2 difficulty=all duration=180
## Args (after `--`): maps=<names|all> difficulty=<0,1,2|all> duration=<sim seconds per run> out=<report path without
## extension, default user://autoplay_report> seed=<int> list. Names are chain maps as in campaign_config.json.
## Without --headless the same command renders the game (add --fixed-fps 60 to run faster than real time).
## Not covered: grenades (the game has no grenade input action), keys/doors that need a mission key.

const CHECKPOINT := preload("res://game/bootstrap/app/checkpoint_progress.gd")
const PREFERENCES := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
const LOADER := preload("res://game/bootstrap/app/menu/mission_loader.gd")
const CAMPAIGN := preload("res://game/bootstrap/app/campaign_config.gd")
const ROUTE := preload("res://game/bootstrap/app/floor_route.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")
const MAIN_PATH := "res://game/bootstrap/app/main.tscn"
const SPIKE_MS := 50.0
const LOAD_TIMEOUT_MSEC := 180000
const DIFFICULTY_NAMES := ["low", "normal", "high"]
const ENGAGE := 14.0
const TOO_CLOSE := 4.5

var _errors := ErrorLog.new()
var _opts := {"maps": "all", "difficulty": "all", "duration": "180", "out": "user://autoplay_report", "seed": "1"}
var _route := ROUTE.new()
var _rng := RandomNumberGenerator.new()
var _taps := {}


## Collects every engine/script error line (the log is the only place a SCRIPT ERROR shows up).
class ErrorLog extends Logger:
	var mutex := Mutex.new()
	var items: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		mutex.lock()
		items.append("%s:%d %s" % [file.get_file(), line, rationale if not rationale.is_empty() else code])
		mutex.unlock()

	func take() -> Array[String]:
		mutex.lock()
		var out := items.duplicate()
		items.clear()
		mutex.unlock()
		return out


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := String(arg).trim_prefix("--").split("=", true, 1)
		_opts[parts[0]] = parts[1] if parts.size() > 1 else "true"
	OS.add_logger(_errors)
	_rng.seed = int(_opts.seed)
	call_deferred("_run")


func _maps() -> Array[String]:
	var names: Array[String] = []
	if str(_opts.maps) == "all":
		var config := CAMPAIGN.new()
		config.load_file()
		for level in config.levels("desktop"):
			if level != "tutorial" and level != "endless":
				names.append(level)
	else:
		for name in str(_opts.maps).split(",", false):
			names.append(name)
	return names


func _difficulties() -> Array[int]:
	var list: Array[int] = []
	if str(_opts.difficulty) == "all":
		return [0, 1, 2]
	for value in str(_opts.difficulty).split(",", false):
		list.append(clampi(int(value), 0, 2))
	return list


func _run() -> void:
	var maps := _maps()
	if _opts.has("list") or maps.is_empty():
		print("AUTOPLAY maps: %s" % ", ".join(maps))
		quit(0 if _opts.has("list") else 2)
		return
	var runs: Array[Dictionary] = []
	for map_name in maps:
		for difficulty in _difficulties():
			var run := await _play(map_name, difficulty)
			runs.append(run)
			print("AUTOPLAY %s/%s: %s in %.0fs, %d script errors, p99 %.1f ms, verdict: %s" % [map_name, DIFFICULTY_NAMES[difficulty], run.result, run.sim_seconds, run.script_errors.size(), run.perf.p99_ms, run.verdict])
	var base := str(_opts.out)
	var json := FileAccess.open(base + ".json", FileAccess.WRITE)
	json.store_string(JSON.stringify({"runs": runs}, "\t"))
	json.close()
	var markdown := FileAccess.open(base + ".md", FileAccess.WRITE)
	markdown.store_string(_markdown(runs))
	markdown.close()
	print("AUTOPLAY report: %s.md" % ProjectSettings.globalize_path(base))
	SFX.stop_all(self) # a voice still playing at exit keeps its stream alive (ObjectDB leak)
	if current_scene != null:
		current_scene.queue_free() # an orderly teardown avoids a heap-corruption abort on quit
		for i in 5:
			await process_frame
	var errors := 0
	for run in runs:
		errors += run.script_errors.size() + (1 if str(run.result) == "load_failed" else 0)
	# The engine may abort during teardown after many missions; tools/run_autoplay.sh reads the code from this line.
	print("AUTOPLAY exit_code=%d" % (1 if errors > 0 else 0))
	quit(1 if errors > 0 else 0)


func _play(map_name: String, difficulty: int) -> Dictionary:
	var run := {"map": map_name, "difficulty": DIFFICULTY_NAMES[difficulty], "result": "load_failed", "sim_seconds": 0.0,
		"script_errors": [], "verdict": "no data", "notes": [], "stuck": [], "spikes": [],
		"perf": {"avg_fps": 0.0, "p95_ms": 0.0, "p99_ms": 0.0, "worst_ms": 0.0, "frames": 0}, "supplies": {}, "combat": {}}
	var settings := PREFERENCES.new()
	settings.load_settings()
	settings.values.enemy_difficulty = difficulty
	settings.save_settings()
	DirAccess.remove_absolute("user://frame_spikes.log")
	_errors.take()
	paused = false
	var loader := LOADER.new()
	root.add_child(loader)
	loader.start_map(CHECKPOINT.map_file(map_name), map_name, {})
	var main: Node = await _wait_for_main(loader)
	run.script_errors = _errors.take()
	if main == null:
		run.notes.append("map did not load (missing map file or loader error)")
		return run
	if is_instance_valid(main.get("tutorial")):
		main.get("tutorial").queue_free() # lessons pause the game
	var key := InputEventKey.new() # F3 opens the debug overlay, which starts frame_spike_log
	key.keycode = KEY_F3
	key.pressed = true
	Input.parse_input_event(key)
	await _drive(main, run)
	run.script_errors.append_array(_errors.take())
	_finish(run)
	return run


## Waits until the mission scene is active; null when loading fails or times out.
func _wait_for_main(loader: Node) -> Node:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < LOAD_TIMEOUT_MSEC:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == MAIN_PATH and not is_instance_valid(loader):
			for i in 30:
				await process_frame
			return current_scene
		if is_instance_valid(loader) and loader.get("back") != null and (loader.get("back") as Button).visible:
			loader.call("_close_error")
			return null
	return null


func _drive(main: Node, run: Dictionary) -> void:
	var player: CharacterBody3D = main.get("player")
	var mission: Node = main.get("mission_layout")
	var infection: Node = main.get("infection_runtime")
	var mutation := [0.0, 1.0]
	infection.mutation_changed.connect(func(current: float, critical: float) -> void: mutation = [current, maxf(critical, 0.001)])
	var duration := float(_opts.duration)
	var phys_start := Engine.get_physics_frames()
	var tick := float(Engine.physics_ticks_per_second)
	var frame_ms: Array[float] = []
	var last_usec := Time.get_ticks_usec()
	var sim := 0.0
	var next_scan := 0.0
	var next_route := 0.0
	var next_stuck := 0.0
	var next_antidote := 0.0
	var next_weapon := 0.0
	var strafe_sign := 1.0
	var next_strafe := 0.0
	var unstick_until := 0.0
	var unstick_dir := Vector3.ZERO
	var anchor := player.global_position
	var anchor_t := 0.0
	var path: Array[Vector3] = []
	var path_goal := Vector3.INF
	var blacklist := {}
	var dwell := {}
	var crates: Array = []
	var pickups: Array = []
	var tracked := {} # pickup instance id -> {"type", "pos"}
	var crate_target: Object = null
	var crate_since := 0.0
	var seen_enemies := {}
	var supplies := {"medkit": {"seen": 0, "collected": 0}, "ammo": {"seen": 0, "collected": 0}, "antidote": {"seen": 0, "collected": 0}, "armor": {"seen": 0, "collected": 0}}
	var crates_total := 0
	var crates_broken := 0
	var crate_ids := {}
	var kills := 0
	var damage := 0.0
	var min_hp := float(player.get("health"))
	var max_hp := maxf(float(player.get("max_health")), 1.0)
	var hp := float(player.get("health"))
	var start_ammo := _ammo_total(player)
	var ammo := start_ammo
	var ammo_spent := 0
	var ammo_found := 0
	var dry_seconds := 0.0
	var dry_no_supply := 0.0
	var hp_low_no_medkit := 0.0
	var antidotes_used := 0
	var antidotes_wanted_empty := 0.0
	var antidotes := int(player.get("antidotes"))
	var scene_changed := false
	while sim < duration:
		await process_frame
		var now := Time.get_ticks_usec()
		var frame := (now - last_usec) / 1000.0
		last_usec = now
		frame_ms.append(frame)
		_release_taps()
		sim = float(Engine.get_physics_frames() - phys_start) / tick
		if frame > SPIKE_MS and run.spikes.size() < 20:
			run.spikes.append({"t": snappedf(sim, 0.01), "ms": snappedf(frame, 0.1), "pos": _p(player.global_position)})
		if current_scene != main or not is_instance_valid(main):
			scene_changed = true
			break
		if bool(main.get("_ended")):
			break
		if paused and not bool(main.get("_ended")) and not bool(main.get("_pause_open")):
			paused = false
		if bool(main.get("_dying")):
			_release_all()
			continue
		var pos := player.global_position
		var dt := 1.0 / tick
		# Bookkeeping: health, ammo, kills.
		var now_hp := float(player.get("health"))
		if now_hp < hp:
			damage += hp - now_hp
		hp = now_hp
		min_hp = minf(min_hp, hp)
		var now_ammo := _ammo_total(player)
		if now_ammo < ammo:
			ammo_spent += ammo - now_ammo
		elif now_ammo > ammo:
			ammo_found += now_ammo - ammo
		ammo = now_ammo
		var now_antidotes := int(player.get("antidotes"))
		if now_antidotes < antidotes:
			antidotes_used += antidotes - now_antidotes
		antidotes = now_antidotes
		var enemies: Array = []
		for node in get_nodes_in_group("infected_alive"):
			if node is Node3D and is_instance_valid(node) and not node.is_queued_for_deletion():
				enemies.append(node)
		var alive_ids := {}
		for enemy in enemies:
			alive_ids[enemy.get_instance_id()] = true
			seen_enemies[enemy.get_instance_id()] = true
		for id in seen_enemies.keys():
			if not alive_ids.has(id):
				seen_enemies.erase(id)
				kills += 1
		# Scan world for pickups and lootable crates twice a second.
		if sim >= next_scan:
			next_scan = sim + 0.5
			pickups.clear()
			crates.clear()
			for node in get_nodes_in_group("hidden_outline"):
				if not (node is Node3D) or node.is_queued_for_deletion():
					continue
				if str(node.scene_file_path).contains("/pickups/public/"):
					var kind := _pickup_kind(str(node.scene_file_path))
					pickups.append(node)
					if not tracked.has(node.get_instance_id()):
						tracked[node.get_instance_id()] = {"type": kind, "pos": node.global_position}
						if supplies.has(kind):
							supplies[kind].seen += 1
				elif node.has_method("has_loot") and bool(node.call("has_loot")) and str(node.call("get_loot_config").get("mode", "empty")) != "empty":
					crates.append(node)
					if not crate_ids.has(node.get_instance_id()):
						crate_ids[node.get_instance_id()] = true
						crates_total += 1
			for id in tracked.keys():
				var obj := instance_from_id(id)
				if obj == null or not is_instance_valid(obj) or (obj as Node).is_queued_for_deletion():
					var info: Dictionary = tracked[id]
					if pos.distance_to(info.pos) < 3.0 and supplies.has(info.type):
						supplies[info.type].collected += 1
					tracked.erase(id)
			crates_broken = 0
			for id in crate_ids.keys():
				var crate := instance_from_id(id)
				if crate == null or not is_instance_valid(crate) or not (crate as Node).is_in_group("hidden_outline"):
					crates_broken += 1
		# Supply starvation accounting.
		var enemy_near := not enemies.is_empty()
		var total_ammo_known := ammo_total_known(pickups, crates)
		if ammo <= 0:
			dry_seconds += dt
			if not total_ammo_known:
				dry_no_supply += dt
		if hp < max_hp * 0.35 and not _has_kind(pickups, "medkit") and crates.is_empty():
			hp_low_no_medkit += dt
		var infection_ratio := float(mutation[0]) / float(mutation[1])
		if infection_ratio > 0.6 and now_antidotes <= 0:
			antidotes_wanted_empty += dt
		if infection_ratio > 0.6 and now_antidotes > 0 and sim >= next_antidote:
			next_antidote = sim + 3.0
			_tap("antidote")
		# Choose weapon/reload.
		var weapon: Node = player.call("get_current_weapon")
		if weapon != null:
			var mag := int(weapon.call("get_magazine_ammo"))
			var reserve := int(weapon.call("carried_ammo"))
			if mag <= 0 and reserve > 0:
				_tap("reload")
			elif mag <= 0 and reserve <= 0 and sim >= next_weapon:
				next_weapon = sim + 0.6
				_tap("weapon_%d" % _rng.randi_range(1, 3))
		# Pick the objective.
		var nearest: Node3D = null
		var nearest_d := INF
		for enemy in enemies:
			var d := pos.distance_to(enemy.global_position)
			if d < nearest_d:
				nearest_d = d
				nearest = enemy
		var goal := Vector3.INF
		var mission_goal := Vector3.INF
		var aim := Vector3.INF
		var fire := false
		var combat := nearest != null and nearest_d < ENGAGE and ammo > 0
		if combat:
			aim = nearest.global_position + Vector3.UP
			fire = true
		var want_hp := hp < max_hp * 0.5
		var want_ammo := ammo < maxi(start_ammo / 3, 20)
		var pick: Node3D = _best_pickup(pos, pickups, want_hp, want_ammo, max_hp - hp, ammo >= start_ammo, blacklist, sim)
		if combat and nearest_d < TOO_CLOSE:
			goal = pos + (pos - nearest.global_position).normalized() * 6.0
		elif combat and pick == null:
			goal = Vector3.INF # hold position and shoot
		elif pick != null:
			goal = pick.global_position
			if pos.distance_to(goal) < 1.3: # standing on it without it vanishing: give up on this one
				dwell[pick.get_instance_id()] = float(dwell.get(pick.get_instance_id(), 0.0)) + dt
				if float(dwell[pick.get_instance_id()]) > 2.0:
					blacklist[pick.get_instance_id()] = sim + 90.0
		else:
			var crate_pick: Node3D = _nearest(pos, crates, blacklist, sim)
			if crate_pick != null:
				if crate_target != crate_pick:
					crate_target = crate_pick
					crate_since = sim
				if sim - crate_since > 25.0:
					blacklist[crate_pick.get_instance_id()] = sim + 60.0
					crate_target = null
				elif pos.distance_to(crate_pick.global_position) < 4.0 and ammo > 0:
					aim = crate_pick.global_position + Vector3.UP * 0.4
					fire = true
				else:
					goal = crate_pick.global_position
			else:
				goal = mission.call("floor_hint_target")
				mission_goal = goal
		# Movement: follow the route, strafe while shooting, unstick when blocked.
		var direction := Vector3.ZERO
		if sim < unstick_until:
			direction = unstick_dir
		elif goal.is_finite():
			if path_goal.distance_to(goal) > 1.0 or sim >= next_route or path.is_empty():
				next_route = sim + 0.5
				path_goal = goal
				path = _route.find(player.get_world_3d().direct_space_state, pos, Vector3(goal.x, 0.0, goal.z), [player.get_rid()])
			while path.size() > 1 and Vector2(pos.x, pos.z).distance_to(Vector2(path[0].x, path[0].z)) < 0.7:
				path.pop_front()
			var aim_at := path[0] if not path.is_empty() else goal
			direction = Vector3(aim_at.x - pos.x, 0.0, aim_at.z - pos.z)
			if direction.length() < 0.5:
				# No usable route (blocked cells, or already on the last waypoint): walk straight at the goal.
				direction = Vector3(goal.x - pos.x, 0.0, goal.z - pos.z)
				if direction.length() < 1.2:
					direction = Vector3.ZERO
		elif combat and nearest_d > TOO_CLOSE:
			if sim >= next_strafe:
				next_strafe = sim + _rng.randf_range(0.8, 2.0)
				strafe_sign = -strafe_sign
			var to_enemy := nearest.global_position - pos
			direction = Vector3(-to_enemy.z, 0.0, to_enemy.x).normalized() * strafe_sign
		var heading := direction.normalized() if direction.length() > 0.01 else Vector3.ZERO
		var exit_close := goal.is_finite() and goal == mission_goal and pos.distance_to(goal) < 8.0 # the exit is a hole in the floor
		if heading != Vector3.ZERO and not exit_close and not _has_floor(player, pos + heading * 1.6):
			path.clear()
			if sim >= unstick_until:
				unstick_until = sim + 0.6
				unstick_dir = Vector3(-heading.z, 0.0, heading.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
			heading = Vector3.ZERO
		_steer(player, heading)
		if nearest != null and nearest_d < 2.2 and sim >= next_strafe - 100.0 and player.get("_roll_cooldown_remaining") != null and float(player.get("_roll_cooldown_remaining")) <= 0.0 and _rng.randf() < 0.02:
			_tap("roll")
		if fire and aim.is_finite():
			_aim(player, aim)
			var held: bool = weapon != null and bool(weapon.call("wants_continuous_fire"))
			if held or Engine.get_process_frames() % 8 < 4: # semi-auto guns fire on each new press
				Input.action_press("fire")
			else:
				Input.action_release("fire")
		else:
			Input.action_release("fire")
		# Stuck detection while trying to move.
		if sim >= next_stuck:
			next_stuck = sim + 1.0
			if sim - anchor_t >= 2.5:
				var moved := Vector2(pos.x - anchor.x, pos.z - anchor.z).length()
				if moved < 0.3 and direction.length() > 0.1 and sim >= unstick_until:
					if run.stuck.size() < 20:
						run.stuck.append({"t": snappedf(sim, 0.1), "pos": _p(pos), "goal": _p(goal) if goal.is_finite() else null})
					unstick_until = sim + 1.2
					unstick_dir = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
					_tap("roll")
					if path_goal.is_finite() and run.stuck.size() > 0 and run.stuck.size() % 3 == 0:
						for pickup in pickups:
							if is_instance_valid(pickup) and pickup.global_position.distance_to(path_goal) < 1.0:
								blacklist[pickup.get_instance_id()] = sim + 30.0
						if crate_target != null:
							blacklist[crate_target.get_instance_id()] = sim + 60.0
					path.clear()
				anchor = pos
				anchor_t = sim
	_release_all()
	var ended: bool = scene_changed or (is_instance_valid(main) and bool(main.get("_ended")))
	var complete := scene_changed
	if is_instance_valid(main) and ended and not scene_changed:
		complete = bool(mission.call("goal_reached", player.global_position))
	run.sim_seconds = sim
	run.end_pos = _p(player.global_position) if is_instance_valid(player) else []
	run.end_hp = hp
	run.result = "complete" if complete else ("failed" if ended or hp <= 0.0 or bool(main.get("_dying")) else "timeout")
	frame_ms.sort()
	var count := maxi(frame_ms.size(), 1)
	var total := 0.0
	for value in frame_ms:
		total += value
	run.perf = {"avg_fps": snappedf(1000.0 * count / maxf(total, 0.001), 0.1), "p95_ms": snappedf(frame_ms[int(count * 0.95) - 1] if count > 1 else 0.0, 0.01),
		"p99_ms": snappedf(frame_ms[int(count * 0.99) - 1] if count > 1 else 0.0, 0.01), "worst_ms": snappedf(frame_ms.back() if not frame_ms.is_empty() else 0.0, 0.1), "frames": frame_ms.size()}
	run.supplies = {"by_kind": supplies, "crates_total": crates_total, "crates_broken": crates_broken, "ammo_start": start_ammo, "ammo_end": ammo,
		"ammo_spent": ammo_spent, "ammo_found": ammo_found, "dry_seconds": snappedf(dry_seconds, 0.1), "dry_seconds_no_supply_known": snappedf(dry_no_supply, 0.1),
		"low_hp_no_medkit_seconds": snappedf(hp_low_no_medkit, 0.1), "antidotes_used": antidotes_used, "antidotes_end": antidotes,
		"antidote_wanted_but_empty_seconds": snappedf(antidotes_wanted_empty, 0.1)}
	run.combat = {"kills": kills, "damage_taken": snappedf(damage, 0.1), "min_health_pct": snappedf(100.0 * min_hp / max_hp, 0.1)}
	var spikes := FileAccess.get_file_as_string("user://frame_spikes.log")
	if not spikes.is_empty():
		run.frame_spike_log_tail = "\n".join(spikes.split("\n").slice(-25))


func _finish(run: Dictionary) -> void:
	var notes: Array = run.notes
	var s: Dictionary = run.supplies
	var c: Dictionary = run.combat
	if s.is_empty():
		return
	if float(s.dry_seconds_no_supply_known) > 3.0:
		notes.append("AMMO: out of ammo for %.0fs with no ammo pickup or crate in sight (not enough ammo)" % float(s.dry_seconds_no_supply_known))
	if float(s.low_hp_no_medkit_seconds) > 3.0:
		notes.append("MEDKITS: health below 35%% for %.0fs with no medkit around (not enough medkits)" % float(s.low_hp_no_medkit_seconds))
	if float(s.antidote_wanted_but_empty_seconds) > 3.0:
		notes.append("ANTIDOTES: infection above 60%% for %.0fs with no antidote in stock (not enough antidotes)" % float(s.antidote_wanted_but_empty_seconds))
	if int(s.crates_total) > 0 and int(s.crates_broken) < int(s.crates_total):
		notes.append("CRATES: broke %d of %d loot crates" % [int(s.crates_broken), int(s.crates_total)])
	if not run.stuck.is_empty():
		notes.append("STUCK: %d spots" % run.stuck.size())
	if not run.spikes.is_empty():
		notes.append("SPIKES: %d frames over %.0f ms, worst %.0f ms" % [run.spikes.size(), SPIKE_MS, float(run.perf.worst_ms)])
	if not run.script_errors.is_empty():
		notes.append("ERRORS: %d script/engine errors" % run.script_errors.size())
	var min_hp := float(c.min_health_pct)
	var starved := not notes.filter(func(n: String) -> bool: return n.begins_with("AMMO") or n.begins_with("MEDKITS") or n.begins_with("ANTIDOTES")).is_empty()
	match str(run.result):
		"complete":
			run.verdict = "too easy" if min_hp >= 70.0 and not starved else ("tight on supplies" if starved else "balanced")
		"failed":
			run.verdict = "too hard (or short of supplies)" if starved else "too hard"
		_:
			run.verdict = "inconclusive (time ran out; the bot may be lost, see STUCK)"


func _markdown(runs: Array[Dictionary]) -> String:
	var out := "# Autoplay report\n\n| map | difficulty | result | time s | min HP % | damage | kills | ammo spent/found | dry s | FPS | p99 ms | errors | verdict |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for run in runs:
		var s: Dictionary = run.supplies
		var c: Dictionary = run.combat
		out += "| %s | %s | %s | %.0f | %s | %s | %s | %s/%s | %s | %s | %s | %d | %s |\n" % [run.map, run.difficulty, run.result, run.sim_seconds,
			c.get("min_health_pct", "-"), c.get("damage_taken", "-"), c.get("kills", "-"), s.get("ammo_spent", "-"), s.get("ammo_found", "-"),
			s.get("dry_seconds", "-"), run.perf.avg_fps, run.perf.p99_ms, run.script_errors.size(), run.verdict]
	for run in runs:
		out += "\n## %s / %s\n" % [run.map, run.difficulty]
		for note in run.notes:
			out += "- %s\n" % note
		if run.supplies.has("by_kind"):
			var kinds: Dictionary = run.supplies.by_kind
			out += "- supplies seen/collected: medkit %d/%d, ammo %d/%d, antidote %d/%d, armor %d/%d; antidotes used %d\n" % [kinds.medkit.seen, kinds.medkit.collected,
				kinds.ammo.seen, kinds.ammo.collected, kinds.antidote.seen, kinds.antidote.collected, kinds.armor.seen, kinds.armor.collected, run.supplies.antidotes_used]
		for stuck in run.stuck:
			out += "- stuck at t=%s pos=%s goal=%s\n" % [stuck.t, stuck.pos, stuck.goal]
		for spike in run.spikes:
			out += "- spike t=%s %s ms at %s\n" % [spike.t, spike.ms, spike.pos]
		for error in run.script_errors.slice(0, 20):
			out += "- error: %s\n" % error
		if run.has("frame_spike_log_tail"):
			out += "\n```\n%s\n```\n" % run.frame_spike_log_tail
	return out


func ammo_total_known(pickups: Array, crates: Array) -> bool:
	return _has_kind(pickups, "ammo") or not crates.is_empty()


func _has_kind(pickups: Array, kind: String) -> bool:
	for pickup in pickups:
		if is_instance_valid(pickup) and _pickup_kind(str(pickup.scene_file_path)) == kind:
			return true
	return false


func _pickup_kind(scene: String) -> String:
	var file := scene.get_file()
	if file.begins_with("medkit") or file.begins_with("med_case"):
		return "medkit"
	if file.begins_with("ammo_"):
		return "ammo"
	for kind in ["antidote", "armor", "dna", "key"]:
		if file.begins_with(kind):
			return kind
	return "other"


func _ammo_total(player: Node) -> int:
	var total := 0
	var slots: Variant = player.get("_slot_weapons")
	var weapons: Array = player.get("weapons")
	for index in (slots if slots is Array else range(weapons.size())):
		var i := int(index)
		if i >= 0 and i < weapons.size() and weapons[i] != null:
			total += int(weapons[i].call("carried_ammo")) + int(weapons[i].call("get_magazine_ammo"))
	return total


## Needed pickups first (health when hurt, ammo when low), otherwise anything within 18 m.
func _best_pickup(pos: Vector3, pickups: Array, want_hp: bool, want_ammo: bool, hp_missing: float, ammo_full: bool, blacklist: Dictionary, sim: float) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	for pickup in pickups:
		if not is_instance_valid(pickup) or blacklist.get(pickup.get_instance_id(), 0.0) > sim:
			continue
		var kind := _pickup_kind(str(pickup.scene_file_path))
		if kind == "key" or kind == "other":
			continue
		var distance := pos.distance_to(pickup.global_position)
		var needed := (kind == "medkit" and want_hp) or (kind == "ammo" and want_ammo) or kind == "antidote" or kind == "armor"
		if (kind == "medkit" and not want_hp and hp_missing <= 1.0) or (kind == "ammo" and not want_ammo and ammo_full):
			continue # a full hero would stand on it without picking it up
		if distance > (45.0 if needed else 18.0):
			continue
		var score := distance - (20.0 if needed else 0.0)
		if score < best_score:
			best_score = score
			best = pickup
	return best


func _nearest(pos: Vector3, nodes: Array, blacklist: Dictionary, sim: float) -> Node3D:
	var best: Node3D = null
	var best_d := 60.0
	for node in nodes:
		if not is_instance_valid(node) or blacklist.get(node.get_instance_id(), 0.0) > sim:
			continue
		var d := pos.distance_to(node.global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


## Converts a world direction into the camera-relative move actions the hero reads.
func _steer(player: Node, direction: Vector3) -> void:
	var camera: Camera3D = player.get("camera")
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var x := direction.dot(right)
	var y := -direction.dot(forward)
	_axis("move_right", "move_left", x)
	_axis("move_down", "move_up", y)
	if direction.length() > 0.1:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")


func _axis(positive: String, negative: String, value: float) -> void:
	if value > 0.01:
		Input.action_press(positive, value)
		Input.action_release(negative)
	elif value < -0.01:
		Input.action_press(negative, -value)
		Input.action_release(positive)
	else:
		Input.action_release(positive)
		Input.action_release(negative)


## Puts the cursor over a world point (viewport pixels); the hero aims by raycasting from the cursor.
func _aim(player: Node, world: Vector3) -> void:
	var camera: Camera3D = player.get("camera")
	if camera.is_position_behind(world):
		return
	player.set("aim_cursor_override", camera.unproject_position(world).clamp(Vector2.ZERO, camera.get_viewport().get_visible_rect().size))


func _has_floor(player: Node3D, point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.8, point + Vector3.DOWN * 2.5, 3)
	return not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _tap(action: String) -> void:
	Input.action_press(action)
	_taps[action] = Engine.get_process_frames() + 4


func _release_taps() -> void:
	for action in _taps.keys():
		if Engine.get_process_frames() >= int(_taps[action]):
			Input.action_release(action)
			_taps.erase(action)


func _release_all() -> void:
	if is_instance_valid(current_scene) and current_scene.get("player") != null:
		current_scene.get("player").set("aim_cursor_override", Vector2.INF)
	for action in ["move_left", "move_right", "move_up", "move_down", "sprint", "fire"]:
		Input.action_release(action)


func _p(v: Vector3) -> Array:
	return [snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)]
