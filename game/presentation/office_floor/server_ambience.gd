extends AudioStreamPlayer3D
## Native positional attenuation; no frame callback for each server rack.

const FAN := preload("res://assets/audio/sfx/coller_server/sound_of_server_oper.ogg")


static func attach(prop: Node3D, model: String) -> void:
	if not model.get_file().begins_with("03_server_rack"):
		return
	var fan := new()
	fan.name = "ServerFans"
	fan.stream = FAN
	fan.bus = &"SFX"
	fan.position = Vector3(0, 1.0, 0)
	fan.volume_db = -5.0
	fan.max_db = 0.0
	fan.unit_size = 1.0
	fan.max_distance = 4.0
	fan.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	fan.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	prop.add_child(fan)
	if DisplayServer.get_name() != "headless":
		fan.play(randf() * FAN.get_length())


static func silence(prop: Node) -> void:
	var fan := prop.get_node_or_null("ServerFans") as AudioStreamPlayer3D
	if fan != null:
		fan.stop()
