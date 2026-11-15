extends SceneTree
const Visibility = preload("res://scripts/scene_visibility.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var detail := MeshInstance3D.new()
	detail.mesh = BoxMesh.new()
	scene.add_child(detail)
	var terrain := MeshInstance3D.new()
	terrain.mesh = SphereMesh.new()
	terrain.scale = Vector3.ONE * 2000.0
	scene.add_child(terrain)
	var authored := MeshInstance3D.new()
	authored.mesh = BoxMesh.new()
	authored.visibility_range_end = 777.0
	scene.add_child(authored)
	var scatter := MultiMeshInstance3D.new()
	scatter.multimesh = MultiMesh.new()
	scatter.multimesh.mesh = BoxMesh.new()
	scene.add_child(scatter)
	Visibility.apply(scene, false)
	_check(detail.visibility_range_end == 0.0, "desktop keeps its existing visibility policy")
	Visibility.apply(scene, true)
	_check(detail.visibility_range_end == 120.0, "small Web detail retains a generous near viewing range")
	_check(terrain.visibility_range_end == 0.0, "planet silhouettes retain their unlimited viewing range")
	_check(authored.visibility_range_end == 777.0, "authored culling distances are preserved")
	_check(scatter.visibility_range_end == 0.0, "scatter stays under its existing LOD control")
	Visibility.apply(scene, true)
	_check(detail.visibility_range_end == 120.0, "reapplying the policy never compounds its range")
	scene.free()
	print("SCENE VISIBILITY TEST COMPLETE: ", failures, " failures")
	quit(0 if failures == 0 else 1)
