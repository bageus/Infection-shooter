extends RefCounted
## Material of each model as Vadim specified it on 26.11.2026: bullet cost and hit/fall sounds follow it.
## Models not listed keep the material rules in environment_prop.gd.

const MATERIAL := {
	"metal": [
		"01_duct_rect_straight.glb", "01_duct_rect_elbow.glb", "01_pipe_sewer_floor_elbow.glb", "01_pipe_sewer_floor_straight.glb",
		"01_pipe_sewer_wall_elbow.glb", "01_pipe_water_floor_elbow.glb", "01_pipe_water_floor_straight.glb", "01_pipe_water_wall_straight.glb",
		"02_frige_dented.glb", "02_dishwasher_dented.glb", "02_washing_machine_dented.glb",
		"07_laboratory_table.glb", "07_medical_trolley.glb", "07_operating_table.glb",
		"12_pistol_casing.glb", "12_shotgun_casing.glb", "12_rifle_casing.glb",
		"15_barrel_green.glb", "15_barrel_blue.glb", "15_barrel_rust.glb",
	],
	"wood": [
		"01_wood_slat_partition_destructible.glb", "01_wall_frame_drywall.glb", "01_wall_timber_frame_only.glb",
		"03_book_case.glb", "03_book_case_small.glb", "03_book_case_with_back.glb", "03_book_case_with_back_small.glb",
		"03_bookshelf.glb", "03_file_cabinet_largest.glb", "03_file_cabinet_small_shelf_fancy.glb",
		"03_file_cabinet_small_with_shelfs.glb", "03_file_cabinet_smaller.glb",
	],
	"tech": ["02_microwave_destructible.glb", "02_kittle_destructible.glb", "02_coffee_machine_destructible.glb"],
	"concrete": [
		"07_reception_counter_two_heights.glb", "15_concrete_block.glb", "15_mix_sack.glb",
		"15_pallet_concrete_blocks.glb", "15_pallet_mix_sacks.glb",
	],
}


## Spec material of a model file name, or "" when the spec does not list it.
static func material_of(file: String) -> String:
	for material in MATERIAL:
		if file in MATERIAL[material]:
			return material
	return ""
