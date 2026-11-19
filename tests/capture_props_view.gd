extends SceneTree
# 实机截图：站在星球表面看 AI 道具是否真的在那儿。
#
#   godot --path . --resolution 1280x720 --position -4000,-4000 --audio-driver Dummy \
#         --script res://tests/capture_props_view.gd -- --no-capture
#
# ⚠ 为什么要窗口：MultiMesh 的实例变换存在 RenderingServer 里，
#   headless 的 Dummy 渲染器读回恒为单位矩阵 —— 探针看不出对错，必须出图。

const OffWin := preload("res://scripts/offscreen_window.gd")

var game
var out_dir := "res://captures/props"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await OffWin.apply(self)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var save := "user://starward_propshot.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	for i in range(6):
		await process_frame
	game.start_game()
	for i in range(30):
		await physics_frame
	for i in range(600):
		await process_frame
		if game.planets.size() >= 20:
			break

	game.state = "walk"
	game.player.visible = false
	var home = game.home
	var cam: Camera3D = game.player.camera
	cam.current = true

	# 站在站点附近，低角度平视，能看到基地 + 周围道具
	var site: Vector3 = home.site_direction.normalized()
	var perp: Vector3 = site.cross(Vector3.FORWARD)
	if perp.length_squared() < 0.01:
		perp = site.cross(Vector3.RIGHT)
	perp = perp.normalized()

	var shots := [
		["ground_near", 240.0, 12.0],   # 离站点 240 米，高 12 米（人眼高度附近）
		["ground_far", 420.0, 40.0],    # 更远更高，看整体
		["air", 900.0, 260.0],          # 空中俯瞰
	]
	for shot in shots:
		var label: String = shot[0]
		var dist: float = shot[1]
		var alt: float = shot[2]
		var dir: Vector3 = site.rotated(perp, dist / home.radius).normalized()
		var pos: Vector3 = home.global_position + home.surface_position(dir, alt)
		var look_at: Vector3 = home.global_position + home.surface_position(site, 6.0)
		cam.global_position = pos
		cam.look_at(look_at, dir)
		for i in range(6):
			await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, label])
		print("已保存 %s/%s.png  (位置距站点 %.0f 米, 高 %.0f 米)" % [
			out_dir, label, dist, alt])

	quit(0)
