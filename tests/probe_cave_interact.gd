extends SceneTree

## 窟穴交互验收探针。
##
## 断言：
##   · 带洞的星球上，interactive_spots 里有 cave=true 的条目
##   · 这些条目的 local_pos 是**星球局部坐标**（不是洞内局部坐标）
##   · 站在洞内对应位置，nearest_interactive() 能返回那个交互点
##   · consume_interactive 能把洞内 MeshInstance3D 调暗，冷却后能恢复
##
## 用法：godot --headless --path . --script res://tests/probe_cave_interact.gd -- --no-capture

var fails := 0


func _init() -> void:
	await _run()


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		fails += 1
		print("FAIL  %s%s" % [label, ("  [" + detail + "]") if detail != "" else ""])


func _run() -> void:
	var PlanetScript = load("res://scripts/planet.gd")
	var kinds := ["qinglan", "zheya", "cangbo", "xuanjing", "xuanyuan"]
	var tested := 0

	for k in kinds:
		var p = PlanetScript.new()
		p.kind = k
		get_root().add_child(p)
		for _i in range(10):
			await process_frame

		if not bool(p.get("cave_enabled")):
			p.queue_free()
			await process_frame
			continue

		tested += 1
		var cave_spots: Array = []
		var spots: Array = p.get("interactive_spots")
		for s in spots:
			if bool((s as Dictionary).get("cave", false)):
				cave_spots.append(s)

		_check(cave_spots.size() > 0, "%s: 有洞内交互点" % k,
			"count=%d / 全部 %d" % [cave_spots.size(), spots.size()])

		if cave_spots.size() == 0:
			p.queue_free()
			await process_frame
			continue

		# local_pos 必须是星球局部坐标：量级应接近星球半径，而不是洞内那几十米
		var radius := float(p.get("radius"))
		var plausible := 0
		for s in cave_spots:
			var lp: Vector3 = (s as Dictionary)["local_pos"]
			if lp.length() > radius * 0.3:
				plausible += 1
		_check(plausible == cave_spots.size(), "%s: local_pos 是星球局部坐标" % k,
			"%d/%d 合理（半径 %.0f）" % [plausible, cave_spots.size(), radius])

		# 站在洞内某点，应该能命中
		var first: Dictionary = cave_spots[0]
		var world_probe: Vector3 = (p as Node3D).global_transform * (first["local_pos"] as Vector3)
		var hit: Dictionary = p.nearest_interactive(world_probe, 4.0)
		_check(not hit.is_empty(), "%s: 站在洞里能命中交互点" % k)
		if not hit.is_empty():
			_check(bool(hit.get("cave", false)), "%s: 命中的是洞内交互点" % k)

		# 采空 → 调暗 → 冷却恢复
		var idx: int = int(hit.get("index", -1)) if not hit.is_empty() else -1
		if idx >= 0:
			var spot: Dictionary = spots[idx]
			var maxc: int = int(spot["max_charges"])
			for _n in range(maxc):
				p.consume_interactive(idx)
			_check(int(spot["charges"]) == 0, "%s: 采空后 charges=0" % k)
			var node = spot.get("node")
			_check(node != null and is_instance_valid(node), "%s: 洞内交互点有 MeshInstance3D" % k)
			if node != null and is_instance_valid(node):
				_check((node as MeshInstance3D).material_override != null,
					"%s: 采空后被调暗（material_override 生效）" % k)
			# 手动重置 ready_at 触发冷却恢复
			spot["ready_at"] = 0
			p._refresh_interactive_charges()
			_check(int(spot["charges"]) == maxc, "%s: 冷却后次数恢复" % k)
			if node != null and is_instance_valid(node):
				_check((node as MeshInstance3D).material_override == null,
					"%s: 恢复后取消调暗" % k)

		p.queue_free()
		await process_frame
		await process_frame

	_check(tested > 0, "至少测了一颗带洞的星球", "tested=%d" % tested)

	if fails == 0:
		print("CAVE INTERACT PROBE COMPLETE: 0 failure(s)")
	else:
		print("CAVE INTERACT PROBE COMPLETE: %d failure(s)" % fails)
	quit()
