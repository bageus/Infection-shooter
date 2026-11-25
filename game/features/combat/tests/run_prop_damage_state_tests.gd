extends SceneTree
const STATE := preload("res://game/features/combat/public/prop_damage_state.gd")
var failures := 0


func _initialize() -> void:
	_categories_and_balance()
	_variant_progression()
	_grenade_and_pending()
	_special_objects()
	_quality_tiers()
	print("Prop damage state tests: %d failures" % failures)
	quit(failures)


func _categories_and_balance() -> void:
	for pair in [["05_PC.glb", "tech", 65.0], ["09_mug.glb", "small", 42.0], ["12_book.glb", "small", 42.0], ["03_cabinet.glb", "large", 155.0]]:
		var state := STATE.new()
		state.configure(pair[0], 1, true)
		_check(state.category == pair[1] and is_equal_approx(state.health, pair[2]), "Original category and health: " + pair[0])
	var cabinet := STATE.new()
	cabinet.configure("03_cabinet.glb", 1, true)
	_check(cabinet.hit(200.0, "PISTOL", false, false, false, false) == STATE.HitAction.NONE and cabinet.health == 155.0, "Pistol cannot damage a large prop")
	cabinet.hit(20.0, "SHOTGUN", false, false, false, false)
	_check(is_equal_approx(cabinet.health, 140.0), "Shotgun object multiplier remains 0.75")
	cabinet.hit(20.0, "UZI", false, false, false, false)
	_check(is_equal_approx(cabinet.health, 122.0), "Uzi object multiplier remains 0.9")


func _variant_progression() -> void:
	var state := STATE.new()
	state.configure("05_PC.glb", 2, true)
	for index in 2:
		_check(state.hit(100.0, "UZI", false, false, false, false) == STATE.HitAction.TRANSITION, "Exhausted health requests a visual transition")
		_check(state.complete_transition() == STATE.Transition.VARIANT and state.variant_index == index, "Damage variants advance in the authored order")
		_check(not state.broken and not state.transition_pending and is_equal_approx(state.health, 52.0), "Each variant restores 80 percent of stage health")
	state.hit(100.0, "UZI", false, false, false, false)
	_check(state.complete_transition() == STATE.Transition.BREAK and state.broken, "Fragments follow the last damage variant")
	_check(state.complete_transition() == STATE.Transition.NONE, "A broken prop cannot transition twice")
	_check(state.hit(1.0, "UZI", false, false, true, true) == STATE.HitAction.CHIP_FACADE, "A broken facade still accepts localized chipping")


func _grenade_and_pending() -> void:
	var state := STATE.new()
	state.configure("03_cabinet.glb", 3, true)
	state.hit(200.0, "GRENADE", false, false, false, false)
	var exhausted := state.health
	_check(state.hit(200.0, "UZI", false, false, false, false) == STATE.HitAction.PUSH and state.health == exhausted, "Hits arriving before deferred transition do not consume another stage")
	_check(state.full_break and state.complete_transition() == STATE.Transition.BREAK and state.variant_index == -1, "Grenade bypasses variants when fragments exist")
	var variant_only := STATE.new()
	variant_only.configure("05_monitor.glb", 1, false)
	variant_only.hit(100.0, "GRENADE", false, false, false, false)
	_check(variant_only.complete_transition() == STATE.Transition.VARIANT and not variant_only.broken, "Grenade preserves the last visual variant when no fragments exist")


func _special_objects() -> void:
	var stack := STATE.new()
	stack.configure("12_book_stack.glb", 0, false)
	_check(stack.hit(60.0, "SHOTGUN", true, false, false, false) == STATE.HitAction.SCATTER and stack.broken, "Book stacks scatter at their existing small-object threshold")
	var mount := STATE.new()
	mount.configure("13_panel.glb", 0, false)
	_check(mount.hit(100.0, "UZI", false, true, true, false) == STATE.HitAction.NONE and not mount.broken, "Wall mount stays anchored below its damage threshold")
	_check(mount.hit(100.0, "UZI", false, true, true, false) == STATE.HitAction.DETACH and mount.broken, "Wall mount detaches at its original damage threshold")
	var effects := STATE.new()
	_check(effects.short_circuit() and not effects.short_circuit(), "First electronic hit short-circuits exactly once")
	_check(effects.trigger_extinguisher() and not effects.trigger_extinguisher(), "Extinguisher triggers exactly once")
	_check(effects.break_glass() and not effects.break_glass(), "Glass shatters exactly once")
	_check(effects.tear_paper() and effects.broken and not effects.tear_paper(), "Paper tears and becomes broken exactly once")


func _quality_tiers() -> void:
	var low := 0
	var medium := 1
	var high := 2
	for name in ["05_PC.glb", "06_office_chair.glb", "04_cardboard_box_closed.glb", "04_crate_small_broken.glb", "09_glass.glb", "09_mug.glb", "01_glass_door_breakable.glb", "03_box_1_metal_dented.glb"]:
		_check(STATE.breaks_from_level(name) == low, "Low breaks " + name)
	for name in ["03_cabinet.glb", "07_table.glb", "08_divider_full_H.glb", "01_wood_slat_partition_destructible.glb", "04_crate_wood_large.glb"]:
		_check(STATE.breaks_from_level(name) == medium, "Medium adds " + name)
	for name in ["09_book_big.glb", "10_couch_flat.glb", "15_barrel_blue.glb", "11_deco_plant.glb"]:
		_check(STATE.breaks_from_level(name) == high, "High only: " + name)
	var table := STATE.new()
	table.configure("07_table.glb", 1, true, low)
	_check(table.indestructible and table.hit(500.0, "GRENADE", false, false, false, false) == STATE.HitAction.NONE and not table.broken, "A table stays intact at Low, even to a grenade")
	var divider := STATE.new()
	divider.configure("08_divider_full_H.glb", 1, true, medium)
	_check(not divider.indestructible and divider.hit(500.0, "GRENADE", false, false, false, false) == STATE.HitAction.TRANSITION, "A divider breaks at Medium")
	var chair := STATE.new()
	chair.configure("06_office_chair.glb", 0, true, low)
	_check(not chair.indestructible, "A chair breaks at Low")
	var default_table := STATE.new()
	default_table.configure("07_table.glb", 1, true)
	_check(not default_table.indestructible, "Without a quality level a prop breaks as at High")


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
