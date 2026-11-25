extends RefCounted
## Runtime damage rules for one prop. No scenes, rendering or physics dependencies.
const BALANCE := preload("res://game/features/combat/public/projectile_balance.gd")
enum HitAction { NONE, SHUDDER, SCATTER, TRANSITION, CHIP_FACADE, DETACH, PUSH, COLLAPSE }
## Broken 04 crates: one shotgun blast, two or three AK/M4/UZI shots, one minigun or sniper shot; pistols do nothing.
const BROKEN_CRATE_HEALTH := 70.0
enum Transition { NONE, VARIANT, BREAK }
const BIG_CRATES := ["04_crate_wood_large.glb"]
## Props no blow breaks: loaded pallets are solid stacks, kept whole like the tarp-covered crate;
## vending machines and white goods are kept whole too (their dent and break stages were removed).
const INDESTRUCTIBLE := [
	"15_pallet_drywall_flat_full.glb", "15_pallet_concrete_blocks_double.glb",
	"02_vending_automat_1_dented.glb", "02_vending_automat_2_dented.glb", "02_vending_machine_fantas_dented.glb",
	"02_coffee_vending_1_dented.glb", "02_frige_dented.glb", "02_dishwasher_dented.glb", "02_washing_machine_dented.glb",
	# Lab equipment: cabinets, tanks and scanners that no blow breaks (the fridge's front glass breaks on its own).
	"MRI_Scanner.glb", "X_Ray_System.glb", "Hyperbaric_Chamber.glb", "Medical_Instrument_Cabinet.glb",
	"Laboratory_Storage_Cabinet.glb", "Laboratory_Drying_Cabinet.glb", "Morgue_Drawers_3x3.glb",
	"Laboratory_Fridge.glb", "Containment_Tank_No_Subject.glb", "Containment_Tank_hunger.glb",
]
## Appliances whose electronics break from Low (microwave, coffee machine, arcade cabinets).
const ELECTRONICS_02 := ["02_microwave_destructible.glb", "02_coffee_machine_destructible.glb", "02_arcade_machine_V1.glb", "02_arcade_machine_V2.glb", "02_arcade_machine_V3.glb", "02_arcade_machine_V4.glb", "02_arcade_machine_V5.glb", "02_arcade_machine_V6.glb"]
## Glassware that breaks whole on its first hit (mirrors fragile_prop.gd is_glassware).
const GLASSWARE := ["09_glass.glb", "09_glass_2.glb", "Laboratory_Flasks_Set.glb", "Test_Tube_Rack.glb"]
## Lab files are not named with a group prefix, so their electronics are listed by name.
const LAB_ELECTRONICS := [
	"Laboratory_Autoclave.glb", "Laboratory_Balance.glb", "Laboratory_Microscope.glb", "Medical_Lab_Oven.glb",
	"MRI_Scanner.glb", "Patient_Monitor_Stand.glb", "Vortex_Mixer.glb", "X_Ray_System.glb",
]
var category := "large"
var health := 0.0
var broken := false
var variant_index := -1
var transition_pending := false
var full_break := false
var collapses := false # Cardboard and big crates: no staged pieces, so they break apart on their own.
var indestructible := false
var short_circuited := false
var paper_torn := false
var extinguisher_triggered := false
var glass_broken := false
var _variant_count := 0
var _has_fragments := false


## Lowest destruction quality level (0 Low, 1 Medium, 2 High) at which a prop breaks.
## Low breaks electronics, chairs, boxes, every crate (loot crates break at all levels) and
## breakable glass; Medium adds cabinets, tables, sofas, partitions and dividers; High breaks the rest.
static func breaks_from_level(model_name: String) -> int:
	var group := model_name.substr(0, 2)
	if group == "05" or group == "06" or model_name in LAB_ELECTRONICS or model_name in ELECTRONICS_02:
		return 0
	if model_name in GLASSWARE or model_name.begins_with("09_glass_water_bottle") or model_name.begins_with("09_mug") or model_name.begins_with("09_fruit_plate"):
		return 0
	if group == "01" and "glass" in model_name and "breakable" in model_name:
		return 0
	if group == "04":
		return 0
	if "box" in model_name:
		return 0
	if group in ["03", "07", "08", "10"] or model_name == "01_wood_slat_partition_destructible.glb":
		return 1
	if group == "02" and "capboard" in model_name:
		return 1
	return 2


func configure(model_name: String, variant_count: int, has_fragments: bool, quality: int = 2) -> void:
	var group := model_name.substr(0, 2)
	category = "tech" if group == "05" or model_name in LAB_ELECTRONICS else ("small" if group in ["09", "11", "12"] else "large")
	_variant_count = variant_count
	_has_fragments = has_fragments
	collapses = not has_fragments and (model_name.to_lower().contains("cardboard") or model_name in BIG_CRATES)
	health = BROKEN_CRATE_HEALTH if model_name.begins_with("04_crate") else _stage_health()
	indestructible = model_name in INDESTRUCTIBLE or quality < breaks_from_level(model_name)


func hit(amount: float, weapon: String, book_stack: bool, wall_mounted: bool, anchored: bool, facade: bool) -> HitAction:
	if indestructible:
		return HitAction.NONE
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
	elif not broken and collapses:
		health -= BALANCE.object_damage(amount, weapon, category)
		if health <= 0.0:
			broken = true
			return HitAction.COLLAPSE
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


## Fragile items break whole on their first hit, whatever the weapon.
func shatter() -> bool:
	if broken:
		return false
	broken = true
	return true


func _stage_health() -> float:
	match category:
		"tech": return 65.0
		"small": return 42.0
	return 155.0
