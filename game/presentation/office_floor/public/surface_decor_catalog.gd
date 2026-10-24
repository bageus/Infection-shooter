extends RefCounted
## Read-only authored stamp catalogue; uses the existing planner_decor_v1 texture string.
const ATLASES := preload("res://game/presentation/office_floor/debris_atlases.gd")
const SCENE := "res://game/presentation/office_floor/public/props/blood_decal.tscn"
const FLOOR_MATERIALS := ["glass", "wood", "extinguisher", "plastic", "fabric", "paper", "cardboard"]
const LABELS := {"glass": "Стекло", "wood": "Дерево", "extinguisher": "Огнетушитель", "plastic": "Пластик", "fabric": "Ткань", "paper": "Бумага", "cardboard": "Картон",
	"glass_fracture": "Трещины", "glass_impact": "Удары по стеклу", "floor_damage": "Повреждения пола", "floor_scuff": "Потёртости пола", "wall_damage": "Повреждения стен", "wall_scuff": "Потёртости стен", "bullet": "Следы попаданий"}


static func entries(category: String, material: String = "all") -> Array:
	var kinds: Array = []
	match category:
		"glass": kinds = ["glass_fracture", "glass_impact"]
		"walls": kinds = ["wall_damage", "wall_scuff", "bullet"]
		"floor": kinds = ["floor_damage", "floor_scuff"] + FLOOR_MATERIALS if material == "all" else [material]
	var result: Array = []
	for kind: String in kinds:
		for index in ATLASES.frame_count(kind):
			result.append({"name": "%s %02d" % [LABELS.get(kind, kind), index + 1], "path": SCENE, "kind": "blood", "blood_texture": "surface:%s:%d" % [kind, index]})
	return result


static func texture_entry(id: String) -> Dictionary:
	if not id.begins_with("surface:") or id.split(":").size() != 3:
		return {}
	var kind := id.get_slice(":", 1)
	var index_text := id.get_slice(":", 2)
	if not index_text.is_valid_int():
		return {}
	var index := int(index_text)
	if index < 0 or index >= ATLASES.frame_count(kind):
		return {}
	var definitions: Array = ATLASES.DEFINITIONS.get(kind, ATLASES.SURFACE_DEFINITIONS.get(kind, []))
	for definition: Array in definitions:
		var columns: int = definition[1]
		var rows: int = definition[2]
		if index >= columns * rows:
			index -= columns * rows
			continue
		var source := load(str(definition[0])) as Texture2D
		if source == null:
			return {}
		var cell := Vector2(source.get_size()) / Vector2(columns, rows)
		var texture := AtlasTexture.new()
		texture.atlas = source
		texture.region = Rect2(Vector2(index % columns, floori(float(index) / columns)) * cell + Vector2.ONE * 0.5, cell - Vector2.ONE)
		texture.filter_clip = true
		return {"texture": texture, "aspect": cell.x / cell.y, "roughness": ATLASES.ROUGHNESS.get(kind, 0.85)}
	return {}
