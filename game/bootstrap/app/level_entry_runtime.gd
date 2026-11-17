extends Node3D
## Level chain at play time: watches the player for a used entry point and shows
## the entry markers of the selected chain map while planning.

const LEVEL_CHAIN := preload("res://game/bootstrap/app/level_chain.gd")
const PANEL := preload("res://game/bootstrap/app/level_constructor_panel.gd")
const CHECK_INTERVAL := 0.2

var chain: RefCounted = LEVEL_CHAIN.new()
var marker_map := ""
var _main: Node
var _player: Node3D
var _planner: Node
var _markers: Array[Label3D] = []
var _panel: RefCounted
var _elapsed := 0.0
## Resources each chain map was first entered with; a restart returns the player to them.
var _entry_carries := {}


func setup(main: Node, player: Node3D, planner: Node) -> void:
	_main = main
	_player = player
	_planner = planner
	chain.load_file()
	_panel = PANEL.new()
	_panel.build(self, planner)
	refresh_markers()


func _process(delta: float) -> void:
	var planning: bool = _planner.active
	for marker in _markers:
		marker.visible = planning
	_elapsed += delta
	if planning or _elapsed < CHECK_INTERVAL or not is_instance_valid(_player):
		return
	_elapsed = 0.0
	var index: int = chain.index_of(str(_main.get("current_level")))
	var slot: int = chain.triggered_slot(index, _player.global_position.x, _player.global_position.z, _player.global_position.y)
	if slot >= 0:
		travel(index, slot)


## Called once a map is set up: its first setup is the state a restart brings back.
func note_entry() -> void:
	var map_name := str(_main.get("current_level"))
	if not _entry_carries.has(map_name):
		_entry_carries[map_name] = _live_carry()


## Resources a chain travel carries; a restart passes restore=true to get the first-entry state.
func carry_for(map_name: String, restore: bool) -> Dictionary:
	return _entry_carries.get(map_name, _live_carry()).duplicate(true) if restore else _live_carry()


func _live_carry() -> Dictionary:
	var runtime: Node = _main.get("infection_runtime")
	return {"loadout": _player.call("export_loadout"), "threshold": runtime.call("get_critical_threshold"), "control": runtime.call("export_control_progress")}


func travel(index: int, slot: int) -> void:
	if slot != LEVEL_CHAIN.FORWARD_SLOT:
		return
	_main.call("travel_to_level", chain.neighbour(index, slot), chain.arrival(index, slot))


func refresh_markers() -> void:
	for marker in _markers:
		marker.queue_free()
	_markers.clear()
	var index: int = chain.index_of(marker_map)
	if index < 0:
		return
	for slot in LEVEL_CHAIN.SLOT_COUNT:
		var item: Dictionary = chain.entry(index, slot)
		if item.type == "none" or not item.placed:
			continue
		var marker := Label3D.new()
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		marker.fixed_size = true
		marker.pixel_size = 0.0009
		marker.font_size = 28
		marker.outline_size = 10
		var target: String = chain.neighbour(index, slot)
		marker.text = "ENTRY %d %s -> %s" % [slot + 1, "UP" if item.type == "ceiling" else "DOWN", target if not target.is_empty() else "(no map)"]
		marker.modulate = Color(0.4, 0.9, 1.0) if not target.is_empty() else Color(1.0, 0.6, 0.3)
		marker.visible = false
		add_child(marker)
		marker.global_position = Vector3(float(item.x), 1.2, float(item.z))
		_markers.append(marker)
