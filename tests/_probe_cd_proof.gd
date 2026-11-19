extends SceneTree
# 活体演示：证明 C（LRU 淘汰）与 D（LOD 联动）真的在运行。
#
# D 的证明：依次设 LOD = 0/1/2/3，每次读回真实的 visibility_range_end，
#           如果数值随档位变化，说明是真的在联动，不是硬编码。
# C 的证明：手动塞入 60 个「闲置」缓存条目（不在任何星球上），
#           触发淘汰后应该被清掉，而 149 个「在用」条目必须全部保留。

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _count_ranges() -> Dictionary:
	var seen := {}
	for planet in game.planets:
		if planet == null:
			continue
		for node in planet.find_children("Prop_*", "MultiMeshInstance3D", true, false):
			var mmi := node as MultiMeshInstance3D
			if mmi == null:
				continue
			var v: float = mmi.visibility_range_end
			seen[v] = int(seen.get(v, 0)) + 1
	return seen


func _run() -> void:
	var save_path := "user://starward_proof.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save_path
	root.add_child(game)
	await game.await_world_ready()

	var deadline := Time.get_ticks_msec() + 180000
	while game.planets.size() < 20 and Time.get_ticks_msec() < deadline:
		await process_frame
	await _frames(10)

	var PlanetScript = load("res://scripts/planet.gd")
	var SettingsScript = load("res://scripts/settings.gd")

	# ── D：逐个档位切换，读回真实值 ──────────────────────────────
	# 判定标准（由观测数据计算，不是写死的 YES）：
	#   每个档位观测到的 range 必须只落在 {base, base*1.6}，且 base 必须出现；
	#   四个档位观测到的 base 必须互不相同 —— 否则就是硬编码。
	print("=== D PROOF: lod 0..3 -> actual visibility_range_end ===")
	var d_ok := true
	var observed_bases: Array = []
	for level in range(4):
		game.settings.set_lod(level)
		await _frames(3)
		var seen := _count_ranges()
		var keys: Array = seen.keys()
		keys.sort()
		var desc := ""
		for k in keys:
			desc += "%.0f m x%d, " % [float(k), int(seen[k])]
		var base: float = float(SettingsScript.LOD_DISTANCE[level])
		print("  lod=%d  expect base=%.0f landmark=%.0f  actual: %s" % [
			level, base, base * 1.6, desc])
		var has_base := false
		for k in keys:
			var v: float = float(k)
			if is_equal_approx(v, base):
				has_base = true
			elif not is_equal_approx(v, base * 1.6):
				d_ok = false
		if not has_base:
			d_ok = false
		observed_bases.append(base if has_base else -1.0)
	for i in range(observed_bases.size()):
		for j in range(i + 1, observed_bases.size()):
			if observed_bases[i] < 0.0 or is_equal_approx(observed_bases[i], observed_bases[j]):
				d_ok = false

	# 恢复成用户原本的设置
	game.settings.set_lod(0)
	await _frames(3)

	# ── C：塞 60 个闲置条目，验证淘汰 ────────────────────────────
	print("\n=== C PROOF: idle entries must be evicted, in-use must survive ===")
	var cache0: Dictionary = PlanetScript._prop_mesh_cache
	var inuse0: Dictionary = PlanetScript._prop_in_use
	print("  before: cache=%d  in_use=%d" % [cache0.size(), inuse0.size()])
	var inuse_before: int = inuse0.size()

	for i in range(60):
		var fake_id := "zzz-idle-test-%02d" % i
		PlanetScript._prop_mesh_cache[fake_id] = null
		PlanetScript._prop_cache_touch(fake_id)

	var cache1: Dictionary = PlanetScript._prop_mesh_cache
	var idle_left := 0
	for k in cache1.keys():
		if String(k).begins_with("zzz-idle-test-"):
			idle_left += 1
	print("  after : cache=%d  idle_remaining=%d" % [cache1.size(), idle_left])

	# 在用条目是否全部还在
	var missing := 0
	for k in inuse0.keys():
		if not cache1.has(k):
			missing += 1
	print("  in_use still cached: %d / %d  (missing=%d)" % [
		inuse_before - missing, inuse_before, missing])
	print("\n  D real?  %s" % ("YES - ranges track lod" if d_ok else "NO - ranges do NOT match lod"))
	print("  C real?  %s" % ("YES - idle evicted, in-use kept" if (idle_left == 0 and missing == 0) else "NO"))

	print("\nPROOF DONE")
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0)
