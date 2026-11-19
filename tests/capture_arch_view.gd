extends SceneTree
# 实机截图（改进版）：用**独立相机**拍 AI 道具，不受玩家贴地逻辑影响。
#
#   godot --path . --resolution 1280x720 --position -4000,-4000 --audio-driver Dummy \
#         --script res://tests/capture_props_view2.gd -- --no-capture
#
# 上一版失败原因：相机是 player.camera 的子节点，玩家每帧被 _physics_process
# 贴回地面，导致三张图位置完全一样、而且都在地台下方。

const OffWin := preload("res://scripts/offscreen_window.gd")

var game
var cam: Camera3D
var out_dir := "res://captures/arch"


func _initialize() -> void:
	call_deferred("_run")


func _shot(planet: Node3D, site: Vector3, perp: Vector3,
		label: String, dist_m: float, alt_m: float, look_alt: float) -> void:
	var dir: Vector3 = site.rotated(perp, dist_m / planet.radius).normalized()
	var pos: Vector3 = planet.global_position + planet.surface_position(dir, alt_m)
	var target: Vector3 = planet.global_position + planet.surface_position(site, look_alt)
	cam.global_position = pos
	cam.look_at(target, dir)
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, label])
	print("已保存 %s.png  相机距站点 %.0f m / 高 %.0f m" % [label, dist_m, alt_m])


func _run() -> void:
	await OffWin.apply(self)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var save := "user://starward_propshot2.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = save
	root.add_child(game)
	await game.await_world_ready()
	for i in range(6):
		await process_frame
	game.start_game()
	for i in range(20):
		await physics_frame
	for i in range(600):
		await process_frame
		if game.planets.size() >= 20:
			break

	# 独立相机：挂到星球上，位置用星球局部坐标，不会被任何角色逻辑改写
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.5
	cam.far = 200000.0
	game.home.add_child(cam)
	cam.current = true

	var home = game.home
	var site: Vector3 = home.site_direction.normalized()
	var perp: Vector3 = site.cross(Vector3.FORWARD)
	if perp.length_squared() < 0.01:
		perp = site.cross(Vector3.RIGHT)
	perp = perp.normalized()

	# 中景：离站点 300 米、高 90 米，俯角约 17°，能同时看到基地与周边道具
	await _shot(home, site, perp, "qinglan_300m", 300.0, 90.0, 10.0)
	# 远景：离站点 700 米、高 220 米
	await _shot(home, site, perp, "qinglan_700m", 700.0, 220.0, 10.0)
	# 贴地：离站点 60 米、高 8 米（看脚下细节与草木）
	await _shot(home, site, perp, "qinglan_60m", 60.0, 8.0, 3.0)

	# 换一颗星球：丹霞（有石桥 + 条纹阶地签名地标）
	var danxia: Node3D = null
	for p in game.planets:
		if p.planet_id == "danxia":
			danxia = p
			break
	if danxia != null:
		var dsite: Vector3 = danxia.site_direction.normalized()
		var dperp: Vector3 = dsite.cross(Vector3.FORWARD)
		if dperp.length_squared() < 0.01:
			dperp = dsite.cross(Vector3.RIGHT)
		dperp = dperp.normalized()
		cam.reparent(danxia, false)
		await _shot(danxia, dsite, dperp, "danxia_400m", 400.0, 130.0, 10.0)

	quit(0)
