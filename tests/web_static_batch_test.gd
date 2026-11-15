extends SceneTree
const Batch = preload("res://scripts/web_static_batch.gd")
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func _run() -> void:
	var planet := Node3D.new()
	root.add_child(planet)
	var landmark := Node3D.new()
	landmark.name = "Architecture_Test"
	planet.add_child(landmark)
	landmark.position = Vector3(100, 20, -200)
	landmark.rotation.y = 0.7
	landmark.scale = Vector3.ONE * 5.0
	var material := StandardMaterial3D.new()
	var bounds := AABB()
	for i in range(3):
		var node := MeshInstance3D.new()
		node.mesh = BoxMesh.new()
		node.material_override = material
		node.position = Vector3(2 + i, 2, 2)
		landmark.add_child(node)
		bounds = bounds.merge(node.transform * node.get_aabb()) if i > 0 else node.transform * node.get_aabb()
	var body := StaticBody3D.new()
	landmark.add_child(body)
	Batch.apply(planet, true)
	var report: Dictionary = landmark.get_meta("web_batched", {})
	_check(report.get("sources", 0) == 3 and report.get("batches", 0) == 1, "three shared-material objects become one draw batch")
	_check(report.get("triangles", 0) == 36 and report.get("output_triangles", 0) == 36, "batch retains every triangle")
	var mesh: MeshInstance3D = landmark.get_node("WebStaticBatch")
	_check(mesh.mesh.get_aabb().position.is_equal_approx(bounds.position) and mesh.mesh.get_aabb().size.is_equal_approx(bounds.size), "placement and bounds survive the transformed parent")
	_check(body.get_parent() == landmark, "collision and gameplay hierarchy remain intact")
	Batch.apply(planet, true)
	_check(landmark.find_children("WebStaticBatch*", "MeshInstance3D", true, false).size() == 1, "batching is idempotent")
	planet.free()
	print("WEB STATIC BATCH TEST COMPLETE: ", failures, " failures")
	quit(0 if failures == 0 else 1)
