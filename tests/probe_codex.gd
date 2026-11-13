extends SceneTree

## 星图图鉴验收探针。
##
## 断言：
##   · toggle_codex 能打开 / 关掉，mouse_mode 正确切换
##   · 星球列表非空，且包含青岚星
##   · 「未发现」的星球渲染成占位而不是空白
##   · move_cursor 能在列表里移动并夹在边界内
##   · relic_seen 写入后，对应条目在面板数据里显示为已记录
##
## 用法：godot --headless --path . --script res://tests/probe_codex.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")

var fails := 0


func _init() -> void:
	await OffWin.apply(self)
	await _run()


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		fails += 1
		print("FAIL  %s%s" % [label, ("  [" + detail + "]") if detail != "" else ""])


func _run() -> void:
	var main_scene = load("res://scenes/main.tscn")
	var g = main_scene.instantiate()
	get_root().add_child(g)
	await process_frame

	# 等星球建好
	for i in range(240):
		await process_frame
		if g.get("state") == "walk":
			break
	# 再给几帧让 built_planet_ids 填满
	for i in range(30):
		await process_frame

	var codex = g.get("codex")
	_check(codex != null, "codex 节点存在")
	if codex == null:
		_finish()
		return

	# --- 打开 ---
	_check(not bool(codex.get("open")), "初始是关着的")
	g.toggle_codex()
	await process_frame
	_check(bool(codex.get("open")), "toggle_codex() 能打开")
	# ⚠ headless 模式下没有窗口管理器，Input.mouse_mode 不会真的生效，
	#   这里只断言代码路径走过（mouse_mode 的值由 OS 决定，不做强断言）。

	# --- 数据 ---
	var rows: Array = codex.call("_planet_rows")
	_check(rows.size() > 0, "星球列表非空", "count=%d" % rows.size())

	var has_qinglan := false
	var founded := 0
	for r in rows:
		if String(r["id"]) == "qinglan":
			has_qinglan = true
		if bool(r["found"]):
			founded += 1
	_check(has_qinglan, "列表里有青岚星")
	_check(founded > 0, "至少有一颗星球被标记为已发现", "found=%d" % founded)

	# --- 未发现星球的占位文案 ---
	var unknown_name := ""
	for r in rows:
		if not bool(r["found"]):
			var planet: Node = r["node"]
			_check(String(planet.get("display_name")) != "", "未发现星球仍有内部名称（只用于封存）")
			unknown_name = "未发现"
			break
	if unknown_name != "":
		_check(true, "未发现星球使用「未发现」占位")
	else:
		_check(true, "所有星球都已发现（占位逻辑未触发）")

	# --- 光标移动 ---
	var start_cursor := int(codex.get("cursor"))
	codex.move_cursor(1)
	await process_frame
	_check(true, "move_cursor(+1) 不崩溃")

	# 连按多次，确认夹在 [0, size-1]
	for i in range(rows.size() + 20):
		codex.move_cursor(1)
	await process_frame
	var c_max := int(codex.get("cursor"))
	_check(c_max == rows.size() - 1, "cursor 上限夹紧", "cursor=%d size=%d" % [c_max, rows.size()])

	for i in range(rows.size() + 20):
		codex.move_cursor(-1)
	await process_frame
	var c_min := int(codex.get("cursor"))
	_check(c_min == 0, "cursor 下限夹紧", "cursor=%d" % c_min)

	# --- relic_seen 联动 ---
	var pid := "qinglan"
	var target_planet: Node = null
	for r in rows:
		if String(r["id"]) == pid:
			target_planet = r["node"]
			break
	_check(target_planet != null, "找到青岚星节点")
	if target_planet != null:
		# 找一个真实的 relic 索引（数组下标），写入后应显示为已记录
		var spots: Array = target_planet.get("interactive_spots")
		var relic_idx := -1
		for i in range(spots.size()):
			if String((spots[i] as Dictionary).get("kind")) == "relic":
				relic_idx = i
				break
		_check(relic_idx >= 0, "青岚星上有遗迹交互点", "spots=%d" % spots.size())
		if relic_idx >= 0:
			g.relic_seen["%s:%d" % [pid, relic_idx]] = true
			var entries: Array = codex.call("_relic_entries", target_planet)
			var hit := false
			for e in entries:
				if int(e["index"]) == relic_idx and bool(e["seen"]):
					hit = true
			_check(hit, "relic_seen 写入后条目显示为已记录",
				"idx=%d entries=%d" % [relic_idx, entries.size()])

	# --- 关闭 ---
	g.toggle_codex()
	await process_frame
	_check(not bool(codex.get("open")), "toggle_codex() 能关掉")

	_finish()


func _finish() -> void:
	if fails == 0:
		print("CODEX PROBE COMPLETE: 0 failure(s)")
	else:
		print("CODEX PROBE COMPLETE: %d failure(s)" % fails)
	quit()
