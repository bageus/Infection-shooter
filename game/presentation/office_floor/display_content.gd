extends RefCounted

# Shared immutable textures/timing; every display owns its material and frame index.
const STATIC_PATHS: Array[String] = [
	"res://models/objects/textures/display/VECTRION Eight-Screen Research Atlas.png",
	"res://models/objects/textures/display/Vectrion Eight-Screen Mutation Research Atlas.png"]
const ANIMATED_PATHS: Array[String] = [
	"res://models/objects/textures/logo/runtime/intro.png",
	"res://models/objects/textures/logo/runtime/sequence.png",
	"res://models/objects/textures/logo/runtime/symbol_rotation.png"]
const TIMING_PATHS: Array[String] = [
	"res://models/objects/textures/logo/runtime/intro.json",
	"res://models/objects/textures/logo/runtime/sequence.json",
	"res://models/objects/textures/logo/runtime/symbol_rotation.json"]
const SCREEN_SHADER := preload("res://game/presentation/office_floor/display_screen.gdshader")

var textures: Dictionary = {}
var timelines: Dictionary = {}


func material(dynamic: bool, index: int) -> ShaderMaterial:
	@warning_ignore("integer_division")
	var path := ANIMATED_PATHS[index % 3] if dynamic else STATIC_PATHS[index / 8]
	if not textures.has(path):
		textures[path] = load(path)
	var result := ShaderMaterial.new()
	result.shader = SCREEN_SHADER
	result.set_shader_parameter("screen_texture", textures[path])
	result.set_shader_parameter("powered", false)
	result.set_shader_parameter("content_rect", Vector4(0, 0, 1, 1))
	if dynamic:
		result.set_shader_parameter("atlas_rect", frame_rect(index, 0.0))
	else:
		var texture := textures[path] as Texture2D
		var guard := Vector2(.5 / texture.get_width(), .5 / texture.get_height())
		var cell := index % 8
		@warning_ignore("integer_division")
		result.set_shader_parameter("atlas_rect", Vector4((cell % 4) * .25 + guard.x,
			(cell / 4) * .5 + guard.y, .25 - guard.x * 2, .5 - guard.y * 2))
	return result


func timeline(index: int) -> Dictionary:
	index %= 3
	if not timelines.has(index):
		var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TIMING_PATHS[index]))
		var ends: Array[float] = []
		var total := 0.0
		for duration: Variant in parsed["durations"]:
			total += float(duration)
			ends.append(total)
		parsed["ends"] = ends
		parsed["total"] = total
		timelines[index] = parsed
	return timelines[index]


func frame_rect(index: int, seconds: float) -> Vector4:
	var data := timeline(index)
	var time := fposmod(seconds, float(data["total"]))
	var ends: Array = data["ends"]
	var frame := 0
	while frame < ends.size() - 1 and time >= float(ends[frame]):
		frame += 1
	var columns := int(data["columns"])
	var rows := int(data["rows"])
	var cell: Array = data["cell_size"]
	var image: Array = data["frame_size"]
	var width := float(columns * int(cell[0]))
	var height := float(rows * int(cell[1]))
	@warning_ignore("integer_division")
	return Vector4((frame % columns * int(cell[0]) + 1.5) / width,
		(frame / columns * int(cell[1]) + 1.5) / height,
		(float(image[0]) - 1.0) / width, (float(image[1]) - 1.0) / height)
