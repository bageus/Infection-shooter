extends SceneTree
## A07: legacy public scenes consume only a positive award, once.
const MEDKIT := preload("res://game/features/pickups/public/medkit_closed_pickup.tscn")
const MED_CASE := preload("res://game/features/pickups/public/med_case_green_pickup.tscn")
const AMMO_RED := preload("res://game/features/pickups/public/ammo_red_pickup.tscn")
const AMMO_ORANGE := preload("res://game/features/pickups/public/ammo_orange_pickup.tscn")
const PLAYER := preload("res://game/features/player/public/player.tscn")
const SCENES := [MEDKIT, MED_CASE, AMMO_RED, AMMO_ORANGE]
const AMOUNTS := [35.0, 50.0, 36, 60]
var failures := 0

class Collector:
	extends Node
	var room := 0.0
	var gained := 0.0
	var calls := 0
	var sounds: Array[StringName] = []
	var source: StringName
	var offered := 0.0
	var during_award: Callable
	func heal(amount: float, from: StringName) -> float:
		source = from
		return _receive(amount)
	func add_ammo_to_current_weapon(amount: int) -> int:
		return int(_receive(amount))
	func _receive(amount: float) -> float:
		calls += 1
		offered = amount
		if during_award.is_valid():
			var callback := during_award
			during_award = Callable()
			callback.call()
		var accepted := minf(maxf(amount, 0.0), room)
		room -= accepted
		gained += accepted
		return accepted
	func play_item_sound(event: StringName) -> void:
		sounds.append(event)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for index in SCENES.size():
		_test_refusal_and_retry(index)
		_test_success_once(index)
		_test_nonpositive_amount(index)
	await _test_real_player()
	await process_frame
	print("Legacy pickup tests: %d failures" % failures)
	quit(1 if failures else 0)


func _spawn(index: int) -> Area3D:
	var item := (SCENES[index] as PackedScene).instantiate() as Area3D
	root.add_child(item)
	return item


func _test_refusal_and_retry(index: int) -> void:
	var item := _spawn(index)
	var collector := Collector.new()
	root.add_child(collector)
	item.call("_on_body_entered", null)
	var unrelated := Node.new()
	item.body_entered.emit(unrelated)
	unrelated.free()
	_check(not bool(item.get("_consumed")), "Unsupported bodies do not consume %s" % item.name)
	for attempt in 2:
		item.body_entered.emit(collector)
		_check(not bool(item.get("_consumed")) and not item.is_queued_for_deletion(), "Full collector keeps %s available" % item.name)
	_check(collector.calls == 2 and collector.gained == 0.0, "Both refused entries reach the collector")
	_check(collector.sounds.is_empty(), "Refused medkits stay silent")
	# The same object is offered again after capacity becomes available.
	collector.room = .25 if index < 2 else 2.0
	var available := collector.room
	item.body_entered.emit(collector)
	_check(is_equal_approx(collector.gained, available), "Retry grants the actual partial capacity")
	_check(bool(item.get("_consumed")) and item.is_queued_for_deletion(), "Positive retry consumes the item")
	_check(is_equal_approx(collector.offered, float(AMOUNTS[index])), "Authored quantity is preserved")
	if index < 2:
		_check(collector.source == &"medkit", "Healing keeps the medkit source")
		_check(collector.sounds == [&"medkit_pickup", &"medkit_use"], "Accepted health pickup keeps its two cues")
	collector.free()
	item.free()


func _test_success_once(index: int) -> void:
	var item := _spawn(index)
	var first := Collector.new()
	var second := Collector.new()
	root.add_child(first)
	root.add_child(second)
	first.room = 1000.0
	second.room = 1000.0
	# heal emits synchronously; an observer can offer the same item again.
	first.during_award = func() -> void: item.body_entered.emit(first)
	item.body_entered.emit(first)
	item.body_entered.emit(first)
	item.body_entered.emit(second)
	_check(first.calls == 1 and first.gained == float(AMOUNTS[index]), "Success/reentrant/duplicate entries grant only once")
	_check(second.calls == 0 and second.gained == 0.0, "Another collector cannot take the queued item")
	_check(item.is_queued_for_deletion(), "Successful item is queued for deletion")
	_check(first.sounds.size() == (2 if index < 2 else 0), "Legacy sound behaviour remains unchanged")
	first.free()
	second.free()
	item.free()


func _test_nonpositive_amount(index: int) -> void:
	for amount in [0, -1]:
		var item := _spawn(index)
		item.set("heal_amount" if index < 2 else "ammo_amount", amount)
		var collector := Collector.new()
		collector.room = 1000.0
		root.add_child(collector)
		item.body_entered.emit(collector)
		_check(not item.is_queued_for_deletion() and not bool(item.get("_consumed")), "Nonpositive amount is refused")
		_check(collector.gained == 0.0 and collector.sounds.is_empty(), "No reward or sound for an empty pickup")
		item.free()
		collector.free()


func _test_real_player() -> void:
	var player := PLAYER.instantiate() as CharacterBody3D
	root.add_child(player)
	player.set_physics_process(false)
	var weapon: Node = player.call("get_current_weapon")
	for index in SCENES.size():
		var item := _spawn(index)
		player.set("health", player.get("max_health"))
		weapon.call("add_reserve_ammo", int(weapon.get("max_reserve_ammo")))
		item.body_entered.emit(player)
		_check(not item.is_queued_for_deletion(), "Real full player refuses legacy scene")
		if index < 2:
			player.set("health", float(player.get("max_health")) - .25)
		else:
			weapon.get("_reserve").amount = int(weapon.get("max_reserve_ammo")) - 2
		item.body_entered.emit(player)
		_check(item.is_queued_for_deletion(), "Real player accepts same object after capacity changes")
		_check(player.get("health") == player.get("max_health"), "Real health stays capped")
		_check(weapon.call("get_reserve_ammo") == weapon.get("max_reserve_ammo"), "Real ammo stays capped")
		item.free()
	player.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
