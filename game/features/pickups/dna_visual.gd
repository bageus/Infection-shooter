extends Node3D
## Small glowing double helix for the DNA pickup; turns slowly while it lies on the floor.

const RUNGS := 12


func _ready() -> void:
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.3, 0.95, 0.1)
	green.emission_enabled = true
	green.emission = Color(0.15, 0.7, 0.05)
	green.metallic = 0.35
	green.roughness = 0.3
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.78, 0.95, 0.86)
	var bead := SphereMesh.new()
	bead.radius = 0.04
	bead.height = 0.08
	bead.material = green
	var rung := BoxMesh.new()
	rung.size = Vector3(0.26, 0.018, 0.018)
	rung.material = white
	for index in RUNGS:
		var angle := index * 0.65
		var y := 0.06 + index * 0.04
		var offset := Vector3(cos(angle) * 0.13, y, sin(angle) * 0.13)
		for point in [offset, Vector3(-offset.x, y, -offset.z)]:
			var dot := MeshInstance3D.new()
			dot.mesh = bead
			dot.position = point
			add_child(dot)
		var bar := MeshInstance3D.new()
		bar.mesh = rung
		bar.position.y = y
		bar.rotation.y = -angle
		add_child(bar)


func _process(delta: float) -> void:
	rotation.y += delta * 0.8
