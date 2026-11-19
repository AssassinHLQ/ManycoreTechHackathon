extends SceneTree

## 星图出图探针：开真窗口、挪到屏幕外、截图，然后立刻退出。
##
## 用法：
##   godot --path . --script res://tests/capture_starmap.gd -- --no-capture
##
## ⚠ 遵守工作区「不许抢前台」红线：
##   · OffWin.apply() 取消最大化 + 960×540 + 挪到 (-4000,-4000)
##   · 命令行必须带 --no-capture（否则 player 会收鼠标）
##   · 出图就 quit()，不留窗口

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT := "res://_tools/_tmp/starmap.png"


func _init() -> void:
	await OffWin.apply(self)
	await _run()


func _run() -> void:
	var main_scene = load("res://scenes/main.tscn")
	var g = main_scene.instantiate()
	get_root().add_child(g)
	await process_frame

	# 先离开主菜单进入游戏（否则截到的是标题画面）
	g.start_game()
	await process_frame

	# 等星球建好
	for i in range(300):
		await process_frame
		if g.get("state") == "walk":
			break
	for i in range(40):
		await process_frame

	# 打开星图
	g.set("map_open", true)
	g.set("map_selected", 0)
	# 让 draw 跑几帧（星场预生成 + 呼吸动画）
	for i in range(8):
		await process_frame

	var img: Image = get_root().get_texture().get_image()
	if img == null:
		print("FAIL 拿不到截图")
		quit()
		return
	var path := ProjectSettings.globalize_path(OUT)
	var err := img.save_png(path)
	if err == OK:
		print("OK 星图截图: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	else:
		print("FAIL 保存失败 err=%d" % err)
	quit()
