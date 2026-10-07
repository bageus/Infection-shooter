extends SceneTree
const FIFO := preload("res://game/presentation/office_floor/blood_mark_fifo.gd")

func _init() -> void:
	var queue := FIFO.new()
	var expected: Array[int] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 29051
	for i in 2000:
		queue.append(i)
		expected.append(i)
		if i % 3 != 0:
			var index := rng.randi_range(0, expected.size() - 1)
			queue.remove(expected[index])
			expected.remove_at(index)
		if queue.first != expected[0]:
			push_error("FIFO diverged after random removal")
			quit(1)
			return
	for id in expected:
		queue.remove(id)
	if queue.first != -1 or not queue.get("_links").is_empty():
		push_error("FIFO retains removed IDs")
		quit(1)
		return
	queue.append(3000)
	queue.remove(3000)
	print("Blood FIFO: random removal, drain and reuse PASS")
	quit()
