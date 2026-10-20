extends Node
## Music selection observes confirmed monster hits and public aggression only.
const CALM := preload("res://assets/audio/music/server_oper_active.ogg")
const THREAT := preload("res://assets/audio/music/tower_threat.ogg")
const HUNT := preload("res://assets/audio/music/tower_hunt.ogg")
const MIX := preload("res://game/bootstrap/app/music_crossfade.gd")
const RELEASE_SECONDS := 3.0
var state := &"calm"
var aggression := 0
var _quiet_time := 0.0
var _recent_hit := 0.0
var _poll_time := 0.0
var _battle := false
var _suspended := false
var mixer: MIX


func _ready() -> void:
	name = "MissionMusic"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mixer = MIX.new()
	add_child(mixer)
	mixer.fade_to(CALM)


func _process(delta: float) -> void:
	if _suspended:
		return
	_poll_time += delta
	if _poll_time < 0.25:
		return
	var elapsed := _poll_time
	_poll_time = 0.0
	var count := 0
	for enemy in get_tree().get_nodes_in_group(&"infected_alive"):
		if not enemy.is_queued_for_deletion() and enemy.has_method("is_alerted") and bool(enemy.call("is_alerted")):
			count += 1
	update_aggression(count, elapsed)


func notify_monster_hit(_position: Vector3 = Vector3.ZERO, _direction: Vector3 = Vector3.ZERO, _weapon: String = "", _excluded: Array[RID] = [], _source_id: int = 0) -> void:
	if _suspended:
		return
	_recent_hit = RELEASE_SECONDS
	_quiet_time = 0.0
	_battle = true
	if state == &"calm":
		_select(&"hunt" if aggression > 10 else &"threat")


func update_aggression(count: int, delta: float) -> void:
	aggression = maxi(count, 0)
	if _suspended:
		return
	_recent_hit = maxf(0.0, _recent_hit - maxf(delta, 0.0))
	if aggression > 10:
		_battle = true
		_quiet_time = 0.0
		_select(&"hunt")
		return
	if not _battle:
		return
	if state == &"hunt" and aggression < 10:
		_select(&"threat")
	if aggression > 0 or _recent_hit > 0.0:
		_quiet_time = 0.0
		if state == &"hunt" and aggression < 10:
			_select(&"threat")
		return
	_quiet_time += maxf(delta, 0.0)
	if _quiet_time >= RELEASE_SECONDS:
		_battle = false
		_select(&"calm")


func _select(next: StringName) -> void:
	if state == next:
		return
	var previous := state
	state = next
	if state == &"calm":
		mixer.fade_to(CALM)
	elif state == &"hunt":
		mixer.fade_to(HUNT)
	else:
		# Downgrading an ongoing hunt enters the repeating body, never the intro.
		mixer.fade_to(THREAT, 30.08 if previous == &"hunt" else 0.0)


func finish_mission() -> void:
	_suspended = true
	state = &"complete"
	set_process(false)
	# The completion screen pauses gameplay, but its outgoing music still fades.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mixer.fade_to(null)
