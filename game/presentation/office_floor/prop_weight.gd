extends RefCounted
## Item weight and character contact rules (prop_weight_v1, ADR-0032).
##
## Pure functions: the weight of an authored model, whether characters kick it
## aside with their feet or push it with their body, and how fast it may move.
## The physical RigidBody mass stays as authored; these rules only shape the
## velocity a character can give an item. Lighter items travel further/faster.

const GRAVITY := 9.8
## What a strength 1.0 character (the player, ordinary infected) can still move.
const BASE_PUSH_CAPACITY_KG := 22.0
## Fraction of the walking speed a weightless item could reach when pushed.
const PUSH_SPEED_SHARE := 0.7
## Items do not jump to speed; this caps the velocity gained per second.
const PUSH_ACCELERATION := 22.0
const KICK_MAX_KG := 2.0
const KICK_MAX_HEIGHT := 0.45
const KICK_MAX_FOOTPRINT := 0.75
## Feet reach this high above the character's lowest point.
const KICK_REACH_HEIGHT := 0.6

# First matching file-name fragment wins; values are kilograms.
const WEIGHTS := [
	["tablet", 0.6], ["toilet_paper", 0.12], ["white_board_stand", 12.0],
	["vending", 240.0], ["arcade", 150.0], ["server_rack2", 220.0], ["server_rack3", 260.0], ["server_rack", 120.0],
	["frige", 85.0], ["washing_machine", 70.0], ["dishwasher", 45.0], ["water_cooler_bottle_attached", 28.0],
	["water_cooler_bottle", 11.0], ["water_cooler", 14.0], ["coffee_machine", 8.0], ["microwave", 12.0], ["kittle", 1.2],
	["capboard_down_one", 18.0], ["capboard_down", 32.0], ["capboard_up", 16.0], ["sink", 25.0], ["toilet", 30.0],
	["book_case_small", 38.0], ["book_case_with_back_small", 40.0], ["book_case", 65.0], ["bookshelf", 42.0],
	["box_1_metal", 24.0], ["file_cabinet_largest", 75.0], ["file_cabinet_small_with_shelfs", 30.0],
	["file_cabinet_smaller", 18.0], ["file_cabinet_large_shelf", 22.0], ["file_cabinet_small_shelf", 10.0],
	["locker", 45.0], ["drawer_cabinet_mobile", 16.0], ["drawer_cabinet", 22.0], ["file_cabinet", 55.0],
	["cardboard_archive_box", 3.5], ["cardboard_box_closed", 3.0], ["cardboard_box_open", 2.4],
	["cardboard_boxes_1", 1.4], ["cardboard_boxes", 2.2], ["crate_small", 6.0], ["crate_large", 12.0],
	["military_crate", 32.0], ["MFU_2", 55.0], ["MFU", 40.0], ["PC_", 12.0], ["computer_tower", 8.0],
	["computer_mouse", 0.1], ["desk_phone", 0.8], ["keyboard", 0.6], ["lamp", 1.4], ["laptop", 2.0],
	["minipc", 1.0], ["monitor_wide", 7.0], ["monitor3_server", 9.0], ["monitor4_server", 8.0], ["monitor", 5.0],
	["printer", 14.0], ["phone", 0.3], ["conference_chair", 7.0], ["office_chair_2", 11.0], ["office_chair", 8.0],
	["simple_chair", 4.5], ["coffee_table2", 20.0], ["coffee_table", 15.0], ["reception_counter", 140.0],
	["round_dining_table", 35.0], ["table_longest", 150.0], ["table_square_tall", 18.0], ["table_square", 25.0],
	["table_circular", 15.0], ["table", 30.0], ["divider", 90.0], ["office_desk", 60.0], ["board_stand", 25.0],
	["books_alt_2", 3.5], ["books_alt", 3.0], ["books", 5.0], ["book_", 0.6],
	["case_with_money_open", 4.0], ["case_with_money", 3.0], ["casehand_2", 2.0], ["casehand", 1.5],
	["file_binder", 0.8], ["fruit_plate", 0.6], ["fruit", 0.2], ["glass_water_bottle", 0.45], ["water_bottle", 0.4],
	["glass", 0.25], ["mug", 0.35], ["notepad", 0.15], ["office_file", 0.3], ["office_files", 0.6],
	["paper_stack", 1.0], ["paper_towel", 0.3], ["paper", 0.05], ["pencil_box", 0.3], ["pencil_holder", 0.3],
	["pencil", 0.01], ["pen_", 0.02], ["marker", 0.02], ["stapler", 0.25],
	["trash_bin_small", 1.2], ["trash_bin", 2.5], ["camera", 0.6], ["armchair", 35.0], ["beanbag", 6.0],
	["couch_large", 75.0], ["couch", 55.0], ["bamboo", 20.0], ["deco_2", 6.0], ["deco_3", 20.0],
	["deco_plant", 10.0], ["plant_large", 35.0], ["plant_medium", 20.0], ["plant_small", 8.0], ["casing", 0.02],
]


## Weight of a model in kg. Unknown models fall back to a dense-furniture volume estimate.
static func weight_kg(model_file: String, volume: float) -> float:
	var known := known_weight(model_file)
	return known if known > 0.0 else clampf(volume * 60.0, 0.1, 300.0)


## Catalogued weight in kg, or -1 for a model the table does not list.
static func known_weight(model_file: String) -> float:
	for entry in WEIGHTS:
		if str(entry[0]) in model_file:
			return float(entry[1])
	return -1.0


## How much a character of `strength` can move at all.
static func push_capacity(strength: float) -> float:
	return BASE_PUSH_CAPACITY_KG * maxf(strength, 0.0)


static func can_push(weight: float, strength: float) -> bool:
	return weight < push_capacity(strength)


## Top speed of an item pushed by a character walking at `walk_speed`.
## Speed falls steeply with weight, so heavy items creep and light ones slide.
static func push_speed(weight: float, strength: float, walk_speed: float) -> float:
	var capacity := push_capacity(strength)
	if capacity <= 0.0 or weight >= capacity:
		return 0.0
	return walk_speed * PUSH_SPEED_SHARE * pow(1.0 - weight / capacity, 2.0)


## Velocity to add along the push direction this physics step.
static func push_velocity_change(weight: float, strength: float, walk_speed: float, current_along: float, delta: float) -> float:
	var target := push_speed(weight, strength, walk_speed)
	return clampf(target - current_along, 0.0, PUSH_ACCELERATION * delta)


## Light, low items do not block characters: feet kick them aside instead.
static func is_kickable(weight: float, size: Vector3) -> bool:
	return weight <= KICK_MAX_KG and size.y <= KICK_MAX_HEIGHT and maxf(size.x, size.z) <= KICK_MAX_FOOTPRINT


## Horizontal speed a kick gives an item; lighter items fly further.
static func kick_speed(weight: float, strength: float, walk_speed: float) -> float:
	var pace := clampf(walk_speed / 5.0, 0.35, 1.6)
	return clampf(1.1 / sqrt(maxf(weight, 0.04)), 0.45, 4.5) * pace * sqrt(clampf(strength, 0.5, 4.0))
