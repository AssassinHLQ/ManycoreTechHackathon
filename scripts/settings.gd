extends Node

## 画质与窗口设置。修改后立即生效并写入 user://starward_settings.json。

var game
var save_path := "user://starward_settings.json"
var values := {
	"quality": "medium",
	"resolution": 1,
	"vsync": true,
	"fps_limit": 0,
	"msaa": 1,
	"shadows": 2,
	"view_distance": 1,
	"grass": 1,
	"sky_detail": 3,
	"volume": 80,
	"sensitivity": 1.0,
	"lod": 2
}

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

var ranged_nodes: Array = []
var ground_scatters: Array = []
var collected := false


func load_and_apply() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		for key in values.keys():
			if data.has(key):
				values[key] = data[key]
	values["quality"] = str(values["quality"])
	values["resolution"] = clampi(int(values["resolution"]), 0, 3)
	values["fps_limit"] = clampi(int(values["fps_limit"]), 0, 240)
	values["msaa"] = clampi(int(values["msaa"]), 0, 2)
	values["shadows"] = clampi(int(values["shadows"]), 0, 2)
	values["view_distance"] = clampi(int(values["view_distance"]), 0, 2)
	values["grass"] = clampi(int(values["grass"]), 0, 1)
	values["sky_detail"] = clampi(int(values["sky_detail"]), 0, 3)
	values["volume"] = clampi(int(values["volume"]), 0, 100)
	values["sensitivity"] = clampf(float(values["sensitivity"]), 0.4, 2.5)
	values["lod"] = clampi(int(values["lod"]), 0, 3)
	values["vsync"] = bool(values["vsync"])


func save_settings() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(values, "\t"))


func apply_all() -> void:
	_apply_resolution()
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(values.fps_limit)
	_apply_msaa()
	_apply_shadows()
	_apply_distance()
	_apply_grass()
	_apply_lod()
	_apply_sky_detail()
	_apply_volume()


func _apply_resolution() -> void:
	if OS.has_feature("web"):
		return
	if DisplayServer.get_name() == "headless":
		return
	if int(values.resolution) == 3:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var size: Vector2i = RESOLUTIONS[int(values.resolution)]
	DisplayServer.window_set_size(size)
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_position((screen - size) / 2)


func _apply_msaa() -> void:
	var viewport: Viewport = game.get_viewport()
	match int(values.msaa):
		0:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
		2:
			viewport.msaa_3d = Viewport.MSAA_4X
		_:
			viewport.msaa_3d = Viewport.MSAA_2X


func _apply_shadows() -> void:
	var light: DirectionalLight3D = game.key_light
	if light == null:
		return
	var level := int(values.shadows)
	light.shadow_enabled = level > 0
	light.directional_shadow_max_distance = 220.0 if level == 1 else 380.0
	RenderingServer.directional_shadow_atlas_set_size(1024 if level == 1 else 2048, true)


func _apply_distance() -> void:
	if not collected:
		_collect_runtime_nodes()
	var factors := [0.55, 1.0, 1.35]
	var factor: float = factors[int(values.view_distance)]
	for entry in ranged_nodes:
		var node: GeometryInstance3D = entry[0]
		if is_instance_valid(node):
			node.visibility_range_end = entry[1] * factor


## 每个 LOD 档位的 [绘制距离(米), 铺量密度系数]
## 0 低 / 1 中 / 2 高 / 3 极致
const LOD_DISTANCE := [900.0, 1500.0, 2400.0, 3600.0]
const LOD_DENSITY := [0.45, 0.7, 1.0, 1.0]


## 玩家可调的 LOD：同时控制「道具画多远」和「铺量画多少」。
##
## 只影响 planet.gd 生成的 Prop_* 节点（AI 道具的 MultiMesh）。
## lm-* 是每颗星球的签名地标、lf-* 是大地貌件，数量很少，
## 它们不做密度削减（否则远处地标会突然消失），只跟随距离档位。
func _apply_lod() -> void:
	if game == null or game.planets == null:
		return
	var level: int = clampi(int(values.lod), 0, 3)
	var distance: float = LOD_DISTANCE[level]
	var density: float = LOD_DENSITY[level]
	for planet in game.planets:
		if planet == null or not is_instance_valid(planet):
			continue
		for node in planet.find_children("Prop_*", "MultiMeshInstance3D", true, false):
			var mmi := node as MultiMeshInstance3D
			if mmi == null or mmi.multimesh == null:
				continue
			var n: String = String(mmi.name)
			# 地标/地貌件：只有距离档位，不削密度
			if n.contains("lm-") or n.contains("lf-"):
				mmi.visibility_range_end = distance * 1.6
				mmi.multimesh.visible_instance_count = -1
				continue
			mmi.visibility_range_end = distance
			var total: int = mmi.multimesh.instance_count
			mmi.multimesh.visible_instance_count = (
				-1 if density >= 0.999 else maxi(1, int(float(total) * density)))


func _apply_grass() -> void:
	if not collected:
		_collect_runtime_nodes()
	var fraction := 0.45 if int(values.grass) == 0 else 1.0
	for entry in ground_scatters:
		var node: MultiMeshInstance3D = entry[0]
		if is_instance_valid(node) and node.multimesh != null:
			var total: int = node.multimesh.instance_count
			node.multimesh.visible_instance_count = int(total * fraction)


## 星空精细度交给 main.gd 推给天空着色器 —— 那里是唯一知道 sky_material 的地方。
func _apply_sky_detail() -> void:
	if game.has_method("apply_sky_detail"):
		game.apply_sky_detail(int(values.sky_detail))


func _apply_volume() -> void:
	var volume := int(values.volume)
	AudioServer.set_bus_mute(0, volume <= 0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(volume) / 100.0, 0.0001)))


func _collect_runtime_nodes() -> void:
	collected = true
	ranged_nodes.clear()
	ground_scatters.clear()
	for node in game.find_children("*", "GeometryInstance3D", true, false):
		if node.visibility_range_end > 0.0:
			ranged_nodes.append([node, node.visibility_range_end])
	for node in game.find_children("*", "MultiMeshInstance3D", true, false):
		if node.is_in_group("ground_scatter") and node.multimesh != null:
			ground_scatters.append([node, node.multimesh.instance_count])


func set_quality(quality: String) -> void:
	values.quality = quality
	match quality:
		"low":
			values.msaa = 0
			values.shadows = 1
			values.view_distance = 0
			values.grass = 0
			values.sky_detail = 0
			values.lod = 0
		"high":
			values.msaa = 2
			values.shadows = 2
			values.view_distance = 2
			values.grass = 1
			values.sky_detail = 3
			values.lod = 3
		_:
			values.quality = "medium"
			values.msaa = 1
			values.shadows = 2
			values.view_distance = 1
			values.grass = 1
			values.sky_detail = 1
			values.lod = 2
	apply_all()
	save_settings()


func set_resolution(index: int) -> void:
	values.resolution = clampi(index, 0, 3)
	_apply_resolution()
	save_settings()


func set_vsync(enabled: bool) -> void:
	values.vsync = enabled
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)
	save_settings()


func set_fps_limit(limit: int) -> void:
	values.fps_limit = limit
	Engine.max_fps = limit
	save_settings()


func set_msaa(level: int) -> void:
	values.msaa = clampi(level, 0, 2)
	values.quality = "custom"
	_apply_msaa()
	save_settings()


func set_shadows(level: int) -> void:
	values.shadows = clampi(level, 0, 2)
	values.quality = "custom"
	_apply_shadows()
	save_settings()


func set_view_distance(level: int) -> void:
	values.view_distance = clampi(level, 0, 2)
	values.quality = "custom"
	_apply_distance()
	save_settings()


## 0 低 / 1 中 / 2 高 / 3 极致
func set_lod(level: int) -> void:
	values.lod = clampi(level, 0, 3)
	values.quality = "custom"
	_apply_lod()
	save_settings()


func set_grass(level: int) -> void:
	values.grass = clampi(level, 0, 1)
	values.quality = "custom"
	_apply_grass()
	save_settings()


## 0 低 / 1 中 / 2 高 / 3 极致。单独改这一项会把「画面质量」标成自定义，
## 与其它单项设置的既有做法一致。
func set_sky_detail(level: int) -> void:
	values.sky_detail = clampi(level, 0, 3)
	values.quality = "custom"
	_apply_sky_detail()
	save_settings()


func set_volume(volume: int) -> void:
	values.volume = clampi(volume, 0, 100)
	_apply_volume()
	save_settings()


func set_sensitivity(multiplier: float) -> void:
	values.sensitivity = clampf(multiplier, 0.4, 2.5)
	save_settings()


func sensitivity_multiplier() -> float:
	return float(values.get("sensitivity", 1.0))


func reset_defaults() -> void:
	values = {
		"quality": "medium",
		"resolution": 1,
		"vsync": true,
		"fps_limit": 0,
		"msaa": 1,
		"shadows": 2,
		"view_distance": 1,
		"grass": 1,
		"sky_detail": 3,
		"volume": 80,
		"sensitivity": 1.0
	}
	apply_all()
	save_settings()
