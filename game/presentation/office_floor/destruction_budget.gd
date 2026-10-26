extends Node
## Frame budget for the heavy part of a blast. Every prop a grenade breaks used to spawn its
## pieces in the same frame, so a crowded corner froze the game for a fraction of a second.
## Jobs queued here run oldest first until the frame's budget is spent; at least one runs per
## frame, so the queue always drains.

const NAME := "DestructionBudget"
const BUDGET_USEC := 5000

var _jobs: Array[Callable] = []
var _head := 0


## Runs `job` within the budget of `effects`. Without a live effects root it runs on the next idle call.
static func enqueue(effects: Node, job: Callable) -> void:
	if not is_instance_valid(effects) or not effects.is_inside_tree():
		job.call_deferred()
		return
	var queue := effects.get_node_or_null(NAME)
	if queue == null:
		queue = new()
		queue.name = NAME
		effects.add_child(queue)
	queue.call("push", job)


func push(job: Callable) -> void:
	_jobs.append(job)
	set_process(true)


func pending() -> int:
	return _jobs.size() - _head


func _ready() -> void:
	set_process(not _jobs.is_empty())


func _process(_delta: float) -> void:
	var start := Time.get_ticks_usec()
	while _head < _jobs.size():
		var job := _jobs[_head]
		_head += 1
		if job.is_valid():
			job.call()
		if Time.get_ticks_usec() - start >= BUDGET_USEC:
			break
	if _head >= _jobs.size():
		_jobs.clear()
		_head = 0
		set_process(false)
	elif _head >= 64:
		_jobs = _jobs.slice(_head)
		_head = 0
