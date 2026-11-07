extends SceneTree
# 视觉回归：把 captures/ 里的截图与基线逐张比对。
#
#   建立/更新基线： godot --headless --path . --script res://tests/visual_diff.gd -- --update
#   比对：           godot --headless --path . --script res://tests/visual_diff.gd
#
# 比对做法：先把两张图降采样到 320×180 再逐像素比。
# 直接比 2560×1440 的话单张就 370 万像素，33 张在 GDScript 里跑不动；
# 降采样之后既快，又天然容忍抗锯齿级别的微小抖动。

const BASE_DIR := "res://tests/visual_baseline"
const SHOT_DIR := "res://captures"
const COMPARE_W := 160
const COMPARE_H := 90
## 单个通道差异超过这个值才算「这个像素变了」（0-255）
const CHANNEL_THRESHOLD := 14
## 变化像素占比超过这个值就判失败
const FAIL_RATIO := 0.02
## 只比这个前缀的截图（回归套图的命名约定）
const PREFIX := "regress_"
## 单独放宽的图：这些场景含半透明云层或大量粒子，
## 即使固定种子、冻结推进，不同次渲染仍会有几个百分点的差异。
## 只对列在这里的图放宽，其余一律按 FAIL_RATIO 判。
const TOLERANCE_OVERRIDES := {
	# 这一组都是「半透明面 + 大量粒子」的场景：alpha 混合的排序与 MSAA
	# 在不同次渲染之间本就不会逐像素一致，实测稳定在 2%~4%。
	# 结构性的变化（缺标签、挪了布局）远大于这个量级 —— 实测能抓到 67%。
	"regress_08_world_cloud": 0.06,    # 大片半透明云海层叠
	"regress_08b_cloud_boat": 0.06,    # 同上，且贴近水面
	"regress_09_world_firefly": 0.06,  # 上千个萤火粒子铺满全幅
	"regress_10_world_alley": 0.06,    # 半透明水洼 + 上千雨丝
}

var failures := 0
var update_mode := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--update":
			update_mode = true
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


func _list_png(dir_path: String) -> Array:
	var names: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return names
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		# 只比回归套图（captures/ 里还有别的截图脚本留下的旧图）
		if not dir.current_is_dir() and name.begins_with(PREFIX) and name.ends_with(".png"):
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


func _load_small(path: String) -> Image:
	# 用绝对路径读：res:// 走 Image.load_from_file 会告警「导出后不可用」
	var abs_path := ProjectSettings.globalize_path(path)
	var image := Image.load_from_file(abs_path)
	if image == null:
		return null
	image.convert(Image.FORMAT_RGB8)
	image.resize(COMPARE_W, COMPARE_H, Image.INTERPOLATE_BILINEAR)
	return image


## 返回 {ratio, changed, min_x, min_y, max_x, max_y}
func _diff(a: Image, b: Image) -> Dictionary:
	var changed := 0
	var min_x := COMPARE_W
	var min_y := COMPARE_H
	var max_x := -1
	var max_y := -1
	for y in range(COMPARE_H):
		for x in range(COMPARE_W):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			var d: float = maxf(absf(pa.r - pb.r), maxf(absf(pa.g - pb.g), absf(pa.b - pb.b)))
			if d * 255.0 > float(CHANNEL_THRESHOLD):
				changed += 1
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	var total := COMPARE_W * COMPARE_H
	return {
		"ratio": float(changed) / float(total),
		"changed": changed,
		"min_x": min_x, "min_y": min_y, "max_x": max_x, "max_y": max_y,
	}


func _run() -> void:
	var shots := _list_png(SHOT_DIR)
	_check(not shots.is_empty(), "captures/ 里有截图（共 %d 张）" % shots.size())
	if shots.is_empty():
		print("VISUAL DIFF: 没有截图可比")
		quit(1)
		return

	if update_mode:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE_DIR))
		var copied := 0
		for name in shots:
			var img := Image.load_from_file(ProjectSettings.globalize_path(SHOT_DIR + "/" + name))
			if img == null:
				continue
			img.save_png(ProjectSettings.globalize_path(BASE_DIR) + "/" + name)
			copied += 1
		print("已更新基线：%d 张 -> %s" % [copied, BASE_DIR])
		quit(0)
		return

	var baseline := _list_png(BASE_DIR)
	_check(not baseline.is_empty(), "基线已存在（共 %d 张）" % baseline.size())
	if baseline.is_empty():
		print("VISUAL DIFF: 还没有基线，先跑一次 -- --update")
		quit(1)
		return

	# 基线有、截图没有 -> 说明有画面没拍出来
	for name in baseline:
		if not shots.has(name):
			_check(false, "截图缺失：%s" % name)

	# 截图有、基线没有 -> 这是新加的机位，**从来没被比对过**。
	# 这一条必须显式失败：否则新机位会一直静默通过，
	# 「加了张图但没人看」和「加了张图且没问题」在结果上完全一样（这次就踩到了）。
	var no_baseline: Array = []
	for name in shots:
		if not baseline.has(name):
			no_baseline.append(name)
	if not no_baseline.is_empty():
		_check(false, "有截图没有基线（%d 张）：%s —— 先跑一次 run_visual.ps1 -Update 把基线补上" % [
			no_baseline.size(), ", ".join(no_baseline)])

	var worst := 0.0
	var worst_name := ""
	var compared := 0
	for name in baseline:
		if not shots.has(name):
			continue
		var base_img := _load_small(BASE_DIR + "/" + name)
		var shot_img := _load_small(SHOT_DIR + "/" + name)
		if base_img == null or shot_img == null:
			_check(false, "%s：图片读不出来" % name)
			continue
		compared += 1
		var result := _diff(base_img, shot_img)
		var ratio: float = float(result["ratio"])
		if ratio > worst:
			worst = ratio
			worst_name = String(name)
		var key: String = String(name).trim_suffix(".png")
		var limit := FAIL_RATIO
		if TOLERANCE_OVERRIDES.has(key):
			limit = float(TOLERANCE_OVERRIDES[key])
		var extra := ""
		if ratio > limit:
			extra = " · 变化区域 x[%d,%d] y[%d,%d]" % [
				int(result["min_x"]), int(result["max_x"]),
				int(result["min_y"]), int(result["max_y"])]
		elif ratio > FAIL_RATIO:
			extra = "（此图容差放宽到 %.0f%%）" % (limit * 100.0)
		_check(ratio <= limit,
			"%s：变化 %.3f%%%s" % [key, ratio * 100.0, extra])

	print("比对 %d 张，最大变化 %.3f%%（%s）" % [compared, worst * 100.0, worst_name])
	if failures > 0:
		print("VISUAL DIFF: %d failure(s)" % failures)
		quit(1)
	else:
		print("VISUAL DIFF: all clear")
		quit(0)
