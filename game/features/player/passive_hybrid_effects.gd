extends RefCounted
## Player-owned hybrid clocks, absorption and automatic ammunition conversion.
const B := preload("res://game/features/infection/public/mutation_balance.gd")
var host: Node
var absorption := 0.0
var absorption_left := 0.0
var hyper_left := -1.0
var hyper_cooldown := 0.0
var organic_cooldown := 0.0

func _init(effects: Node) -> void:
	host = effects

func tick(delta: float) -> void:
	hyper_cooldown = maxf(0.0, hyper_cooldown - delta)
	organic_cooldown = maxf(0.0, organic_cooldown - delta)
	absorption_left = maxf(0.0, absorption_left - delta)
	if absorption_left <= 0.0 or not host.enabled("devourer"):
		absorption = 0.0
	if hyper_left >= 0.0:
		var elapsed := minf(delta, hyper_left)
		if host.enabled("hyperactive"):
			host.runtime.call("reduce_skill_cooldowns", elapsed * (B.value("hyperactive", "multiplier") - 1.0))
		hyper_left -= delta
		# At exactly one second the series remains eligible for the next kill.
		if hyper_left < 0.0 or not host.enabled("hyperactive"):
			hyper_cooldown = maxf(0.0, B.value("hyperactive", "cooldown") - maxf(0.0, delta - elapsed))
			hyper_left = -1.0
	_organic_ammo()

func on_kill() -> void:
	if host.enabled("hyperactive") and hyper_cooldown <= 0.0:
		hyper_left = B.value("hyperactive", "gap")
	if host.enabled("killer_instinct"):
		var gun: Node = host.player.call("get_current_weapon")
		gun.call("refill_magazine_from_reserve")
		host._passive_buff("killer_instinct", B.value("killer_instinct", "duration"))

func cloud(delta: float) -> void:
	if not host.enabled("devourer"):
		return
	host.player.call("heal", B.value("devourer", "heal") * delta)
	if float(host.player.get("health")) >= float(host.player.get("max_health")):
		absorption = B.value("devourer", "absorption")
		absorption_left = B.value("devourer", "duration")
	host._passive("devourer")

func absorb(amount: float) -> float:
	if not host.enabled("devourer") or absorption_left <= 0.0:
		return amount
	var taken := minf(amount, absorption)
	absorption -= taken
	if taken > 0.0:
		host.vfx.energy_shield()
	return amount - taken

func hyperactive() -> bool:
	return host.enabled("hyperactive") and hyper_left >= 0.0

func _organic_ammo() -> void:
	if not host.enabled("organic_ammo") or organic_cooldown > 0.0:
		return
	var gun: Node = host.player.call("get_current_weapon")
	# Belt-fed weapons have no magazine and must not generate reserve ammunition.
	if bool(gun.get("direct_reserve_feed")) or int(gun.call("get_magazine_ammo")) > 0:
		return
	var health := float(host.player.get("health"))
	if health <= 0.0:
		return
	if int(gun.call("add_magazine_ammo", int(gun.get("magazine_size")))) <= 0:
		return
	gun.call("cancel_reload")
	if health >= float(host.player.get("max_health")) * B.value("organic_ammo", "threshold") / 100.0:
		host.player.set("health", health - B.value("organic_ammo", "health"))
	organic_cooldown = B.value("organic_ammo", "cooldown")
	host._passive("organic_ammo", organic_cooldown)
