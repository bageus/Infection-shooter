extends RefCounted
## Footstep query: is there floor biomass under the foot? Reads the pieces that
## sit directly in the mission container; bootstrap binds the container.

const AUDIO := preload("res://game/presentation/office_floor/biomass_impact_audio.gd")
const PROBE := &"biomass_step_probe"


static func has_biomass_at(container: Node, world_position: Vector3) -> bool:
	if not is_instance_valid(container):
		return false
	for child in container.get_children():
		if child.has_meta("baked_biomass_floor") and child.call("covers", world_position): return true
		if child.get("floor_biomass_baked") == true: continue
		if not child.has_meta("biomass_piece") or str(child.get("surface")) != "floor":
			continue
		if not child.has_meta(PROBE):
			var created := AUDIO.new()
			created.watch(child)
			child.set_meta(PROBE, created)
		var probe: RefCounted = child.get_meta(PROBE)
		if probe.call("covers", world_position, Vector3.UP, "floor"):
			return true
	return false
