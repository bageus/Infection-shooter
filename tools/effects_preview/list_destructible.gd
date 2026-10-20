extends SceneTree
## Writes destructible_models.json: every planner model that has damage variants or
## breakup groups, by model group, for the effects preview's destruction tab.
##   godot --headless --path . --script res://tools/effects_preview/list_destructible.gd
## Re-run it after adding or changing destructible models.

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const ROOT := "res://models/objects/enviroments/"
# Fixtures that the planner builds from their own scenes rather than the shared prop.
const OWN_SCENE := ["02_toilet_new.glb", "02_wall_urinal_improved.glb", "05_wall_hand_dryer_improved.glb", "02_sink_pedestal_improved.glb", "01_stairs.glb", "01_stairs_2.glb"]
const OUT := "res://tools/effects_preview/destructible_models.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := CATALOG.new()
	var holder := Node3D.new()
	root.add_child(holder)
	var groups := {}
	for number in range(1, 14):
		var group := "%02d" % number
		var found := []
		var files := Array(ResourceLoader.list_directory(ROOT + group)).filter(func(name: String) -> bool: return name.ends_with(".glb"))
		files.sort()
		for file: String in files:
			if file in OWN_SCENE or not str(catalog._environment_scene_for(file)).is_empty():
				continue
			var prop := PROP.instantiate()
			prop.set("model_path", ROOT + group + "/" + file)
			holder.add_child(prop)
			await process_frame
			if not (prop.get("_variants") as Array).is_empty() or not (prop.get("_stages") as Array).is_empty():
				found.append({"name": file.get_basename().substr(3).replace("_", " "), "path": ROOT + group + "/" + file})
			prop.queue_free()
			await process_frame
		if not found.is_empty():
			groups[group] = found
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(groups, "\t") + "\n")
	file.close()
	quit(0)
