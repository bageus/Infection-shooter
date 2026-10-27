extends RefCounted
## Base platform adapter: no SDK, no advertisements. Subclasses override what the platform offers.

const AD_PENDING := ""
const AD_CLOSED := "closed"
const AD_FAILED := "failed"


func start() -> void:
	pass


## Begin a fullscreen advertisement. Platforms without ads leave it failed at once.
func request_ad() -> void:
	pass


## Returns AD_PENDING while the advertisement is open, then AD_CLOSED or AD_FAILED.
func poll_ad() -> String:
	return AD_FAILED
