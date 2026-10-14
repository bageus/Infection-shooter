extends RefCounted
## Player-owned request/confirm use case; bootstrap presents the confirmation.
var pending: Dictionary = {}


func request(player: Node) -> bool:
	if player.antidotes <= 0 and not player.infinite_antidotes:
		return false
	var preview: Dictionary = player.infection_runtime.antidote_preview()
	if not preview.can_use or (not preview.emergency and not pending.is_empty()):
		return false
	if not preview.emergency and (not preview.forgotten.is_empty() or not preview.dormant.is_empty()):
		pending = preview.duplicate(true)
		player.antidote_confirmation_requested.emit(preview)
		return false
	pending.clear()
	return apply(player)


func confirm(player: Node) -> bool:
	var same: bool = not pending.is_empty() and pending == player.infection_runtime.antidote_preview()
	pending.clear()
	return apply(player) if same else false


func cancel() -> void:
	pending.clear()


func apply(player: Node) -> bool:
	if player.antidotes <= 0 and not player.infinite_antidotes:
		return false
	var used: bool = player.infection_runtime.use_antidote()
	if used:
		if not player.infinite_antidotes:
			player.antidotes -= 1
		player.play_item_sound(&"antidote_use")
	return used
