extends "res://game/infrastructure/platform/public/platform_adapter.gd"
## Test adapter: the advertisement stays pending for a set number of polls, then ends with `result`.

var result := AD_CLOSED
var polls_until_done := 0
var requests := 0
var _polls := 0


func request_ad() -> void:
	requests += 1
	_polls = 0


func poll_ad() -> String:
	_polls += 1
	return AD_PENDING if _polls <= polls_until_done else result
