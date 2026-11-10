extends Node3D
## 一维星 —— 「A Windy Day」点云资产（CC BY 4.0, Loïc Norgeot）。
##
## 设定（用户原话）：「只有点云组成的星球，远看美丽，但靠近却再也无法观测，
## 作为装饰星球」。
##
## 资产本身是 150 个 POINTS 图元（原始 205 万个点），只有 POSITION + COLOR_0，
## 没有三角面。这在 Godot 里能正常导入（primitive type = 0），但有三个坑：
##
##   1. **顶点色默认不生效**：glTF 导入出来的 StandardMaterial3D 是
##      `vertex_color_use_as_albedo = false`，所以整颗星是纯白的。
##
##   2. **提亮走不通 StandardMaterial3D**（实测）：
##      · `vertex_color_use_as_albedo=true` + `SHADING_MODE_UNSHADED`
##        → unshaded 下 albedo 不参与光照，改亮度参数毫无效果
##      · 用 emission 提亮
##        → emission 是常量，乘不到每个点的顶点色上
##      所以改用 `shaders/one_dim_star.gdshader`：
##      直接把 COLOR（顶点色）× brightness 写进 EMISSION，加法混合。
##
##   3. **点会被光照吃掉**：点云是自发光星尘，不该被太阳照亮/背光变黑
##      → 着色器里 unshaded。
##
## 「靠近就消失」：
##   150 个独立 mesh（每个一个 surface），没有 MultiMesh，
##   所以按 mesh 分批隐藏：远离时全可见，靠近时逐批熄灭，最后整颗不可见。
##   用 `visible` 控制，开销极低。

const PointCloudShader = preload("res://shaders/one_dim_star.gdshader")

## 目标半径（米）。资产烘焙后的原始半径 ≈1.036，缩放到这个尺寸。
const TARGET_RADIUS := 130.0
## 自转速度（弧度/秒）。
const SPIN_SPEED := 0.012
## 点云亮度增益。1.0 = 原始颜色。
## ⚠ 别为了「更亮」把这个调大：实测 2.6 会把夜半球过曝成油画（对比截图
## captures/compare_b_shader.png），细节全丢。资产本身颜色是对的。
const BRIGHTNESS := 1.0
## 靠近到这个距离以内，开始分批熄灭。
const VANISH_START := 420.0
## 靠近到这个距离，全部熄灭。
const VANISH_END := 130.0

var game: Node3D
var model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _spin := 0.0
var _hint_shown := false


func _ready() -> void:
	_build()


func _build() -> void:
	var packed: PackedScene = load("res://assets/models/one-dim-star/model.glb")
	if packed == null:
		push_warning("一维星模型加载失败")
		return
	model = packed.instantiate() as Node3D

	# 所有 surface 换成同一个点云着色器材质
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = PointCloudShader
	shader_mat.set_shader_parameter("brightness", BRIGHTNESS)

	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		_meshes.append(mi)
		# 点云不投影、不参与全局光照
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		for s in range(mesh.get_surface_count()):
			mesh.surface_set_material(s, shader_mat)

	# 缩放到目标半径（烘焙后资产半径 ≈1.036）
	var s := TARGET_RADIUS / 1.036
	model.scale = Vector3.ONE * s
	add_child(model)


func _process(delta: float) -> void:
	_spin += delta * SPIN_SPEED
	rotation.y = _spin

	if _meshes.is_empty():
		return

	# 「靠近就无法观测」：按观察者距离分批熄灭。
	var observer := _nearest_observer()
	if observer == null:
		return
	var dist := global_position.distance_to(observer.global_position)

	if dist >= VANISH_START:
		_set_visible_fraction(1.0)
		_hint_shown = false
		return

	if dist <= VANISH_END:
		_set_visible_fraction(0.0)
		if not _hint_shown and game != null and game.hud != null:
			_hint_shown = true
			game.hud.show_toast("一维星在你观测它时散开了", 3.0)
		return

	var t := (dist - VANISH_END) / (VANISH_START - VANISH_END)
	# 平方曲线：远一点掉得慢，近了骤然消失
	_set_visible_fraction(t * t)


## 按比例点亮前 N 个 mesh。用固定顺序（数组索引）保证不会闪烁。
func _set_visible_fraction(f: float) -> void:
	var n := _meshes.size()
	var keep := int(round(n * clampf(f, 0.0, 1.0)))
	for i in range(n):
		_meshes[i].visible = i < keep


func _nearest_observer() -> Node3D:
	if game == null:
		return null
	var best: Node3D = null
	var best_dist := INF
	if game.ship != null:
		var d: float = global_position.distance_to(game.ship.global_position)
		if d < best_dist:
			best_dist = d
			best = game.ship
	if game.player != null:
		var d: float = global_position.distance_to(game.player.global_position)
		if d < best_dist:
			best = game.player
	return best
