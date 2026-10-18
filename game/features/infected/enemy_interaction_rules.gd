extends RefCounted
## Read-only target policy injected by mission composition; defaults preserve combat.
const META := &"enemy_gameplay_modes_v1"


static func ignores(target: Node) -> bool:
	return _flag(target, "ignore_player")


static func damage(target: Node, amount: float) -> void:
	if is_instance_valid(target) and target.has_method("take_damage") and not ignores(target) and not _flag(target, "no_damage"):
		target.call("take_damage", amount)


static func _flag(target: Node, key: String) -> bool:
	if not is_instance_valid(target) or not target.has_meta(META):
		return false
	var policy: Variant = target.get_meta(META)
	return policy is Dictionary and policy.get(key, false) == true
