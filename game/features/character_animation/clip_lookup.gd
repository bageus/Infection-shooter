extends RefCounted
## Finds a clip by name token among the normalized names the driver indexed
## (lower case, underscores for spaces and dashes -> original clip name).


## A random clip named token or token + digits (AttackLeft, AttackLeft2).
static func variant(animations: Dictionary, token: String) -> String:
	var found: Array[String] = []
	for normalized: String in animations:
		var squashed := normalized.replace("_", "")
		if squashed.begins_with(token) and squashed.substr(token.length()).is_valid_int() or squashed == token:
			found.append(animations[normalized])
	return found[randi() % found.size()] if not found.is_empty() else ""


## Exact normalized match first, then the shortest clip containing the token.
## Clips naming one of `blocked` are skipped unless the token names it too.
static func find(animations: Dictionary, blocked: Array, tokens: Array) -> String:
	for token: String in tokens:
		for normalized: String in animations:
			var squashed := normalized.replace("_", "")
			if squashed == token and not _is_excluded(blocked, normalized, token):
				return animations[normalized]
		var best := ""
		var best_length := 9999
		for normalized: String in animations:
			var squashed := normalized.replace("_", "")
			if token in squashed and not _is_excluded(blocked, normalized, token) and normalized.length() < best_length:
				best = animations[normalized]
				best_length = normalized.length()
		if not best.is_empty():
			return best
	return ""


static func _is_excluded(blocked: Array, normalized: String, token: String) -> bool:
	for word: String in blocked:
		if word in normalized and word not in token:
			return true
	return false
