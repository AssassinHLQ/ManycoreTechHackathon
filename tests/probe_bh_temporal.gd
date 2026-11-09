extends SceneTree
# 探针：量「闪烁」——固定相机连拍，算帧间差异。
#
# 为什么这样测：吸积盘自转只有 0.004 弧度/秒（26 分钟一圈），
# 相邻几帧之间画面本该几乎完全一样。所以任何明显的帧间变化都不是自转，
# 而是闪烁（多层三角面透视重叠随视角抖动）。
#
# 输出：平均帧间差、最大帧间差、变化像素占比（>8）。
#       数字越小越稳；修好之后应该接近 0。
#
#   godot --path . --resolution 1280x720 --position -4000,-4000 \
#         --audio-driver Dummy --script res://tests/probe_bh_temporal.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")

var game


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _diff(a: Image, b: Image) -> Array:
	var w := a.get_width()
	var h := a.get_height()
	var total := 0.0
	var worst := 0.0
	var changed := 0
	var count := 0
	# 抽样步长 2：全图逐像素太慢，隔点采样足够反映闪烁
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			var d: float = maxf(maxf(absf(pa.r - pb.r), absf(pa.g - pb.g)), absf(pa.b - pb.b)) * 255.0
			total += d
			worst = maxf(worst, d)
			if d > 8.0:
				changed += 1
			count += 1
	return [total / maxf(1.0, float(count)), worst, 100.0 * float(changed) / maxf(1.0, float(count))]


func _run() -> void:
	await OffWin.apply(self)
	var save := "user://starward_probe_bh_temporal.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	await _frames(30)
	game.hud.visible = false
	game.set_process(false)
	game.state = "capture"

	var target: Node3D = game.gargantua
	if target == null:
		print("卡冈图雅没建出来")
		quit(1)
		return
	var center: Vector3 = target.global_position
	var cam := Camera3D.new()
	cam.near = 1.0
	cam.far = 200000.0
	cam.fov = 55.0
	game.add_child(cam)
	cam.current = true

	# 挑三个「内部结构最容易闪」的角度：贴近盘面、稍微侧一点
	var angles := [
		["edge_0", deg_to_rad(0.0), deg_to_rad(18.0)],
		["edge_60", deg_to_rad(60.0), deg_to_rad(18.0)],
		["above_45", deg_to_rad(45.0), deg_to_rad(40.0)],
	]
	print("=== 帧间稳定性（数字越小越不闪） ===")
	print("  角度        平均差   最大差   变化像素占比")
	for entry in angles:
		var label: String = entry[0]
		var yaw: float = entry[1]
		var pitch: float = entry[2]
		var dist := 2600.0
		cam.global_position = center + Vector3(
			cos(pitch) * cos(yaw) * dist,
			sin(pitch) * dist,
			cos(pitch) * sin(yaw) * dist)
		cam.look_at(center, Vector3.UP)
		await _frames(10)

		var prev: Image = await _grab()
		var acc_mean := 0.0
		var acc_worst := 0.0
		var acc_pct := 0.0
		var samples := 5
		for i in range(samples):
			await _frames(3)
			var cur: Image = await _grab()
			var r: Array = _diff(prev, cur)
			acc_mean += float(r[0])
			acc_worst = maxf(acc_worst, float(r[1]))
			acc_pct += float(r[2])
			prev = cur
		print("  %-10s  %7.3f  %7.1f   %7.3f%%" % [
			label, acc_mean / samples, acc_worst, acc_pct / samples])
	print("DONE")
	quit(0)
