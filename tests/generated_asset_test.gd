extends SceneTree
## Verify every installed prop has a live route and every queued instance reaches rendering.

const Planet := preload("res://scripts/planet.gd")
const Placement := preload("res://scripts/prop_placement.gd")
var game
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)


func _run() -> void:
	var save := "user://generated_asset_test.json"
	var progress := "user://generated_asset_progress.json"
	for path in [save, progress]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	game.progress_path = progress
	root.add_child(game)
	await game.await_world_ready()
	# The remaining planets must inherit settings even when they load afterwards.
	game.settings.values.lod = 0
	game.settings.values.grass = 0
	game.settings._apply_lod()
	game.start_game()
	var deadline := Time.get_ticks_msec() + 180000
	while (game.planets.size() < 20 or game.world_build_remaining) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(game.planets.size() == 20, "all 20 planets are built")
	var used := {}
	var core_models := {}
	var themes := {}
	var signatures := {}
	var count := 0
	for node in game.find_children("*", "Node3D", true, false):
		if node.has_meta("generated_asset"):
			used[node.get_meta("generated_asset")] = true
		if node.scene_file_path.begins_with("res://assets/models/"):
			core_models[node.scene_file_path] = true
	for planet in game.planets:
		if planet.has_meta("runtime_baked"):
			var terrain: Resource = load("res://assets/runtime_bakes/planet_" + planet.planet_id + ".res")
			var meshes: Array = terrain.get_meta("meshes", [])
			if terrain.get_meta("signature", {}).get("model", "") == planet.lux_model_path and not meshes.is_empty() and planet.surface.mesh == meshes[0].mesh:
				core_models[planet.lux_model_path] = true
		var signature: Array[String] = []
		for node in planet.find_children("*", "MeshInstance3D", true, false):
			var name := String(node.name)
			if name.begins_with("CaveProp_"):
				var id := name.trim_prefix("CaveProp_")
				if Planet.PROP_MODELS.has(id):
					used[Planet.PROP_MODELS[id]] = true
		for id in planet.prop_queue:
			var parent: Node3D = planet._prop_root if planet._prop_root != null else planet
			var instance := parent.get_node_or_null("Prop_" + id) as MultiMeshInstance3D
			_check(instance != null and instance.multimesh.instance_count == planet.prop_queue[id].size(),
				"%s renders every queued %s" % [planet.planet_id, id])
			if instance != null:
				if instance.is_in_group("ground_scatter") and instance.multimesh.instance_count > 1:
					_check(instance.multimesh.visible_instance_count > 0 and instance.multimesh.visible_instance_count < instance.multimesh.instance_count,
						"%s respects the saved low plant density" % planet.planet_id)
				if id.begins_with("lm-") or id.begins_with("lm2-") or id.begins_with("lf-"):
					_check(instance.multimesh.visible_instance_count == -1, "%s low detail preserves %s" % [planet.planet_id, id])
				used[Planet.PROP_MODELS[id]] = true
				count += instance.multimesh.instance_count
				if not id.begins_with("lm-") and not id.begins_with("lm2-"):
					signature.append(id)
		for prefix in ["lm-", "lm2-"]:
			var id: String = prefix + planet.kind
			if ResourceLoader.exists(Planet.PROP_MODELS.get(id, "res://missing")):
				_check(planet.prop_queue.has(id), "%s has its own %s landmark" % [planet.planet_id, prefix])
		var workshops: Array = planet.find_children("Workshop_*", "Node3D", false, false)
		_check(workshops.size() == 1, "%s has a coherent outpost" % planet.planet_id)
		if not workshops.is_empty():
			var outpost: Node3D = workshops[0]
			themes[outpost.get_meta("theme")] = true
			var platform := outpost.get_node_or_null("Prop_mod-platform") as Node3D
			_check(platform != null and outpost.has_node("WorkshopCollision"), "outpost has visual deck and matching collision")
			if platform != null:
				var deck_box: AABB = platform.transform * Placement.bounds(platform)
				for node in outpost.get_children():
					if node is Node3D and node.has_meta("generated_asset") and node != platform \
						and not node.has_meta("surface_attachment") \
						and not String(node.name).contains("stairs") and not String(node.name).contains("tower-top"):
						var contact_gap := INF
						for point in Placement.contact_points(node):
							var foot: Vector3 = node.transform * point
							var floor_y := Placement.support_y(platform, Vector2(foot.x, foot.z), 1)
							if is_finite(floor_y):
								contact_gap = minf(contact_gap, foot.y - platform.position.y - floor_y)
						_check(is_finite(contact_gap) and absf(contact_gap) < 0.002,
							"%s %s has a foot touching the real deck" % [planet.planet_id, node.name])
						var footprint: AABB = node.transform * Placement.bounds(node)
						_check(footprint.position.x >= deck_box.position.x - 0.03 and footprint.end.x <= deck_box.end.x + 0.03 \
							and footprint.position.z >= deck_box.position.z - 0.03 and footprint.end.z <= deck_box.end.z + 0.03,
							"%s %s fits inside its deck" % [planet.planet_id, node.name])
				var stairs := outpost.get_node("Prop_mod-stairs") as Node3D
				var stair_box: AABB = stairs.transform * Placement.bounds(stairs)
				_check(stair_box.position.z < deck_box.end.z, "stairs overlap the deck edge without a seam")
				var tread := stairs.position.y + Placement.support_y(stairs, Vector2(0, -0.85), 10)
				var edge := platform.position.y + Placement.support_y(platform, Vector2(0, 2.3), 1)
				_check(absf(tread - edge) < 0.002, "upper stair tread meets the real deck rim")
				var roof := outpost.get_node_or_null("Prop_mod-tower-top") as Node3D
				if roof != null:
					var supports := outpost.find_children("RoofSupport_*", "MeshInstance3D", false, false)
					_check(supports.size() == 4, "round tower crown has four supports inside its footprint")
					for support in supports:
						var box: AABB = support.transform * Placement.bounds(support)
						var bottom := roof.position.y + Placement.support_y(roof, Vector2(support.position.x, support.position.z), -1, true)
						_check(is_finite(bottom) and absf(box.end.y - bottom) < 0.02, "column reaches the actual underside of the crown")
		signature.sort()
		signatures["|".join(signature)] = true
	_check(themes.size() == 4, "four distinct outpost themes")
	_check(signatures.size() == 20, "all 20 planets have distinct environment combinations")
	var active_core := 0
	for id in DirAccess.get_directories_at("res://assets/models/"):
		# The original Qinglan surface is superseded by its v5 model.
		if id in ["props", "qinglan-planet"]:
			continue
		var path: String = "res://assets/models/" + id + "/model.glb"
		if ResourceLoader.exists(path):
			active_core += 1
			_check(core_models.has(path), "active core model is instantiated: " + path)
	var installed := 0
	var missing: Array[String] = []
	for directory in ["res://assets/models/props/", "res://assets/models/props/station/",
		"res://assets/models/props/attic/", "res://assets/models/props/attic-worlds/"]:
		for id in DirAccess.get_directories_at(directory):
			for filename in ["model.glb", "model_glb.glb"]:
				var path: String = directory + id + "/" + filename
				if not ResourceLoader.exists(path):
					continue
				installed += 1
				if not used.has(path):
					missing.append(path)
				break
	_check(missing.is_empty(), "installed assets without live instances: " + str(missing))
	print("GENERATED ASSETS: %d installed, %d used paths, %d planet instances, %d themes, %d unique combinations" % [
		installed, used.size(), count, themes.size(), signatures.size()])
	print("CORE MODELS: %d active assets checked; legacy Qinglan surface retained as superseded" % active_core)
	print("GENERATED ASSET TEST COMPLETE: %d checks, %d failure(s)" % [checks, failures])
	game.queue_free()
	await process_frame
	await process_frame
	for path in [save, progress]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0 if failures == 0 else 1)
