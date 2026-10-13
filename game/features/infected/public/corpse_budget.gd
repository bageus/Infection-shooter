extends RefCounted
## Keeps killed infected on the level until their count passes MAX_CORPSES
## (settings: keep_corpses). The oldest retained body is then hidden, so a
## body in view is not removed on a timer while the level stays under budget.

const MAX_CORPSES := 60

## Set from the player's settings. Off keeps the timed sink-and-hide of ADR-0041.
static var keep := false
static var _corpses: Array[Dictionary] = []


## Retains a body: its hitboxes go now, and on_evict hides it and stops its
## physics once it is pushed out.
static func retain(owner: Node, parts: Node, on_evict: Callable) -> void:
	if parts != null:
		parts.call("remove_corpse_hitboxes")
	_prune()
	_corpses.append({"owner": owner, "evict": on_evict})
	while _corpses.size() > MAX_CORPSES:
		var oldest := _corpses.pop_front() as Dictionary
		if is_instance_valid(oldest.owner):
			(oldest.evict as Callable).call()


## Ends a death clip: the body sinks and is hidden, or with keep it is retained.
static func clip_tail(tween: Tween, owner: Node, parts: Node, visual: Node3D, sink_depth: float, hide: Callable) -> void:
	if keep:
		tween.tween_callback(retain.bind(owner, parts, hide))
		return
	tween.tween_property(visual, "position:y", visual.position.y - sink_depth, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(hide)


static func count() -> int:
	_prune()
	return _corpses.size()


static func _prune() -> void:
	_corpses = _corpses.filter(func(entry: Dictionary) -> bool: return is_instance_valid(entry.owner))
