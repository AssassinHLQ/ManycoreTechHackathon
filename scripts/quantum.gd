extends Node3D

## 量子碎岩：未被观测时会在若干坐标间迁移；被持续注视时会保持静止。
## 它同时实现扫描目标的接口，因此可以直接加入 game.anomalies。

var game
var planet
var anomaly_id := "quantum"
var title := "量子碎岩"
var body := "它不服从轨道。只要没有一双眼睛落在它身上，它就可能在几个位置之间任选其一。被看见的那一刻，它才不得不存在于此。"
var accent_color := Color("ffab5e")
var scan_time := 3.4

var positions: Array = []
var index := 0
var unobserved_time := 0.0
var announced := false
var crystal: MeshInstance3D
var rings: Array = []
var glow_light: OmniLight3D
var crystal_material: StandardMaterial3D
var flash: MeshInstance3D
var flash_material: StandardMaterial3D
var rng := RandomNumberGenerator.new()
var bob_time := 0.0


func _ready() -> void:
	planet = get_parent()
	rng.seed = 7331
	_build_visual()
	_build_positions()
	if positions.is_empty():
		return
	_place(0)


func _build_visual() -> void:
	crystal_material = StandardMaterial3D.new()
	crystal_material.albedo_color = Color(0.52, 0.34, 1.0)
	crystal_material.emission_enabled = true
	crystal_material.emission = Color(0.46, 0.2, 1.0)
	crystal_material.emission_energy_multiplier = 1.7
	crystal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	crystal = MeshInstance3D.new()
	var shard := CylinderMesh.new()
	shard.top_radius = 0.0
	shard.bottom_radius = 0.92
	shard.height = 3.4
	shard.radial_segments = 4
	crystal.mesh = shard
	crystal.material_override = crystal_material
	crystal.position.y = 2.9
	add_child(crystal)

	var inner := MeshInstance3D.new()
	var inner_shard := CylinderMesh.new()
	inner_shard.top_radius = 0.0
	inner_shard.bottom_radius = 0.44
	inner_shard.height = 4.6
	inner_shard.radial_segments = 4
	inner.mesh = inner_shard
	inner.material_override = crystal_material
	inner.position.y = 2.1
	inner.rotation.y = PI * 0.25
	inner.rotation.z = PI
	add_child(inner)

	for i in range(2):
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 1.55 + i * 0.5
		torus.outer_radius = 1.63 + i * 0.5
		torus.rings = 32
		torus.ring_segments = 6
		ring.mesh = torus
		ring.material_override = crystal_material
		ring.position.y = 2.9
		add_child(ring)
		rings.append(ring)

	var plinth := MeshInstance3D.new()
	var plinth_mesh := CylinderMesh.new()
	plinth_mesh.top_radius = 1.5
	plinth_mesh.bottom_radius = 1.9
	plinth_mesh.height = 0.5
	plinth_mesh.radial_segments = 8
	plinth.mesh = plinth_mesh
	var plinth_material := StandardMaterial3D.new()
	plinth_material.albedo_color = Color("241d33")
	plinth_material.metallic = 0.4
	plinth_material.roughness = 0.55
	plinth.material_override = plinth_material
	plinth.position.y = 0.25
	add_child(plinth)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.9
	shape.height = 0.5
	collision.shape = shape
	collision.position.y = 0.25
	body.add_child(collision)
	add_child(body)

	var rune := MeshInstance3D.new()
	var rune_torus := TorusMesh.new()
	rune_torus.inner_radius = 3.3
	rune_torus.outer_radius = 3.5
	rune_torus.rings = 40
	rune_torus.ring_segments = 5
	rune.mesh = rune_torus
	rune.material_override = crystal_material
	rune.rotation.x = PI * 0.5
	rune.position.y = 0.52
	add_child(rune)

	for i in range(3):
		var fleck := MeshInstance3D.new()
		var fleck_mesh := CylinderMesh.new()
		fleck_mesh.top_radius = 0.0
		fleck_mesh.bottom_radius = 0.22
		fleck_mesh.height = 0.9
		fleck_mesh.radial_segments = 3
		fleck.mesh = fleck_mesh
		fleck.material_override = crystal_material
		var angle := TAU * float(i) / 3.0
		fleck.position = Vector3(cos(angle) * 2.3, 1.4 + float(i) * 0.8, sin(angle) * 2.3)
		add_child(fleck)

	glow_light = OmniLight3D.new()
	glow_light.light_color = Color("ffab5e")
	glow_light.light_energy = 3.4
	glow_light.omni_range = 18.0
	glow_light.position.y = 2.9
	add_child(glow_light)

	flash_material = StandardMaterial3D.new()
	flash_material.albedo_color = Color(0.85, 0.72, 1.0, 0.5)
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash = MeshInstance3D.new()
	var bubble := SphereMesh.new()
	bubble.radius = 3.4
	bubble.height = 6.8
	bubble.radial_segments = 16
	bubble.rings = 8
	flash.mesh = bubble
	flash.material_override = flash_material
	flash.position.y = 2.4
	flash.scale = Vector3.ONE * 0.01
	flash.visible = false
	add_child(flash)
	for child in get_children():
		if child is GeometryInstance3D:
			child.visibility_range_end = 900.0
		elif child is Node3D:
			for grandchild in child.get_children():
				if grandchild is GeometryInstance3D:
					grandchild.visibility_range_end = 900.0


func _build_positions() -> void:
	if planet == null or not planet.cave_enabled:
		return
	var base: Vector3 = planet.site_direction
	var tangents := [
		Vector3.RIGHT,
		-Vector3.RIGHT,
		Vector3.FORWARD,
		(Vector3.RIGHT + Vector3.FORWARD).normalized(),
		(-Vector3.RIGHT + Vector3.FORWARD).normalized()
	]
	for tangent in tangents:
		var direction: Vector3 = (base + tangent * 0.086).normalized()
		positions.append(planet.surface_position(direction, 0.06))


func _place(next_index: int) -> void:
	index = next_index
	var local: Vector3 = positions[index]
	position = local
	basis = Basis(Quaternion(Vector3.UP, local.normalized()))


func _process(delta: float) -> void:
	if game == null or planet == null or positions.is_empty():
		return
	_animate(delta)
	if game.state not in ["walk", "ship"] or game.paused:
		return
	if game.discovered.has(anomaly_id):
		return
	var active: Vector3 = game.get_active_position()
	if active.distance_to(global_position) > 700.0:
		return
	if _observed():
		unobserved_time = 0.0
		if not announced:
			announced = true
			game.hud.show_toast("它在你注视时静止。移开视线，看看会发生什么。", 4.0)
		return
	unobserved_time += delta
	if unobserved_time >= 2.4:
		unobserved_time = 0.0
		_teleport()


func _animate(delta: float) -> void:
	bob_time += delta
	crystal.position.y = 2.9 + sin(bob_time * 1.4) * 0.22
	crystal.rotation.y += delta * 0.9
	for i in range(rings.size()):
		var ring: MeshInstance3D = rings[i]
		ring.rotation.y += delta * (0.4 + i * 0.25)
		ring.rotation.x = sin(bob_time * 0.7 + i) * 0.4
		ring.position.y = 2.9 + sin(bob_time * 1.1 + i * 1.7) * 0.12
	glow_light.light_energy = 3.4 + sin(bob_time * 2.2) * 0.45
	crystal_material.emission_energy_multiplier = 3.0 + sin(bob_time * 1.8) * 0.6
	if flash.visible:
		var flash_scale: float = flash.scale.x + delta * 9.0
		flash.scale = Vector3.ONE * flash_scale
		flash_material.albedo_color.a = maxf(0.0, 0.5 - flash_scale * 0.09)
		if flash_material.albedo_color.a <= 0.0:
			flash.visible = false


func _observed() -> bool:
	var camera: Camera3D = game.get_active_camera()
	if camera == null:
		return false
	var target: Vector3 = crystal.global_position
	var offset := target - camera.global_position
	var distance := offset.length()
	if distance > 720.0:
		return false
	var forward := -camera.global_transform.basis.z
	if forward.dot(offset.normalized()) < 0.5:
		return false
	return game._has_line_of_sight(camera.global_position, target)


func _teleport() -> void:
	if positions.size() < 2:
		return
	var next_index := index
	while next_index == index:
		next_index = rng.randi_range(0, positions.size() - 1)
	_place(next_index)
	flash.visible = true
	flash.scale = Vector3.ONE * 0.05
	flash_material.albedo_color.a = 0.5
	if global_position.distance_to(game.get_active_position()) < 180.0:
		game.audio.play_ui(760.0)
		game.hud.show_toast("碎岩在你没看的时候换了位置。", 2.6)
