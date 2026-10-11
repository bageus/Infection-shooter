extends RefCounted


static func configure(weapon: Node3D, model: Node3D, two_handed: bool) -> Node3D:
	var authored_root := find_marker(model, "WeaponRoot")
	if authored_root == null:
		push_error("%s: authored WeaponRoot missing" % weapon.name)
		return null
	normalize_model(model, authored_root)
	if bool(weapon.get("align_authored_grip")):
		var grip := find_marker(authored_root, "Grip_R")
		if grip != null:
			# New kit has +Y up; the existing hand socket expects -Y up.
			var turn := Basis(Vector3.RIGHT, PI)
			model.transform = Transform3D(turn, -(turn * relative_transform(authored_root, grip).origin)) * model.transform
	for required in ["Grip_R", "Muzzle"]:
		if find_marker(authored_root, required) == null:
			push_error("%s: authored %s missing" % [weapon.name, required])
	if find_marker(authored_root, "Grip_L") == null:
		if two_handed:
			push_error("%s: two-hand weapon requires Grip_L" % weapon.name)
		else:
			push_warning("%s: authored Grip_L missing" % weapon.name)
	var authored_muzzle := find_marker(authored_root, "Muzzle")
	var public_muzzle := weapon.get_node_or_null("Muzzle") as Marker3D
	if authored_muzzle != null and public_muzzle != null:
		public_muzzle.transform = relative_transform(weapon, authored_muzzle)
		# These authored GLBs use +X along the barrel; gameplay Marker3D uses -Z.
		public_muzzle.basis = public_muzzle.basis * Basis(Vector3.UP, -PI * 0.5)
	var authored_ejection := find_marker(authored_root, "EjectionPort")
	var public_ejection := weapon.get_node_or_null("EjectionPort") as Marker3D
	if authored_ejection != null and public_ejection != null:
		public_ejection.transform = relative_transform(weapon, authored_ejection)
	return authored_muzzle


static func normalize_model(model: Node3D, authored_root: Node3D) -> void:
	# Imported scene roots can wrap WeaponRoot with a non-identity transform.
	model.transform = relative_transform(model, authored_root).affine_inverse()


static func relative_transform(boundary: Node3D, marker: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var node: Node = marker
	while node != boundary and node != null:
		if node is Node3D:
			result = (node as Node3D).transform * result
		node = node.get_parent()
	return result


static func find_marker(node: Node, marker_name: String) -> Node3D:
	if node.name == marker_name and node is Node3D:
		return node as Node3D
	for child in node.get_children():
		var found := find_marker(child, marker_name)
		if found != null:
			return found
	return null
