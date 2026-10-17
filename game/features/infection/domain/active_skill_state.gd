extends RefCounted
## Two equipped skills and effect-then-recovery timing, owned by infection.
const CATALOG := preload("res://game/features/infection/domain/mutation_catalog.gd")
var slots: Array[String] = ["", ""]
var effects: Dictionary = {}
var effect_totals: Dictionary = {}
var totals: Dictionary = {}
var _available: Dictionary = {}


func assign(index: int, id: String, tree, mutation: float, stability: float) -> bool:
	if index < 0 or index >= slots.size():
		return false
	if not id.is_empty() and (not CATALOG.is_active_skill(id) or not tree.is_active(id, mutation, stability)):
		return false
	for other in slots.size():
		if other != index and not id.is_empty() and CATALOG.family(slots[other]) == CATALOG.family(id):
			return false
	for row in CATALOG.ACTIVE:
		if CATALOG.family(str(row[0])) == CATALOG.family(id) and CATALOG.level(str(row[0])) > CATALOG.level(id) and tree.learned.has(str(row[0])):
			return false
	slots[index] = id
	if not id.is_empty():
		_available[id] = true
	return true


func learned(id: String, tree, mutation: float, stability: float) -> void:
	if not CATALOG.is_active_skill(id):
		return
	for index in slots.size():
		if not slots[index].is_empty() and CATALOG.family(slots[index]) == CATALOG.family(id):
			var previous := slots[index]
			tree.cooldowns[id] = float(tree.cooldowns.get(previous, 0.0))
			if effects.has(previous):
				effects[id] = effects[previous]
				effect_totals[id] = effect_totals.get(previous, effects[previous])
				effects.erase(previous)
			totals[id] = maxf(float(totals.get(previous, 0.0)), float(tree.cooldowns[id]))
			slots[index] = id
			_available[id] = tree.is_active(id, mutation, stability)
			return
	for index in slots.size():
		if slots[index].is_empty():
			slots[index] = id
			_available[id] = tree.is_active(id, mutation, stability)
			return


func reconcile(tree, mutation: float, stability: float, factor: float) -> bool:
	var changed := false
	for index in slots.size():
		var id := slots[index]
		if id.is_empty():
			continue
		if not tree.learned.has(id):
			slots[index] = ""
			changed = true
	for row in CATALOG.ACTIVE:
		var id := str(row[0])
		var active: bool = tree.is_active(id, mutation, stability)
		if _available.has(id) and active != bool(_available[id]):
			changed = true
			if active:
				start_recovery(id, tree, factor)
			else:
				effects.erase(id)
		_available[id] = active
	return changed


func start_recovery(id: String, tree, factor: float) -> void:
	totals[id] = CATALOG.cooldown(id) * factor
	tree.cooldowns[id] = totals[id]


func can_cast(id: String, tree, mutation: float, stability: float) -> bool:
	return id in slots and tree.is_active(id, mutation, stability) and float(effects.get(id, 0.0)) <= 0.0 and float(tree.cooldowns.get(id, 0.0)) <= 0.0


func tick(seconds: float, tree, mutation: float, stability: float, factor: float, effects_advance: bool = true) -> Array[String]:
	var finished: Array[String] = []
	for row in CATALOG.ACTIVE:
		var id := str(row[0])
		if not tree.is_active(id, mutation, stability):
			continue
		var remaining := float(effects.get(id, 0.0))
		var recovery_time := seconds
		if remaining > 0.0:
			if not effects_advance:
				continue
			effects[id] = maxf(0.0, remaining - seconds)
			if float(effects[id]) > 0.0:
				continue
			start_recovery(id, tree, factor)
			recovery_time = maxf(0.0, seconds - remaining)
		var before := float(tree.cooldowns.get(id, 0.0))
		tree.cooldowns[id] = maxf(0.0, before - recovery_time)
		if before > 0.0 and float(tree.cooldowns[id]) <= 0.0:
			finished.append(id)
	return finished


func report_effect(id: String, duration: float) -> void:
	var running := float(effects.get(id, 0.0)) > 0.0
	effect_totals[id] = maxf(duration, float(effect_totals.get(id, 0.0))) if running else duration
	effects[id] = duration
