extends RefCounted

const CATALOG := preload("res://game/features/infection/domain/mutation_catalog.gd")

var learned: Dictionary = {}
var locked: Dictionary = {}
var cooldowns: Dictionary = {}


func reconcile(mutation: float) -> bool:
	var changed := false
	for skill_id in learned.keys():
		var row := CATALOG.find(str(skill_id))
		if (row.is_empty() or mutation < CATALOG.threshold(row)) and not locked.has(skill_id):
			learned.erase(skill_id)
			changed = true
	return changed


func points(mutation: float) -> int:
	return maxi(0, int(floor((mutation - 15.0) / 10.0)) - learned.size())


func is_active(skill_id: String, mutation: float) -> bool:
	var row := CATALOG.find(skill_id)
	return learned.has(skill_id) and not row.is_empty() and mutation >= CATALOG.threshold(row)


func can_upgrade(skill_id: String, mutation: float) -> bool:
	var row := CATALOG.find(skill_id)
	if row.is_empty() or points(mutation) <= 0 or mutation < CATALOG.threshold(row) or learned.has(skill_id):
		return false
	var rank := int(row[3])
	if rank > 0 and rank < 3:
		var previous := false
		for candidate in CATALOG.all():
			if candidate[2] == row[2] and int(candidate[3]) == rank - 1 and learned.has(str(candidate[0])):
				previous = true
		if not previous:
			return false
	if rank == 3:
		for parent in CATALOG.HYBRID_PARENTS.get(skill_id, []):
			if not learned.has(parent):
				return false
	return true


func upgrade(skill_id: String, mutation: float) -> bool:
	if not can_upgrade(skill_id, mutation):
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


func cast(skill_id: String, mutation: float) -> bool:
	if not is_active(skill_id, mutation) or float(cooldowns.get(skill_id, 0.0)) > 0.0:
		return false
	var row := CATALOG.find(skill_id)
	if row not in CATALOG.ACTIVE:
		return false
	cooldowns[skill_id] = 10.0
	return true
