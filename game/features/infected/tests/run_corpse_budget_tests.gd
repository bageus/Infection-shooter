extends SceneTree
## Corpse budget (keep_corpses): bodies stay until MAX_CORPSES, then the oldest is evicted.

const BUDGET := preload("res://game/features/infected/public/corpse_budget.gd")

var failures := 0
var evicted: Array[int] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_keeps_up_to_limit()
	_test_evicts_oldest_first()
	_test_freed_bodies_leave_budget()
	_test_retained_body_survives_cloud_end()
	print("Corpse budget tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _body(index: int) -> Node3D:
	var body := Node3D.new()
	root.add_child(body)
	body.set_meta("index", index)
	return body


func _evict_callable(body: Node3D) -> Callable:
	return func() -> void: evicted.append(body.get_meta("index"))


func _test_keeps_up_to_limit() -> void:
	evicted.clear()
	BUDGET._corpses.clear()
	for i in BUDGET.MAX_CORPSES:
		var body := _body(i)
		BUDGET.retain(body, null, _evict_callable(body))
	_check(BUDGET.count() == BUDGET.MAX_CORPSES, "Bodies up to the limit are all kept")
	_check(evicted.is_empty(), "Nothing is evicted at the limit")


func _test_evicts_oldest_first() -> void:
	var body := _body(BUDGET.MAX_CORPSES)
	BUDGET.retain(body, null, _evict_callable(body))
	_check(evicted == [0], "The oldest body is evicted when the limit is passed")
	_check(BUDGET.count() == BUDGET.MAX_CORPSES, "Count stays at the limit after eviction")


func _test_freed_bodies_leave_budget() -> void:
	evicted.clear()
	BUDGET._corpses.clear()
	var first := _body(100)
	BUDGET.retain(first, null, _evict_callable(first))
	first.free()
	_check(BUDGET.count() == 0, "A freed body no longer counts against the budget")
	var second := _body(101)
	BUDGET.retain(second, null, _evict_callable(second))
	_check(BUDGET.count() == 1 and evicted.is_empty(), "Adding after a free does not evict anything")
	BUDGET._corpses.clear()


func _test_retained_body_survives_cloud_end() -> void:
	BUDGET.keep = true
	var body := _body(200)
	BUDGET.cloud_gone(body, true)
	_check(is_instance_valid(body), "A shown body survives its death cloud ending while kept")
	BUDGET.hidden(body, null)
	_check(is_instance_valid(body), "Hiding a body whose cloud has ended frees it on the next frame only")
	BUDGET.keep = false
	var gone := _body(201)
	BUDGET.cloud_gone(gone, true)
	_check(not is_instance_valid(gone) or gone.is_queued_for_deletion(), "Without keep the cloud ending frees the body")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
