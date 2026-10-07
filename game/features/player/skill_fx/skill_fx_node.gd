extends Node3D
## One procedural skill effect: counts its age, hands the age and a fade
## factor to its animation step every frame and frees itself when done. An
## open-ended effect (life = INF) runs until stop().

var life := 1.0
var fade_in := 0.0
var fade_out := 0.0
## step.call(age: float, fade: float)
var step: Callable
var _age := 0.0


## Fades the effect out over `seconds` and frees it.
func stop(seconds: float = 0.3) -> void:
	fade_out = maxf(seconds, 0.01)
	life = minf(life, _age + fade_out)


func _process(delta: float) -> void:
	# A long hitch (first-use shader compile) must not skip a whole flash.
	_age += minf(delta, 0.1)
	if _age >= life:
		queue_free()
		return
	var fade := 1.0
	if fade_in > 0.0:
		fade = clampf(_age / fade_in, 0.0, 1.0)
	if is_finite(life) and fade_out > 0.0:
		fade *= clampf((life - _age) / fade_out, 0.0, 1.0)
	if step.is_valid():
		step.call(_age, fade)
