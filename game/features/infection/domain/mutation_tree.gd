extends RefCounted

const CATALOG := preload("res://game/features/infection/domain/mutation_catalog.gd")

var learned: Dictionary = {}
var locked: Dictionary = {}
var cooldowns: Dictionary = {}


func reconcile(mutation: float) -> bool:
	var changed := false
	var protected: Dictionary = {}
	for skill_id in locked.keys():
		if not learned.has(skill_id):
			continue
		var locked_row := CATALOG.find(str(skill_id))
		if locked_row.is_empty():
			continue
		for parent in _branch_rows(locked_row):
			if parent[2] == locked_row[2] and int(parent[3]) < int(locked_row[3]):
				protected[str(parent[0])] = true
		for parent_id in CATALOG.HYBRID_PARENTS.get(str(skill_id), []):
			protected[str(parent_id)] = true
			var parent_row := CATALOG.find(str(parent_id))
			for ancestor in _branch_rows(parent_row):
				if ancestor[2] == parent_row[2] and int(ancestor[3]) < int(parent_row[3]):
					protected[str(ancestor[0])] = true
	for skill_id in learned.keys():
		var row := CATALOG.find(str(skill_id))
		if (row.is_empty() or mutation < CATALOG.threshold(row)) and not locked.has(skill_id) and not protected.has(skill_id):
			learned.erase(skill_id)
			locked.erase(skill_id)
			changed = true
	# Repair old or imported progress that skipped a prerequisite.
	for rows in [CATALOG.ACTIVE, CATALOG.PASSIVE]:
		for row in rows:
			if int(row[3]) <= 0 or int(row[3]) >= 3 or not learned.has(str(row[0])):
				continue
			if not _has_previous(row, rows):
				learned.erase(str(row[0]))
				locked.erase(str(row[0]))
				changed = true
	for hybrid_id in CATALOG.HYBRID_PARENTS:
		if not learned.has(hybrid_id):
			continue
		for parent_id in CATALOG.HYBRID_PARENTS[hybrid_id]:
			if not learned.has(parent_id):
				learned.erase(hybrid_id)
				locked.erase(hybrid_id)
				changed = true
				break
	return changed


func points(mutation: float) -> int:
	return maxi(0, CATALOG.point_budget(mutation) - learned.size())


func is_active(skill_id: String, mutation: float, stability: float = 30.0) -> bool:
	var row := CATALOG.find(skill_id)
	return learned.has(skill_id) and not row.is_empty() and mutation >= CATALOG.threshold(row) and stability >= CATALOG.required_stability(row)


func can_upgrade(skill_id: String, mutation: float, stability: float = 30.0) -> bool:
	var row := CATALOG.find(skill_id)
	if row.is_empty() or points(mutation) <= 0 or mutation < CATALOG.threshold(row) or learned.has(skill_id) or stability < CATALOG.required_stability(row):
		return false
	var rank := int(row[3])
	if rank > 0 and rank < 3 and not _has_previous(row, _branch_rows(row)):
		return false
	if rank == 3:
		for parent in CATALOG.HYBRID_PARENTS.get(skill_id, []):
			if not learned.has(parent):
				return false
	return true


func _branch_rows(row: Array) -> Array:
	return CATALOG.ACTIVE if row in CATALOG.ACTIVE else CATALOG.PASSIVE


func _has_previous(row: Array, rows: Array) -> bool:
	for candidate in rows:
		if candidate[2] == row[2] and int(candidate[3]) == int(row[3]) - 1:
			return learned.has(str(candidate[0]))
	return false


func upgrade(skill_id: String, mutation: float, stability: float = 30.0) -> bool:
	if not can_upgrade(skill_id, mutation, stability):
		return false
	learned[skill_id] = true
	return true


func toggle_lock(skill_id: String) -> bool:
	if not learned.has(skill_id):
		return false
	if locked.has(skill_id):
		locked.erase(skill_id)
	else:
		locked[skill_id] = true
	return true


func tick(delta: float) -> void:
	for skill_id in cooldowns.keys():
		cooldowns[skill_id] = maxf(0.0, float(cooldowns[skill_id]) - delta)


func cast(skill_id: String, mutation: float, stability: float = 30.0) -> bool:
	if not is_active(skill_id, mutation, stability) or float(cooldowns.get(skill_id, 0.0)) > 0.0:
		return false
	var row := CATALOG.find(skill_id)
	if row not in CATALOG.ACTIVE:
		return false
	cooldowns[skill_id] = 10.0
	return true
