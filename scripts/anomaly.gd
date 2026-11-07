extends Node3D

var game: Node3D
var anomaly_id := ""
var title := ""
var body := ""
var accent_color := Color("7de0d2")
var scan_time := 1.8
var scan_range := 55.0
var orb: MeshInstance3D
var ring: MeshInstance3D
var rune_material: StandardMaterial3D
var base_orb_height := 6.1


func _ready() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("242d35")
	stone.metallic = 0.45
	stone.roughness = 0.62
	var pedestal := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.8
	cylinder.bottom_radius = 2.2
	cylinder.height = 0.65
	cylinder.radial_segments = 8
	pedestal.mesh = cylinder
	pedestal.material_override = stone
	pedestal.position.y = 0.3
	add_child(pedestal)

	var monolith := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.35, 5.1, 0.72)
	monolith.mesh = box
	monolith.material_override = stone
	monolith.position.y = 3.0
	monolith.rotation.z = -0.06
	add_child(monolith)

	rune_material = StandardMaterial3D.new()
	rune_material.albedo_color = accent_color
	rune_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rune_material.emission_enabled = true
	rune_material.emission = accent_color
	rune_material.emission_energy_multiplier = 2.2
	for i in range(4):
		var rune := MeshInstance3D.new()
		var rune_box := BoxMesh.new()
		rune_box.size = Vector3(0.58 + (i % 2) * 0.28, 0.12, 0.035)
		rune.mesh = rune_box
		rune.material_override = rune_material
		rune.position = Vector3(0, 2.0 + i * 0.7, -0.38)
		add_child(rune)

	orb = MeshInstance3D.new()
	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.46
	orb_mesh.height = 0.92
	orb_mesh.radial_segments = 16
	orb_mesh.rings = 8
	orb.mesh = orb_mesh
	orb.material_override = rune_material
	orb.position.y = base_orb_height
	add_child(orb)

	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.85
	torus.outer_radius = 1.92
	torus.rings = 40
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = rune_material
	ring.position.y = 0.85
	add_child(ring)

	var light := OmniLight3D.new()
	light.light_color = accent_color
	light.light_energy = 1.6
	light.omni_range = 16.0
	light.position.y = 4.2
	add_child(light)
	for child in get_children():
		if child is GeometryInstance3D:
			child.visibility_range_end = 1100.0

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var pedestal_collision := CollisionShape3D.new()
	var pedestal_shape := CylinderShape3D.new()
	pedestal_shape.radius = 2.2
	pedestal_shape.height = 0.65
	pedestal_collision.shape = pedestal_shape
	pedestal_collision.position.y = 0.3
	body.add_child(pedestal_collision)
	var monolith_collision := CollisionShape3D.new()
	var monolith_shape := BoxShape3D.new()
	monolith_shape.size = Vector3(1.35, 5.1, 0.72)
	monolith_collision.shape = monolith_shape
	monolith_collision.position.y = 3.0
	monolith_collision.rotation.z = -0.06
	body.add_child(monolith_collision)
	add_child(body)


func _process(_delta: float) -> void:
	if game == null:
		return
	var time: float = game.visual_time
	orb.position.y = base_orb_height + sin(time * 1.7 + float(abs(anomaly_id.hash()) % 10)) * 0.32
	orb.rotation.y = time * 0.7
	ring.rotation.y = time * 0.25
	var discovered: bool = game.discovered.has(anomaly_id)
	var pulse := 1.0 + sin(time * 2.4) * 0.08
	orb.scale = Vector3.ONE * (0.75 if discovered else pulse)
	rune_material.emission_energy_multiplier = 0.65 if discovered else 2.0 + sin(time * 2.0) * 0.35
