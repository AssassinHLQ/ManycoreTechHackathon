extends Node3D

## 第一人称烤棉花糖：签子挂在相机上，火候随时间增长，按 E 取回。

var game
var active := false
var finishing := false
var progress := 0.0
var holding := false
var announced_perfect := false
var announced_scorch := false
var spin := 0.0

var marshmallow: MeshInstance3D
var marshmallow_material: StandardMaterial3D
var char_material: StandardMaterial3D
var char_spots: Array = []
var glow: OmniLight3D
var entry_tween: Tween
var eat_tween: Tween

const HOLD_POSITION := Vector3(0.40, -0.62, -0.52)
const REST_POSITION := Vector3(0.42, -1.08, -0.45)
const COOK_TIME := 8.0
const MAX_PROGRESS := 1.25
const PERFECT_START := 0.62
const PERFECT_END := 0.86
const CAMPFIRE_RANGE := 6.2


func _ready() -> void:
	visible = false
	position = REST_POSITION
	rotation = Vector3(-0.22, 0.0, 0.38)
	var stick := MeshInstance3D.new()
	var stick_mesh := CylinderMesh.new()
	stick_mesh.top_radius = 0.005
	stick_mesh.bottom_radius = 0.008
	stick_mesh.height = 0.66
	stick_mesh.radial_segments = 6
	stick.mesh = stick_mesh
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("8d6647")
	wood.roughness = 0.9
	stick.material_override = wood
	stick.position = Vector3(0, 0.24, 0)
	add_child(stick)

	marshmallow_material = StandardMaterial3D.new()
	marshmallow_material.albedo_color = Color("f3e7cf")
	marshmallow_material.roughness = 0.85
	marshmallow_material.emission_enabled = true
	marshmallow_material.emission = Color("ff9a3c")
	marshmallow_material.emission_energy_multiplier = 0.0

	marshmallow = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.046
	capsule.height = 0.135
	capsule.radial_segments = 16
	capsule.rings = 6
	marshmallow.mesh = capsule
	marshmallow.material_override = marshmallow_material
	marshmallow.position = Vector3(0, 0.49, 0)
	add_child(marshmallow)

	var tip := MeshInstance3D.new()
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.003
	tip_mesh.bottom_radius = 0.004
	tip_mesh.height = 0.11
	tip_mesh.radial_segments = 5
	tip.mesh = tip_mesh
	tip.material_override = wood
	tip.position = Vector3(0, 0.62, 0)
	add_child(tip)

	char_material = StandardMaterial3D.new()
	char_material.albedo_color = Color(0.16, 0.09, 0.05, 0.0)
	char_material.roughness = 0.95
	char_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var spot_layout := [
		[Vector3(0.031, 0.03, 0.028), Vector3(1.0, 0.7, 0.5)],
		[Vector3(-0.026, -0.032, 0.034), Vector3(0.8, 0.6, 0.5)],
		[Vector3(0.004, 0.052, -0.032), Vector3(1.0, 0.5, 0.7)],
		[Vector3(0.038, -0.026, -0.022), Vector3(0.7, 0.9, 0.5)],
		[Vector3(-0.034, 0.026, -0.026), Vector3(0.6, 0.8, 0.6)]
	]
	for layout in spot_layout:
		var spot := MeshInstance3D.new()
		var spot_mesh := SphereMesh.new()
		spot_mesh.radius = 0.014
		spot_mesh.height = 0.018
		spot_mesh.radial_segments = 8
		spot_mesh.rings = 4
		spot.mesh = spot_mesh
		spot.material_override = char_material
		spot.position = layout[0]
		spot.scale = layout[1]
		spot.visible = false
		marshmallow.add_child(spot)
		char_spots.append(spot)

	glow = OmniLight3D.new()
	glow.light_color = Color("ff9d4a")
	glow.light_energy = 0.0
	glow.omni_range = 0.9
	marshmallow.add_child(glow)


func start() -> void:
	if active or finishing or game == null:
		return
	if game.state != "walk" or game.player == null or game.campfire == null:
		return
	if game.player.global_position.distance_to(game.campfire.global_position) > CAMPFIRE_RANGE:
		return
	if entry_tween != null and entry_tween.is_valid():
		entry_tween.kill()
	if eat_tween != null and eat_tween.is_valid():
		eat_tween.kill()
	active = true
	progress = 0.0
	spin = 0.0
	holding = false
	announced_perfect = false
	announced_scorch = false
	marshmallow.scale = Vector3.ONE
	marshmallow.rotation = Vector3.ZERO
	marshmallow.visible = true
	for spot in char_spots:
		spot.visible = false
	char_material.albedo_color.a = 0.0
	position = REST_POSITION
	visible = true
	_update_visuals()
	entry_tween = create_tween()
	entry_tween.tween_property(self, "position", HOLD_POSITION, 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	entry_tween.finished.connect(func(): holding = true)
	game.audio.set_roast(true, 0.0)


func cancel(notify := false) -> void:
	if entry_tween != null and entry_tween.is_valid():
		entry_tween.kill()
	if eat_tween != null and eat_tween.is_valid():
		eat_tween.kill()
	var was_active := active
	active = false
	finishing = false
	holding = false
	visible = false
	position = REST_POSITION
	if game != null and game.audio != null:
		game.audio.set_roast(false, 0.0)
	if notify and was_active:
		game.hud.show_toast("离开了篝火，棉花糖还没烤好。", 2.2)


func finish(auto_burned := false) -> void:
	if not active:
		return
	active = false
	finishing = true
	holding = false
	if entry_tween != null and entry_tween.is_valid():
		entry_tween.kill()
	game.audio.set_roast(false, 0.0)

	var ratio := 0.35
	if progress < 0.35:
		ratio = 0.35
	elif progress < PERFECT_START:
		ratio = 0.65
	elif progress < PERFECT_END:
		ratio = 1.0
	elif progress < 1.0:
		ratio = 0.75
	else:
		ratio = 0.15
	var gain := 100.0 * ratio
	game.player.oxygen = minf(100.0, game.player.oxygen + gain)
	game.player.fuel = minf(100.0, game.player.fuel + gain)
	if ratio >= 0.999:
		game.hud.show_toast("棉花糖外脆内软。氧气与喷气燃料已补满。", 3.5)
		game.audio.play_chime()
	elif progress >= PERFECT_START and progress < 1.0:
		game.hud.show_toast("棉花糖微微焦香。氧气 +%d，燃料 +%d。" % [int(gain), int(gain)], 3.0)
		game.audio.play_ui(470.0)
	elif auto_burned or progress >= 1.0:
		game.hud.show_toast("棉花糖烤成炭了，只补回一点燃料。", 3.2)
		game.audio.play_ui(170.0)
	else:
		game.hud.show_toast("棉花糖还是生的。氧气 +%d，燃料 +%d。" % [int(gain), int(gain)], 3.0)
		game.audio.play_ui(320.0)

	eat_tween = create_tween()
	eat_tween.tween_property(marshmallow, "scale", Vector3.ZERO, 0.18)
	eat_tween.tween_callback(_reset_after_eat)


func _reset_after_eat() -> void:
	visible = false
	position = REST_POSITION
	marshmallow.scale = Vector3.ONE
	finishing = false


func quality_label() -> String:
	if progress < 0.35:
		return "还是生的"
	if progress < PERFECT_START:
		return "微微焦黄"
	if progress < PERFECT_END:
		return "火候刚好"
	if progress < 1.0:
		return "有点焦香"
	return "烤成炭了"


func _process(delta: float) -> void:
	if not active or game == null:
		return
	if game.state != "walk":
		cancel(false)
		return
	if game.paused or game.map_open or game.journal_open:
		game.audio.set_roast(false, 0.0)
		return
	if game.player.global_position.distance_to(game.campfire.global_position) > CAMPFIRE_RANGE + 0.6:
		cancel(true)
		return

	progress = minf(MAX_PROGRESS, progress + delta / COOK_TIME)
	if not announced_perfect and progress >= PERFECT_START and progress < PERFECT_END:
		announced_perfect = true
		game.hud.show_toast("火候刚好 —— 现在按 E 取下棉花糖。", 2.4)
		game.audio.play_ui(660.0)
	if not announced_scorch and progress >= 1.0:
		announced_scorch = true
		game.hud.show_toast("边缘开始焦了，快取下来！", 2.0)
		game.audio.play_ui(210.0)
	if progress >= MAX_PROGRESS:
		finish(true)
		return

	spin += delta * (0.7 + progress * 1.4)
	marshmallow.rotation.y = spin
	if holding:
		position = HOLD_POSITION + Vector3(0.0, sin(game.visual_time * 2.1) * 0.006, 0.0)
	_update_visuals()
	game.audio.set_roast(true, clampf(progress, 0.0, 1.0))


func _update_visuals() -> void:
	var p := progress
	var color := _roast_color(p)
	marshmallow_material.albedo_color = color
	var perfect := p >= PERFECT_START and p < PERFECT_END
	marshmallow_material.emission_energy_multiplier = (0.45 + sin(game.visual_time * 7.0) * 0.1) if perfect else 0.0
	var swell := 1.0 + minf(p, 1.0) * 0.14 - maxf(0.0, p - 1.0) * 0.6
	marshmallow.scale = Vector3.ONE * maxf(swell, 0.35)
	var char_amount := clampf((p - 0.45) / 0.45, 0.0, 1.0) * 0.85
	char_material.albedo_color.a = char_amount
	for spot in char_spots:
		spot.visible = char_amount > 0.03
	glow.light_energy = (0.55 + sin(game.visual_time * 6.0) * 0.08) if perfect else (0.22 if p >= 1.0 else 0.0)


func _roast_color(p: float) -> Color:
	if p < 0.35:
		return Color("f3e7cf")
	if p < PERFECT_START:
		return Color("f3e7cf").lerp(Color("e0b173"), (p - 0.35) / (PERFECT_START - 0.35))
	if p < PERFECT_END:
		return Color("e0b173").lerp(Color("b9772f"), (p - PERFECT_START) / (PERFECT_END - PERFECT_START))
	if p < 1.0:
		return Color("b9772f").lerp(Color("6b3d1b"), (p - PERFECT_END) / (1.0 - PERFECT_END))
	return Color("6b3d1b").lerp(Color("291b13"), clampf((p - 1.0) / 0.25, 0.0, 1.0))
