extends RefCounted
## Runtime damage rules for one prop. No scenes, rendering or physics dependencies.
const BALANCE := preload("res://game/features/combat/public/projectile_balance.gd")
enum HitAction { NONE, SHUDDER, SCATTER, TRANSITION, CHIP_FACADE, DETACH, PUSH }
enum Transition { NONE, VARIANT, BREAK }
var category := "large"
var health := 0.0
var broken := false
var variant_index := -1
var transition_pending := false
var full_break := false
var short_circuited := false
var paper_torn := false
var extinguisher_triggered := false
var glass_broken := false
var _variant_count := 0
var _has_fragments := false


func configure(model_name: String, variant_count: int, has_fragments: bool) -> void:
	var group := model_name.substr(0, 2)
	category = "tech" if group == "05" else ("small" if group in ["09", "11", "12"] else "large")
	_variant_count = variant_count
	_has_fragments = has_fragments
	health = _stage_health()


func hit(amount: float, weapon: String, book_stack: bool, wall_mounted: bool, anchored: bool, facade: bool) -> HitAction:
	if book_stack and not broken:
		health -= BALANCE.object_damage(amount, weapon, "small")
		if health <= 0.0:
			broken = true
			return HitAction.SCATTER
	elif not broken and not transition_pending and (variant_index + 1 < _variant_count or _has_fragments):
		health -= BALANCE.object_damage(amount, weapon, category)
		if health <= 0.0:
			full_break = weapon == "GRENADE" and _has_fragments
			transition_pending = true
			return HitAction.TRANSITION
		if amount > 0.0 and weapon != "PISTOL":
			return HitAction.SHUDDER
	elif broken and facade:
		return HitAction.CHIP_FACADE
	elif wall_mounted and anchored and not broken:
		health -= BALANCE.object_damage(amount, weapon, category)
		if health <= 0.0:
			broken = true
			return HitAction.DETACH
	elif not anchored:
		return HitAction.PUSH
	return HitAction.NONE


func complete_transition() -> Transition:
	if broken:
		return Transition.NONE
	if variant_index + 1 < _variant_count and not full_break:
		variant_index += 1
		health = _stage_health() * 0.8
		transition_pending = false
		return Transition.VARIANT
	if _has_fragments:
		broken = true
		return Transition.BREAK
	return Transition.NONE


func short_circuit() -> bool:
	if short_circuited:
		return false
	short_circuited = true
	return true


func tear_paper() -> bool:
	if paper_torn:
		return false
	paper_torn = true
	broken = true
	return true


func trigger_extinguisher() -> bool:
	if extinguisher_triggered:
		return false
	extinguisher_triggered = true
	return true


func break_glass() -> bool:
	if glass_broken or broken:
		return false
	glass_broken = true
	return true


func _stage_health() -> float:
	match category:
		"tech": return 65.0
		"small": return 42.0
	return 155.0
