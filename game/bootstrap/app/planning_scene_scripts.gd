extends RefCounted
## Remove redundant script overrides emitted by PackedScene.pack for instances.
## The public scene already supplies the same script; authored overrides stay.

static func canonicalize(path: String) -> Error:
	var text := FileAccess.get_file_as_string(path)
	var resources: Dictionary = {}
	var declaration := RegEx.create_from_string('^\\[ext_resource type="([^"]+)" path="([^"]+)" id="([^"]+)"\\]$')
	var instance := RegEx.create_from_string('instance=ExtResource\\("([^"]+)"\\)')
	var binding := RegEx.create_from_string('^script = ExtResource\\("([^"]+)"\\)$')
	var lines := text.split("\n")
	for line in lines:
		var match := declaration.search(line)
		if match != null:
			resources[match.get_string(3)] = match.get_string(2)
	var scripts: Dictionary = {}
	var inherited_script: Script
	var redundant: Dictionary = {}
	for index in lines.size():
		var line := lines[index]
		if line.begins_with("[node "):
			inherited_script = null
			var match := instance.search(line)
			if match != null and resources.has(match.get_string(1)):
				var scene_path := str(resources[match.get_string(1)])
				if not scripts.has(scene_path):
					scripts[scene_path] = _scene_script(scene_path)
				inherited_script = scripts[scene_path]
		var override := binding.search(line)
		if override != null and inherited_script != null:
			var id := override.get_string(1)
			if resources.get(id, "") == inherited_script.resource_path:
				lines[index] = ""
				redundant[id] = true
	text = "\n".join(lines)
	for id: String in redundant:
		if not text.contains('ExtResource("%s")' % id):
			for line in lines:
				var match := declaration.search(line)
				if match != null and match.get_string(3) == id:
					text = text.replace(line + "\n", "")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	return file.get_error()


static func _scene_script(path: String) -> Script:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var original := packed.instantiate()
	var script := original.get_script() as Script
	original.free()
	return script
