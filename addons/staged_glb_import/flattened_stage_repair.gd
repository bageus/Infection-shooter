@tool
extends RefCounted
## Recover exported stage membership when empty scenes accompany loose authored parts.
## Only known whole-model roots qualify; ordinary single-scene props are untouched.
const WHOLE_ROOTS := ["intact", "receptioncounter", "chair", "tabledestructible_top", "partitiondestructible_part_001"]

static func scenes_for(state: GLTFState, scenes: Array) -> Array:
	var filled: Array = scenes.filter(func(scene: Dictionary) -> bool: return not scene.get("nodes", []).is_empty())
	if filled.size() != 1 or not scenes.any(func(scene: Dictionary) -> bool: return str(scene.get("name", "")).split(".")[0] == "LargeParts"):
		return scenes
	var roots: Array = filled[0].get("nodes", [])
	if roots.size() < 2:
		return scenes # Empty stage labels alone do not supply destruction geometry.
	var nodes := state.get_nodes()
	var first := str(nodes[int(roots[0])].original_name).to_lower().split(".")[0]
	if first not in WHOLE_ROOTS:
		return scenes
	var intact: Array[int] = [int(roots[0])]
	var parts: Array[int] = []
	var fragments: Array[int] = []
	var power_off: Array[int] = []
	for raw_index in roots.slice(1):
		var index := int(raw_index)
		var node := nodes[index]
		var label := str(node.original_name).to_lower()
		if label == "power_off":
			power_off.append(index)
		elif "_fragment_" in label:
			fragments.append(index)
		elif node.mesh >= 0:
			parts.append(index)
		else:
			intact.append(index) # Non-rendering authored attachment anchors.
	if parts.is_empty():
		return scenes
	var repaired: Array = [{"name": "Intact", "nodes": intact}, {"name": "LargeParts", "nodes": parts}]
	if not fragments.is_empty():
		repaired.append({"name": "SmallFragments", "nodes": fragments})
	if not power_off.is_empty():
		repaired.append({"name": "Power_Off", "nodes": power_off})
	state.json["scene"] = 0
	return repaired
