extends RefCounted
## A distinct signal target per cache entry; never retains the cache owner.
var _owner: WeakRef
var _method: StringName
var _key: int


func _init(owner: RefCounted, method: StringName, key: int) -> void:
	_owner = weakref(owner)
	_method = method
	_key = key


func changed() -> void:
	var owner: RefCounted = _owner.get_ref()
	if owner != null:
		owner.call(_method, _key)
