extends RefCounted
## Player-owned antidote use: checks stock, then applies the infection change.

const SFX := preload("res://game/core/audio/public/sound_events.gd")


func request(player: Node) -> bool:
	if player.antidotes <= 0 and not player.infinite_antidotes:
		SFX.play_ui(player, &"access_denied")
		return false
	var used: bool = player.infection_runtime.use_antidote()
	if used:
		if not player.infinite_antidotes:
			player.antidotes -= 1
		player.play_item_sound(&"antidote_use")
	return used
