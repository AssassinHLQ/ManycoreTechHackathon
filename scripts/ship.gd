extends Node3D

var game
var camera: Camera3D
var velocity := Vector3.ZERO
var landed := true
var landed_planet
var docked := false
var docked_station
var target
var autopilot := false
var fuel := 100.0
var hull := 100.0
var focus := false
var zoom := 1.0
## 第三人称（看飞船外观）模式。座舱视角看的是机腹斜角，很不好看。
var third_person := false
## 第三人称时相机绕船身转的角度（弧度）。鼠标左右拖动可以绕着看。
var orbit_yaw := 0.0
var orbit_pitch := 0.28
## 第三人称相机的跟随距离（米）。滚轮也能调。
var orbit_distance := 13.0

## 船体椭球半轴（米）。所有贴附件的位置都从它推导，避免悬空。
const HULL_X := 1.75
const HULL_Y := 1.0
const HULL_Z := 3.25
const AUTOPILOT_ACCEL := 230.0
const AUTOPILOT_FUEL_PER_DV := 0.008
const MANUAL_FUEL_PER_DV := 0.00625
## 卡冈图雅引力场里的最大油耗倍率（贴着视界时）。外圈从 1.0 平缓往上涨，
## 进场越深越明显，到内圈是 3 倍 —— 也就是说「想靠推力和它硬顶」几乎一定会烧干。
const BH_FUEL_MULTIPLIER := 3.0
## 倍率曲线的形状：1 = 线性，>1 = 外圈几乎无感、内圈陡增。
const BH_FUEL_CURVE := 2.4
var thrust_level := 0.0
var mouse_sensitivity := 0.0018
const WEB_LOOK_SCALE := 0.5
var engine_materials: Array = []
var engine_lights: Array = []
## 外部模型的尾焰锥体（程序化几何那套没有这个）。用来按推力改长度。
var engine_plumes: Array = []
## 按材质分组的盒体批次，_build_model 末尾统一合并提交。
var _batch := {}
var hull_body: StaticBody3D
var hull_shape: BoxShape3D
var station_velocity := Vector3.ZERO
var last_station_port := Vector3.ZERO
var dock_cooldown := 0.0
var impact_cooldown := 0.0
var fuel_empty_time := 0.0
var fuel_warning_cooldown := 0.0
const FUEL_LIFE_SUPPORT := 90.0
const STATION_COLLISION_RANGE := 400.0
const STATION_COLLISION_MASK := 5

# ── 卡冈图雅的引力 ────────────────────────────────────────────────────────
## 从多远开始有牵引力。再往外就完全自由航行了。
const BH_PULL_RANGE := 7200.0
## 视界半径（飞船在这个半径以内就被吞掉）。
const BH_HORIZON := 120.0
## 远端加速度（天文学上「拉到就回不来」的那圈，换算成游戏单位）。
const BH_ACCEL_FAR := 1.6
## 近端加速度：贴到视界附近时的最大牵引。飞船推力 72 / 喷气 150，
## 所以约 0.70 closeness（离视界 ~2100）开始推不动 —— 那就是「回不来」的界线。
const BH_ACCEL_NEAR := 420.0
## 「逃逸层」系数：内层加速度就是再乘这个数，用来表现「越近越难挣脱」。
## 以前这行只是定义、没接进公式（实测：全项目零引用），所以内圈根本没有
## 「越近越绝望」的额外梯度。现在接上：closeness 超过 BH_ESCAPE_FROM 之后，
## 加速度额外乘一个从 1 涨到 BH_ESCAPE_BOOST 的系数。
const BH_ESCAPE_BOOST := 3.2
## 逃逸层从多近开始生效（closeness，0~1）。
const BH_ESCAPE_FROM := 0.55
## 飞船的三档推力。用来算「推力余量」：余量 = 推力 - 引力。
const SHIP_THRUST := 72.0
const SHIP_BOOST_THRUST := 150.0
const SHIP_BRAKE_DECEL := 260.0

## ── 飞行手感（2026-11-10 第三次修正，这次是真正的目标方案）──
##
## 历史（前两版都错了）：
##   第一版：纯牛顿漂移，鼠标直接转动飞船，A/D 直接横移。
##          → 玩家感觉「在平移」，因为横移让飞船侧向蹭，机头不跟着看的方向。
##   第二版：本喵加了阻尼 + 速度对齐，但**方向逻辑没变**。
##          → 更糟：阻尼违反太空物理（用户当场指出）。
##
## 这一版要的是：
##   1. **鼠标只决定「想看哪里」**，不直接转飞船。
##   2. 飞船**缓慢转向**那个方向（有角速度上限，像真飞机一样转不快）。
##   3. **机头永远指向屏幕中心**（即始终 = 期望朝向）。
##   4. A/D 不再横移，改成**滚转**（战斗机那样压坡度转弯）。
##   5. 遵循宇宙物理：只有推进、引力、撞击能改变速度；**没有任何阻尼**。
##
## 实现方式：
##   · 维护一个「期望朝向」`aim_basis`（鼠标推动它）
##   · 每帧让飞船的实际 basis 用**角速度受限**的方式向 aim_basis 旋转
##   · 机头 -Z 永远收敛到 aim 的 -Z，所以「头朝屏幕中心」自动成立
##   · 速度只由推力/引力改变，飞船转向不直接改速度矢量
##     （但推力方向随机头，所以转向后推进自然改变速度方向）

## 期望朝向（鼠标推动的「想看的方向」）。飞船会缓慢追上来。
var aim_basis := Basis.IDENTITY

## 最大角速度（弧度/秒）。这是「转得多快」的上限 ——
## 2.4 约合 137°/秒，像战斗机而不是陀螺。
const MAX_TURN_RATE := 2.4
## 角速度的加速度（弧度/秒²）。有它才不是「瞬间到位」，而是慢慢起转、慢慢停。
const TURN_ACCEL := 9.0
## 当前角速度（世界空间轴向量，长度 = 弧度/秒）。
var _turn_velocity := Vector3.ZERO

## 滚转速率（弧度/秒），A/D 控制。
const ROLL_RATE := 2.0
## 鼠标灵敏度（每像素转多少弧度）。
const AIM_SENSITIVITY := 0.0022

## 推进速度上限（米/秒）。只限制推力能加速到多快，不拦惯性。
const SHIP_MAX_SPEED := 420.0
const SHIP_BOOST_MAX_SPEED := 700.0
## 外圈切向加速度占总牵引的比例。太小会笔直撞进去，太大又几乎不会被吸走。
const BH_TANGENT_RATIO := 0.5
## ── 防「擦边逃逸」────────────────────────────────────────────────
## 玩家实测能靠引力弹弓从黑洞旁边擦边过去。原因是纯径向引力只改方向、
## 不改速度大小，速度够快就能走双曲线轨道溜掉。
## 下面三个参数在近黑洞区域强行吃掉切向速度，让高速飞船也逃不掉。
##
## 从多近开始吃切向速度（closeness，0~1）。0.62 约合离黑洞 4100。
const BH_CAPTURE_FROM := 0.62
## 「逃逸速度」参考值：切向速度超过它的倍数越多，被吃得越快。
## 飞船速度上限是 1600，取 520 让高速擦边也躲不过。
const BH_ESCAPE_SPEED := 520.0
## 切向速度的吞噬速率（每秒占切向速度的比例，还会乘超速倍数）。
const BH_TANGENT_SINK := 1.6
## 被吃掉的切向动量有多少转成向心加速度（让它真的被卷进去，而不是单纯刹停）。
const BH_SINK_TO_INWARD := 0.9

## ── 强制捕获兜底 ─────────────────────────────────────────────────
## 进了这个半径就别想走：不管速度多少，切向速度被吃掉、径向速度被拉满。
## 120 是视界，这里留出一段缓冲区，让「已经没救了」的观感提前出现，
## 而不是等贴脸才判定。
##
## 取 2400：实测 3000 处、1600 全速擦边时，仅靠引力+切向吞噬仍能逃出去
## （60 秒后飞到 44645 之外）。把兜底半径放到 2400，让最高速的擦边也躲不过。
const BH_FORCE_CAPTURE := 2400.0
## 强制捕获时每秒吃掉多少切向速度（占总切向速度的比例，1.0 = 秒杀）。
const BH_FORCE_BRAKE := 3.0
## 强制捕获时保持的最小向心速度。
const BH_FORCE_INWARD := 180.0
## 捕获锁存：一旦进过 BH_FORCE_CAPTURE 就记住，直到退出这个倍数的外圈才解锁。
## 不锁存的话，1600 全速一帧能飞 26 单位，高速擦边会直接穿过判定圈。
const BH_CAPTURE_RELEASE := 1.35
## 进场后多久之内还保留绕转（秒）。过了这个时间就只剩往里拽。
const BH_ORBIT_FADE := 22.0
## 轨道阻尼系数（每秒）。切向速度每帧按这个比例衰减，让绕转的飞船慢慢螺进，
## 而不是在固定半径上变成一条闭合圆轨道。
const BH_ORBIT_DRAG := 0.28
var bh_orbit_age := 0.0
var bh_distance := INF
var bh_pull := Vector3.ZERO
## 0~1，给 HUD 的牵引强度（1 = 已到视界边缘）。
var bh_pull_strength := 0.0
## 这一帧的**径向**引力加速度（不含切向分量），单位与 SHIP_THRUST 相同。
## HUD 用它算「推力余量」——光报 closeness 会误导：closeness 是距离的归一化，
## 而加速度是 pow(closeness, 2.2) 插值出来的，低区间两者差得很远。
var bh_radial_accel := 0.0
## 卡冈图雅引力带来的额外油耗倍率（1 = 不受影响）。由 _black_hole_pull 每帧算好，
## 推力、喷气、制动、自动航行四处扣油都乘它 —— 越靠近黑洞，同样的动作越费推进剂。
var bh_fuel_multiplier := 1.0
var bh_warn_level := 0
var bh_warn_cooldown := 0.0
## 是否已经被黑洞捕获（锁存）。见 _apply_black_hole_capture 里的说明。
var bh_captured := false


func _ready() -> void:
	_build_model()
	hull_body = StaticBody3D.new()
	hull_body.name = "ShipCollision"
	hull_body.collision_layer = 1
	hull_body.collision_mask = 0
	var hull_collision := CollisionShape3D.new()
	hull_shape = BoxShape3D.new()
	if ship_model_length > 0.01:
		# 外部模型：按实测包围盒的 72% 做碰撞（留出翼尖、天线这类细枝末节）。
		hull_shape.size = Vector3(
			maxf(0.6, ship_model_span * 0.72),
			maxf(0.5, ship_model_height * 0.85),
			maxf(0.8, ship_model_length * 0.72))
		hull_collision.position = Vector3(0.0, ship_model_height * 0.5, 0.0)
	else:
		hull_shape.size = Vector3(3.0, 1.8, 4.6)
		hull_collision.position = Vector3(0, -0.2, 0.2)
	hull_collision.shape = hull_shape
	hull_body.add_child(hull_collision)
	add_child(hull_body)
	camera = Camera3D.new()
	if ship_model_length > 0.01:
		# 座舱相机：放在**机头一侧**的座舱罩里。
		# 旧版这里是 Vector3(0, 机高*0.78, 机长*0.22) —— 机尾方向、高度 78%。
		# 那组数字是照着**旧朝向**（机头在 -X、机身横着）调的，
		# 修正朝向后（机头 -Z）镜头变成从机尾上方斜看机腹，
		# 机头歪在画面角落 —— 玩家说的「视角不正」。
		# 现在的数值来自 tests/probe_ship_cockpit.gd 的实测：
		#   模型局部坐标里，座舱隆起在 Z ≈ -0.24（机头侧）、顶面 Y ≈ 0.348；
		#   换算到游戏尺度（机长 6.5 m，factor ≈ 3.403）：
		#   Z ≈ -0.82 m、Y ≈ 1.18 m。
		# 相机再往机头方向挪一点点、略低于罩顶，这样罩沿不会糊住半个屏幕。
		camera.position = Vector3(0.0, ship_model_height * 0.78, -ship_model_length * 0.125)
	else:
		camera.position = Vector3(0, 1.54, -1.42)
	camera.fov = 72.0
	camera.near = 0.09
	camera.far = 60000.0
	add_child(camera)
	var headlight := SpotLight3D.new()
	headlight.position = Vector3(0, 0.2, -2.5)
	headlight.spot_range = 85.0
	headlight.spot_angle = 38.0
	headlight.light_energy = 2.5
	headlight.light_color = Color("c7e7ff")
	add_child(headlight)
	for child in get_children():
		if child is GeometryInstance3D:
			child.visibility_range_end = 1500.0


func _hull_r(z: float) -> float:
	# 船体是椭球：x 半轴 1.75、y 半轴 1.0、z 半轴 3.25。给定 z 返回归一化半径系数。
	return sqrt(maxf(0.0, 1.0 - pow(z / HULL_Z, 2.0)))



## 翼型截面：六点近似（前缘钝、后缘薄）。
func _wing_section(chord: float, thick: float, x: float, z_off: float, y_off: float) -> PackedVector3Array:
	var le := -chord * 0.5 + z_off
	var te := chord * 0.5 + z_off
	var half := thick * 0.5
	return PackedVector3Array([
		Vector3(x, y_off, le),
		Vector3(x, y_off + half, le + chord * 0.18),
		Vector3(x, y_off + half, te - chord * 0.26),
		Vector3(x, y_off, te),
		Vector3(x, y_off - half, te - chord * 0.26),
		Vector3(x, y_off - half, le + chord * 0.18),
	])


func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, flip: bool) -> void:
	if flip:
		tool.add_vertex(a)
		tool.add_vertex(c)
		tool.add_vertex(b)
		tool.add_vertex(a)
		tool.add_vertex(d)
		tool.add_vertex(c)
	else:
		tool.add_vertex(a)
		tool.add_vertex(b)
		tool.add_vertex(c)
		tool.add_vertex(a)
		tool.add_vertex(c)
		tool.add_vertex(d)


## 渐缩机翼：根部截面 → 翼尖截面（带后掠），六条翼面 + 两端封盖。
func _wing_mesh(span: float, root_chord: float, tip_chord: float,
		root_thick: float, tip_thick: float, sweep: float, side: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flip := side < 0.0
	var root := _wing_section(root_chord, root_thick, 0.0, 0.0, 0.0)
	var tip := _wing_section(tip_chord, tip_thick, span * side, sweep * side, 0.0)
	for i in range(6):
		var j := (i + 1) % 6
		_quad(tool, root[i], root[j], tip[j], tip[i], flip)
	var root_center := Vector3.ZERO
	var tip_center := Vector3.ZERO
	for p in root:
		root_center += p
	for p in tip:
		tip_center += p
	root_center /= 6.0
	tip_center /= 6.0
	for i in range(6):
		var j := (i + 1) % 6
		if flip:
			tool.add_vertex(root_center)
			tool.add_vertex(root[i])
			tool.add_vertex(root[j])
			tool.add_vertex(tip_center)
			tool.add_vertex(tip[j])
			tool.add_vertex(tip[i])
		else:
			tool.add_vertex(root_center)
			tool.add_vertex(root[j])
			tool.add_vertex(root[i])
			tool.add_vertex(tip_center)
			tool.add_vertex(tip[i])
			tool.add_vertex(tip[j])
	tool.generate_normals()
	return tool.commit()


## 外部飞船模型（CC BY 4.0，见 assets/models/LICENSE_MANIFEST.json）。
## 为空串时退回 _build_model() 的程序化几何 —— 保留旧模板，换模型不影响可玩性。
const SHIP_MODEL_PATH := "res://assets/models/ship-fighter/model.glb"
## 模型的朝向**已经在 GLB 里烘焙好了**（tools/slim_ship.py 按 Godot 约定转成
## 机头 -Z、机顶 +Y、翼展 X），运行时**不要再转**。
## 旧版本这里写的是绕 X 轴 +90°，那是因为当时的 GLB 是 Y-up；
## 但实测发现那个旋转只解决了「机顶朝上」，机头仍留在 -X ——
## 飞船是**横着飞**的（前进方向 -Z 与机头差 90°），玩家从座舱看出去是机腹侧面。
## 现在朝向由构建脚本负责并有 tests/probe_ship_facing.gd 六向截图复核。
const SHIP_MODEL_ROTATION := Vector3.ZERO
## 目标机长（米）。原模型机长 1.91 m，放大到和旧程序化船体（全长 6.5 m）一致，
## 否则驾驶员相机、着陆高度、对接口尺度全部要跟着改，还会看起来像个小无人机。
##
## ⚠ 2026-11-09 从 6.5 提到 14.0：玩家身高 1.65 m，而 6.5 m 机长的船
## 机高只有 1.53 m —— **比人还矮**，截图里就像个能一脚踩扁的模型玩具。
## 真实战斗机的量级：F-16 机长 15 m、翼展 9.5 m。14 m 机长对应
## 翼展 10.1 m、机高 3.30 m，站在旁边才有「这是一架战机」的体量感，
## 又不会大到把小岛和台阶压得不像样。
## 注意：改这个值会连带影响碰撞盒、座舱相机、着陆高度与登船判定半径
## （它们都从 ship_model_length / height / span 推导，见 _ready 与 _build_external_model）。
const SHIP_MODEL_TARGET_LENGTH := 14.0
## 落地下压量（米）：land() 把船体原点放在 surface_position(normal, 2.3)，
## 即离地 2.3 m。模型底面是**平的**（没有起落架，见 tests/probe_ship_facing.gd
## 的 -Y 仰视图），所以要让底面贴地就得整体压下 2.3 m。
## 旧值 0.96 是照着**旧朝向**的模型调的 —— 那时机头还在 -X（横着飞），
## 修正朝向后模型底面相对原点的位置变了，0.96 会让船悬空 1.34 m。
const SHIP_MODEL_GROUND_SINK := 2.3
## 模型原始机长（Z, 米），用来把碰撞盒与相机按比例摆到船体上。
var ship_model_length := 0.0
var ship_model_height := 0.0
var ship_model_span := 0.0


## 尝试实例化外部模型。成功返回 true 并填好实测尺寸，失败返回 false 走程序化几何。
func _build_external_model() -> bool:
	if SHIP_MODEL_PATH == "" or not ResourceLoader.exists(SHIP_MODEL_PATH):
		return false
	var packed := load(SHIP_MODEL_PATH) as PackedScene
	if packed == null:
		return false
	var holder := Node3D.new()
	holder.name = "ShipModel"
	var model := packed.instantiate() as Node3D
	if model == null:
		holder.free()
		return false
	model.rotation = SHIP_MODEL_ROTATION
	holder.add_child(model)
	add_child(holder)

	# 实测包围盒：转完之后 X = 翼展，Y = 机高，Z = 机长。
	# 关键：只能用相对 holder 的局部变换算，绝不能用 global_transform ——
	# _ready() 时飞船自身还没被摆到世界位置，global 坐标是没有意义的
	# （实测过：拿 global 算会把 holder.position 推成 -12248，模型直接飞出天际）。
	var bounds := AABB()
	var first := true
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			# 从 mi 到 model 的相对变换（model 是 holder 的直接子节点，已带朝向旋转）
			var rel := Transform3D.IDENTITY
			var walker: Node = mi
			while walker != null and walker != model:
				rel = (walker as Node3D).transform * rel
				walker = walker.get_parent()
			if walker == model:
				rel = model.transform * rel
			var box: AABB = rel * mi.get_aabb()
			if first:
				bounds = box
				first = false
			else:
				bounds = bounds.merge(box)
		for child in node.get_children():
			stack.append(child)
	if first:
		return false
	# 把模型中心挪到原点、底部贴 y=0。注意顺序：先按 factor 缩放，再用缩放后的
	# 包围盒算偏移 —— 之前写成 holder.position *= factor 会把模型往下推，直接陷进地形。
	var center := bounds.get_center()
	ship_model_span = absf(bounds.size.x)
	ship_model_height = absf(bounds.size.y)
	ship_model_length = absf(bounds.size.z)
	var factor := 1.0
	if ship_model_length > 0.001:
		factor = SHIP_MODEL_TARGET_LENGTH / ship_model_length
		ship_model_span *= factor
		ship_model_height *= factor
		ship_model_length *= factor
	holder.scale = Vector3.ONE * factor
	holder.position = Vector3(-center.x * factor, -bounds.position.y * factor - SHIP_MODEL_GROUND_SINK, -center.z * factor)
	# 外部模型只有网格和贴图，**没有尾焰** —— 程序化几何里那几块发光盘不会自动出现。
	# 玩家反馈「飞船没尾焰吗」，就是这里缺了。补三束喷焰，坐标用模型局部空间
	# 挂在 holder 下，自动跟着 factor 缩放。
	_build_external_exhaust(holder, bounds)
	return true


## 按实测包围盒在机尾补三束喷焰（外部模型专用，见 _build_external_model）。
##
## 为什么要手写：GLB 里只有网格 + 贴图，没有「这里在喷火」的信息；
## 程序化几何那套 engine_materials 是在 _build_model() 里创建的，
## 走外部模型分支时**根本不会执行**，于是运行时一个发光材质都没有，
## 尾焰自然就没了。
##
## 坐标全部用**模型局部空间**（挂在 holder 下）：
##   · holder.scale = factor，所以这里写 0.3 就是 0.3×factor 米；
##   · 改 SHIP_MODEL_TARGET_LENGTH 时这里不用动。
## 横向排三束是因为机尾实测是一个宽 0.34（占翼展 25%）的喷口簇，
## 截图里也看得出是三个并排的喷口。
func _build_external_exhaust(holder: Node3D, bounds: AABB) -> void:
	var tail_z: float = bounds.position.z + bounds.size.z
	var nozzle_y: float = bounds.position.y + bounds.size.y * 0.37
	var length := bounds.size.z
	var span := bounds.size.x

	# 外焰：加法混合。**必须用顶点色做沿轴渐变**，否则整根锥体亮度一致，
	# 屏幕上就是一块白色实心板（第一版就栽在这）。
	# vertex_color_use_as_albedo 让顶点色直接当颜色/透明度用。
	var flame := StandardMaterial3D.new()
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame.vertex_color_use_as_albedo = true
	flame.albedo_color = Color(0.55, 0.90, 1.0, 1.0)
	flame.emission_enabled = true
	flame.emission = Color(0.30, 0.72, 1.0)
	flame.emission_energy_multiplier = 0.55
	flame.cull_mode = BaseMaterial3D.CULL_DISABLED
	engine_materials.append(flame)

	# 内焰核心：更小更亮，接近白色
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	core_mat.vertex_color_use_as_albedo = true
	core_mat.albedo_color = Color(0.92, 0.98, 1.0, 1.0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.75, 0.93, 1.0)
	core_mat.emission_energy_multiplier = 1.1
	core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	engine_materials.append(core_mat)

	# 三束喷口横向间距：实测机尾喷口簇宽度只占翼展约 25%
	# （tests/probe_ship_nozzles.gd 量到 x ∈ ±0.172，翼展 1.378）。
	# 取 0.075 让三束都落在簇内，超出就会从机翼上穿出去 —— 那是错的。
	for i in range(3):
		var side := float(i - 1)                    # -1 / 0 / +1
		var nozzle := Vector3(side * span * 0.075, nozzle_y, tail_z)

		# 外层火舌：细长、尾端收尖并淡出
		var plume := MeshInstance3D.new()
		plume.mesh = _plume_mesh(length * 0.26, length * 0.055, 14)
		plume.material_override = flame
		plume.position = nozzle
		plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(plume)
		engine_plumes.append(plume)

		# 内层亮芯：短一半，贴合喷口
		var core := MeshInstance3D.new()
		core.mesh = _plume_mesh(length * 0.13, length * 0.028, 12)
		core.material_override = core_mat
		core.position = nozzle
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(core)

		# 尾灯：照亮机尾地面
		var light := OmniLight3D.new()
		light.position = nozzle + Vector3(0.0, 0.0, length * 0.10)
		light.light_color = Color("67dceb")
		light.light_energy = 0.0
		light.omni_range = span * 1.6
		holder.add_child(light)
		engine_lights.append(light)


## 生成一束尾焰网格：从喷口（z=0，粗、亮）沿 +Z 收尖（z=len，细、透明）。
## 顶点色带 alpha，配合 vertex_color_use_as_albedo 做出真实的「烧到尾端就散开」。
##
## 为什么要手搓 ArrayMesh：CylinderMesh 的顶点色全是一样���，
## 拿它做加法混合只能得到一块亮度均匀的实心板。
func _plume_mesh(length: float, radius: float, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 沿长度分 4 段，让淡出是渐变而不是突变
	var rings := 4
	for r in range(rings):
		var t0 := float(r) / rings
		var t1 := float(r + 1) / rings
		var z0 := length * t0
		var z1 := length * t1
		# 半径往后收窄：喷口处最粗，尾端收到 12%
		var rad0 := radius * (1.0 - 0.88 * t0)
		var rad1 := radius * (1.0 - 0.88 * t1)
		# 透明度：喷口 0.85 → 尾端 0
		var a0 := 0.85 * (1.0 - t0) * (1.0 - t0)
		var a1 := 0.85 * (1.0 - t1) * (1.0 - t1)
		for s in range(sides):
			var ang0 := TAU * float(s) / sides
			var ang1 := TAU * float(s + 1) / sides
			var p00 := Vector3(cos(ang0) * rad0, sin(ang0) * rad0, z0)
			var p01 := Vector3(cos(ang1) * rad0, sin(ang1) * rad0, z0)
			var p10 := Vector3(cos(ang0) * rad1, sin(ang0) * rad1, z1)
			var p11 := Vector3(cos(ang1) * rad1, sin(ang1) * rad1, z1)
			# 法线朝内（cull_disabled，两面都画）；用顶点法线让光照稳定
			var n0 := Vector3(cos(ang0), sin(ang0), 0.0)
			var n1 := Vector3(cos(ang1), sin(ang1), 0.0)
			_tri_colored(st, p00, n0, a0, p01, n1, a1, p11, n1, a1)
			_tri_colored(st, p00, n0, a0, p11, n1, a1, p10, n0, a1)
	st.generate_tangents()
	return st.commit()


func _tri_colored(st: SurfaceTool, a: Vector3, na: Vector3, aa: float,
		b: Vector3, nb: Vector3, ab: float,
		c: Vector3, nc: Vector3, ac: float) -> void:
	st.set_color(Color(1.0, 1.0, 1.0, aa))
	st.set_normal(na)
	st.add_vertex(a)
	st.set_color(Color(1.0, 1.0, 1.0, ab))
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_color(Color(1.0, 1.0, 1.0, ac))
	st.set_normal(nc)
	st.add_vertex(c)


func _build_model() -> void:
	# 优先用外部模型；没有就退回程序化几何（原逻辑一行没删）。
	if _build_external_model():
		return
	var ivory := _material(Color("b9b6a6"))
	ivory.metallic = 0.35
	ivory.roughness = 0.5
	var ivory_dark := _material(Color("9a9688"))
	ivory_dark.metallic = 0.35
	ivory_dark.roughness = 0.58
	var dark := _material(Color("26363e"))
	dark.metallic = 0.6
	var dark_soft := _material(Color("1b262c"))
	dark_soft.metallic = 0.45
	var copper := _material(Color("8d5a3d"))
	copper.metallic = 0.5
	var trim := _material(Color("7f8f8c"))
	trim.metallic = 0.75
	trim.roughness = 0.32
	var glass := _material(Color("224f63"), 0.3)
	glass.metallic = 0.55
	glass.roughness = 0.18
	var screen_mat := _material(Color("79e0ec"), 1.6)
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var seam := _material(Color("141c21"))
	seam.metallic = 0.3
	seam.roughness = 0.7

	# ===== 主壳体 =====
	var body := _mesh(_sphere(1.0, 26, 16), ivory, Vector3.ZERO)
	body.scale = Vector3(HULL_X, HULL_Y, HULL_Z)
	add_child(body)

	# ===== 两侧船壳板：贴着椭球表面，越靠艏艉越窄 =====
	for side in [-1.0, 1.0]:
		for z in [-2.15, -1.15, -0.15, 0.85, 1.85]:
			var r: float = _hull_r(z)
			if r < 0.30:
				continue
			var plate_x: float = side * HULL_X * r * 0.985
			var plate: MeshInstance3D = _mesh(_box(Vector3(0.075, 0.62 * r, 0.86)), ivory_dark,
				Vector3(plate_x, 0.06 * r, z))
			plate.rotation.y = side * (0.05 + 0.09 * absf(z) / HULL_Z)
			add_child(plate)
			# 板缝：贴在板与板之间的细暗条
			_batch_box(Vector3(0.03, 0.5 * r, 0.035), seam,
				Transform3D(Basis.IDENTITY, Vector3(plate_x + side * 0.03, 0.05 * r, z + 0.46 * r)))
		# 舷侧灯带：沿壳体中线，长度随船体收窄
		var strip: MeshInstance3D = _mesh(_box(Vector3(0.03, 0.05, 2.9)), screen_mat,
			Vector3(side * (HULL_X * _hull_r(0.0) * 0.99 - 0.01), -0.14, -0.35))
		add_child(strip)

	# ===== 背脊：紧贴壳体顶部的低矮整流脊 =====
	var spine := _mesh(_cylinder(0.20, 0.34, 3.1, 10), ivory_dark, Vector3(0, HULL_Y * 0.86, 0.35))
	spine.rotation.x = PI * 0.5
	add_child(spine)
	for i in range(3):
		var vent := _mesh(_box(Vector3(0.30, 0.04, 0.20)), seam, Vector3(0, HULL_Y * 0.90, -0.30 + i * 0.55))
		add_child(vent)

	# ===== 舰首：锥形鼻 + 探针 + 前照灯 =====
	var nose := _mesh(_cylinder(0.10, 0.62, 1.35, 14), ivory, Vector3(0, 0.0, -(HULL_Z * 0.86)))
	nose.rotation.x = -PI * 0.5
	add_child(nose)
	var nose_tip := _mesh(_cylinder(0.015, 0.11, 0.62, 10), trim, Vector3(0, 0.0, -(HULL_Z * 0.86) - 0.95))
	nose_tip.rotation.x = -PI * 0.5
	add_child(nose_tip)
	add_child(_mesh(_sphere(0.085, 10, 6), screen_mat, Vector3(0, 0.0, -(HULL_Z * 0.86) - 1.28)))
	_light_add(Vector3(0, 0.0, -HULL_Z * 0.80), Color("cfe9ff"), 1.0, 5.0)

	# ===== 腹部：深色底板 + 舱门 + 抓握条 =====
	var belly_y := -HULL_Y * 0.72
	add_child(_mesh(_box(Vector3(1.9, 0.42, 3.3)), dark, Vector3(0, belly_y, 0.25)))
	add_child(_mesh(_box(Vector3(1.25, 0.09, 1.6)), dark_soft, Vector3(0, belly_y - 0.24, 0.30)))
	for i in range(4):
		_batch_box(Vector3(0.8, 0.04, 0.07), trim,
			Transform3D(Basis.IDENTITY, Vector3(0, belly_y - 0.30, -0.40 + i * 0.38)))
	add_child(_mesh(_box(Vector3(0.05, 0.28, 0.8)), dark_soft, Vector3(0.95, belly_y, -0.75)))

	# ===== 座舱：玻璃罩 + 分段框条 + 纵向梁 + 内饰 =====
	var cockpit_y := HULL_Y * 0.56
	var cockpit := _mesh(_sphere(1.0, 22, 12), glass, Vector3(0, cockpit_y, -1.45))
	cockpit.scale = Vector3(1.15, 0.60, 1.30)
	add_child(cockpit)
	for i in range(7):
		var angle := PI * (0.10 + 0.80 * float(i) / 6.0)
		var p := Vector3(cos(angle) * 1.14, cockpit_y - 0.13, -1.45 + sin(angle) * 1.28)
		var bezel := _mesh(_box(Vector3(0.075, 0.10, 0.30)), trim, p)
		bezel.rotation.y = -angle + PI * 0.5
		add_child(bezel)
	for side in [-1.0, 1.0]:
		var rail := _mesh(_box(Vector3(0.06, 0.08, 2.1)), trim,
			Vector3(side * 0.56, cockpit_y + 0.34, -1.45))
		rail.rotation.x = 0.05
		add_child(rail)
	# 内饰：仪表台 + 三块屏 + 座椅
	add_child(_mesh(_box(Vector3(1.3, 0.14, 0.40)), dark, Vector3(0, cockpit_y - 0.12, -2.20)))
	add_child(_mesh(_box(Vector3(1.0, 0.04, 0.24)), screen_mat, Vector3(0, cockpit_y - 0.04, -2.18)))
	for side in [-1.0, 1.0]:
		add_child(_mesh(_box(Vector3(0.26, 0.035, 0.18)), screen_mat,
			Vector3(side * 0.36, cockpit_y - 0.05, -1.98)))
	add_child(_mesh(_box(Vector3(0.64, 0.26, 0.55)), dark_soft, Vector3(0, cockpit_y - 0.06, -0.95)))
	add_child(_mesh(_box(Vector3(0.64, 0.30, 0.14)), dark_soft, Vector3(0, cockpit_y + 0.16, -0.70)))

	# ===== 机翼：三段渐缩 + 前缘翼梁 + 后缘襟翼 + 翼刀 =====
	var wing_y := -HULL_Y * 0.22
	for side in [-1.0, 1.0]:
		# 主翼：自建渐缩翼型网格（根部厚、翼尖薄、带后掠），不再是三块拼板
		var wing: MeshInstance3D = _mesh(_wing_mesh(4.60, 1.98, 1.30, 0.26, 0.12, 0.30, side), ivory,
			Vector3(side * 0.55, wing_y, 0.42))
		add_child(wing)
		# 前缘翼梁（圆柱，给翼面一条圆润的边）
		var spar := _mesh(_cylinder(0.065, 0.065, 4.15, 10), trim, Vector3(side * 2.95, wing_y + 0.01, -0.58))
		spar.rotation.z = PI * 0.5
		add_child(spar)
		# 后缘襟翼
		var flap := _mesh(_box(Vector3(3.3, 0.07, 0.50)), trim, Vector3(side * 2.75, wing_y - 0.06, 1.32))
		flap.rotation.x = 0.14
		add_child(flap)
		# 翼刀
		add_child(_mesh(_box(Vector3(0.05, 0.26, 1.10)), trim, Vector3(side * 2.60, wing_y + 0.10, 0.40)))
		# 翼尖小翼（斜置短鳍，不是大平板）
		var fin := _mesh(_box(Vector3(0.10, 0.46, 0.95)), copper, Vector3(side * 5.05, wing_y + 0.22, 0.55))
		fin.rotation.z = side * 0.34
		add_child(fin)
		# 翼尖航行灯（左红右绿）
		var nav := _material(Color("ff5a4a") if side < 0.0 else Color("6affa0"), 3.0)
		nav.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		add_child(_mesh(_sphere(0.075, 10, 6), nav, Vector3(side * 5.16, wing_y + 0.40, 0.55)))
		# 翼下挂架 + 传感器吊舱
		add_child(_mesh(_box(Vector3(0.10, 0.24, 0.55)), trim, Vector3(side * 2.85, wing_y - 0.20, 0.30)))
		var pod := _mesh(_cylinder(0.12, 0.15, 0.62, 10), ivory_dark, Vector3(side * 2.85, wing_y - 0.46, 0.30))
		pod.rotation.x = PI * 0.5
		add_child(pod)
		add_child(_mesh(_sphere(0.075, 10, 6), screen_mat, Vector3(side * 2.85, wing_y - 0.46, -0.02)))

	# ===== 引擎舱：挂在机翼下方，尺寸受控 =====
	var engine_y := wing_y - 0.52
	for side in [-1.0, 1.0]:
		var nacelle := _mesh(_cylinder(0.36, 0.44, 2.10, 16), dark, Vector3(side * 2.75, engine_y, 0.95))
		nacelle.rotation.x = PI * 0.5
		add_child(nacelle)
		for i in range(2):
			var band := _mesh(_cylinder(0.47, 0.47, 0.10, 16), trim,
				Vector3(side * 2.75, engine_y, 0.55 + i * 0.80))
			band.rotation.x = PI * 0.5
			add_child(band)
		# 进气口：唇环 + 五片格栅（都在舱体半径内）
		var lip := _mesh(_cylinder(0.45, 0.40, 0.16, 16), trim, Vector3(side * 2.75, engine_y, -0.13))
		lip.rotation.x = PI * 0.5
		add_child(lip)
		for i in range(5):
			_batch_box(Vector3(0.62, 0.035, 0.13), trim, Transform3D(
				Basis(Vector3.RIGHT, 0.30), Vector3(side * 2.75, engine_y, -0.11 + i * 0.055)))
		add_child(_mesh(_cylinder(0.33, 0.33, 0.05, 16), dark_soft, Vector3(side * 2.75, engine_y, -0.06)))
		# 推进器钟口 + 发光盘 + 导流片
		var bell := _mesh(_cylinder(0.46, 0.34, 0.36, 16), trim, Vector3(side * 2.75, engine_y, 2.02))
		bell.rotation.x = PI * 0.5
		add_child(bell)
		var glow_mat := _material(Color("67dceb"), 2.8)
		glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		engine_materials.append(glow_mat)
		var exhaust := _mesh(_cylinder(0.30, 0.30, 0.06, 16), glow_mat, Vector3(side * 2.75, engine_y, 2.16))
		exhaust.rotation.x = PI * 0.5
		add_child(exhaust)
		for i in range(4):
			var vane_angle := TAU * float(i) / 4.0 + 0.4
			_batch_box(Vector3(0.05, 0.20, 0.26), trim, Transform3D(Basis.IDENTITY,
				Vector3(side * 2.75 + cos(vane_angle) * 0.30, engine_y + sin(vane_angle) * 0.30, 2.20)))
		var light := OmniLight3D.new()
		light.position = Vector3(side * 2.75, engine_y, 2.45)
		light.light_color = Color("67dceb")
		light.light_energy = 0.8
		light.omni_range = 6.0
		add_child(light)
		engine_lights.append(light)
		# 引擎挂架
		add_child(_mesh(_box(Vector3(0.14, 0.30, 0.70)), trim, Vector3(side * 2.75, wing_y - 0.28, 0.75)))

	# ===== RCS 姿控口：八处，贴着壳体表面 =====
	var rcs_mat := _material(Color("39474f"))
	rcs_mat.metallic = 0.5
	for entry in [[-0.55, 0.30], [0.30, 0.55], [0.62, -0.20], [-0.20, -0.62]]:
		var z_pos: float = 2.35 * entry[0]
		var r := _hull_r(z_pos)
		for side in [-1.0, 1.0]:
			var port := _mesh(_cylinder(0.06, 0.078, 0.14, 8), rcs_mat,
				Vector3(side * HULL_X * r * 0.93, HULL_Y * r * float(entry[1]), z_pos))
			port.rotation.x = PI * 0.5
			add_child(port)

	# ===== 天线：主桅 + 抛物面 + 鞭状天线 =====
	var mast_base := Vector3(0.55, HULL_Y * 0.72, 1.30)
	add_child(_mesh(_cylinder(0.018, 0.04, 1.35, 6), copper, mast_base + Vector3(0, 0.67, 0)))
	var dish := _mesh(_sphere(0.42, 14, 8), ivory, mast_base + Vector3(0, 1.42, 0))
	dish.scale = Vector3(1.0, 0.20, 1.0)
	add_child(dish)
	add_child(_mesh(_cylinder(0.015, 0.015, 0.32, 6), trim, mast_base + Vector3(0, 1.34, 0)))
	for side in [-1.0, 1.0]:
		var whip := _mesh(_cylinder(0.006, 0.014, 1.10, 5), trim,
			Vector3(side * 0.40, HULL_Y * 0.80, 1.75))
		whip.rotation.z = side * 0.30
		whip.rotation.x = -0.16
		add_child(whip)

	# ===== 起落架：支柱 + 液压杆 + 剪刀撑 + 驻脚 =====
	for leg in [Vector3(-1.15, -0.95, 0.55), Vector3(1.15, -0.95, 0.55), Vector3(0, -0.95, -1.25)]:
		var strut := _mesh(_cylinder(0.07, 0.10, 1.15, 10), dark, leg)
		strut.rotation.z = -signf(leg.x) * 0.30
		add_child(strut)
		var piston := _mesh(_cylinder(0.04, 0.045, 0.62, 8), trim, leg + Vector3(0, -0.26, 0))
		piston.rotation.z = -signf(leg.x) * 0.30
		add_child(piston)
		for s in [-1.0, 1.0]:
			var brace := _mesh(_cylinder(0.018, 0.022, 0.48, 6), trim, leg + Vector3(s * 0.13, -0.42, 0.07))
			brace.rotation.z = s * 0.50
			add_child(brace)
		add_child(_mesh(_box(Vector3(0.52, 0.10, 0.52)), dark, leg + Vector3(0, -0.62, 0)))
		for i in range(2):
			_batch_box(Vector3(0.44, 0.04, 0.08), trim,
				Transform3D(Basis.IDENTITY, leg + Vector3(0, -0.68, -0.13 + i * 0.26)))

	# ===== 尾段：尾锥 + 减速板 + 号牌 =====
	var tail_cone := _mesh(_cylinder(0.44, 0.20, 0.62, 14), ivory_dark, Vector3(0, 0.02, HULL_Z * 0.88))
	tail_cone.rotation.x = PI * 0.5
	add_child(tail_cone)
	for side in [-1.0, 1.0]:
		var brake := _mesh(_box(Vector3(0.85, 0.06, 0.52)), trim, Vector3(side * 0.42, 0.34, HULL_Z * 0.80))
		brake.rotation.z = side * -0.26
		add_child(brake)
		add_child(_mesh(_box(Vector3(0.025, 0.13, 0.95)), screen_mat,
			Vector3(side * (HULL_X * _hull_r(-0.35) - 0.02), 0.38, -0.35)))
	add_child(_mesh(_sphere(0.07, 8, 5), screen_mat, Vector3(0, 0.36, HULL_Z * 0.97)))

	# 批量小件统一提交，减少 draw call
	_batch_flush()


## 姿态控制：让飞船**平滑地**转向 `aim_basis`（鼠标想看的方向）。
##
## 为什么不用 `basis.slerp(aim, delta * k)`：
##   那会让转向速度跟「当前差角」成正比 —— 差角大时瞬间甩过去，
##   差角小时磨磨蹭蹭，既不像飞机，也没法做「转得慢」的体感。
##   玩家看到的就是「鼠标一动船就歪过去了」。
##
## 这里用**角速度 + 角加速度**：
##   1. 算出从当前朝向转到 aim 需要的「角速度轴」（旋转轴 × 差角）
##   2. 用 TURN_ACCEL 让实际角速度追上去，并夹在 MAX_TURN_RATE 以内
##   3. 按这个角速度转一帧
## 效果：飞船像有惯性一样慢慢起转、慢慢停，最高不超过 MAX_TURN_RATE。
##
## ⚠ 这是姿态控制（喷口在做功），不是凭空改速度 —— 速度矢量完全不受影响，
##   符合「不受外力不改变运动状态」。
func _apply_attitude(delta: float) -> void:
	var cur := global_transform.basis.orthonormalized()
	var target := aim_basis.orthonormalized()

	# 当前朝向到目标朝向的「差旋转」
	var diff := target * cur.inverse()
	var q := diff.get_rotation_quaternion()
	# 四元数的角度（0..PI）
	var angle := q.get_angle()
	var axis := q.get_axis()

	if angle < 0.0005 or absf(axis.length()) < 0.0001:
		# 基本对齐了：角速度衰减到 0
		_turn_velocity = _turn_velocity.lerp(Vector3.ZERO, clampf(delta * 12.0, 0.0, 1.0))
		return

	# 目标角速度 = 轴 × 差角（单位：弧度/秒），并限制大小
	var desired := axis.normalized() * angle
	# 差角越大越想转快，但不超过 MAX_TURN_RATE
	var desired_len := minf(angle / maxf(delta, 0.0001), MAX_TURN_RATE)
	desired = desired.normalized() * desired_len

	# 角速度向目标靠拢（受角加速度限制）
	var dv := desired - _turn_velocity
	var max_dv := TURN_ACCEL * delta
	if dv.length() > max_dv:
		dv = dv.normalized() * max_dv
	_turn_velocity += dv
	# 再夹一次上限（防止累积超过）
	if _turn_velocity.length() > MAX_TURN_RATE:
		_turn_velocity = _turn_velocity.normalized() * MAX_TURN_RATE

	# 按角速度转一帧
	var step_angle := _turn_velocity.length() * delta
	if step_angle > 0.0001:
		var step_axis := _turn_velocity.normalized()
		# 不要转过头
		if step_angle > angle:
			step_angle = angle
		var step := Basis(step_axis, step_angle)
		var new_basis := (step * cur).orthonormalized()
		var t := global_transform
		t.basis = new_basis
		global_transform = t


func _unhandled_input(event: InputEvent) -> void:
	if game.state != "ship" or game.paused or game.map_open:
		focus = false
		return
	# 第三人称是观察模式：着陆 / 对接时也要能拖鼠标绕船看，
	# 所以「必须飞行中」这条限制只对座舱视角生效。
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (third_person or (not landed and not docked)):
		if not autopilot:
			# Web 的鼠标位移会被乘以 devicePixelRatio；screen_relative 在 4.7 里与 relative 相同。
			var look_delta: Vector2 = event.relative
			if OS.has_feature("web"):
				look_delta = look_delta / maxf(1.0, DisplayServer.screen_get_scale()) * WEB_LOOK_SCALE
			apply_look(look_delta)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		focus = event.pressed
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if third_person:
				# 第三人称：滚轮调的是**跟随距离**（拉近拉远看飞船），
				# 不是座舱那个长焦 —— 长焦在第三人称没意义。
				orbit_distance = clampf(orbit_distance * 0.9, 4.5, 60.0)
			else:
				zoom = clampf(zoom * 1.18, 1.0, 16.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if third_person:
				orbit_distance = clampf(orbit_distance * 1.1, 4.5, 60.0)
			else:
				zoom = clampf(zoom / 1.18, 1.0, 16.0)
		if zoom < 1.01:
			zoom = 1.0


func apply_look(relative: Vector2) -> void:
	if game.state != "ship" or game.paused or game.map_open:
		return
	# 第三人称是「观察模式」：船停着（landed）或对接中也该能绕圈看。
	if not third_person and (landed or docked or autopilot):
		return
	relative = relative.limit_length(120.0)
	var sensitivity: float = mouse_sensitivity * (game.settings.sensitivity_multiplier() if game.settings != null else 1.0)
	if third_person:
		# 第三人称：鼠标改成「绕着飞船转视角」，不影响飞船朝向。
		orbit_yaw = wrapf(orbit_yaw - relative.x * sensitivity * 2.4, -PI, PI)
		orbit_pitch = clampf(orbit_pitch - relative.y * sensitivity * 1.8, -0.35, 1.15)
		return

	# ── 座舱视角：鼠标**只推动期望朝向 aim_basis**，不直接转飞船 ──
	#
	# 这是本次改动的核心。旧版直接 `rotate_object_local()` —— 鼠标一动飞船立刻
	# 转身，而 A/D 又是横移，于是「鼠标转一点 + 横移一点」看起来就是原地平移。
	# 现在鼠标推动的是「我想看的方向」，飞船要靠**角速度**慢慢追上来，
	# 机头最终会精确指向那个方向（也就是屏幕中心）。
	#
	# 偏航：绕**世界 Y 轴**转（不是飞船自身的 up）——
	#   否则飞船压坡度后，鼠标左右会变成滚转，很难控制。
	# 俯仰：绕**飞船自身的右轴**（pitch 跟随机身，才符合飞行器手感）。
	var yaw := -relative.x * sensitivity * AIM_SENSITIVITY / mouse_sensitivity
	var pitch := -relative.y * sensitivity * AIM_SENSITIVITY / mouse_sensitivity

	# 先算当前期望朝向的 forward 与 right，用来构造新的 aim
	var aim_forward := -aim_basis.z.normalized()
	var aim_right := aim_basis.x.normalized()

	# 俯仰：绕自身右轴，并夹住上下限（别翻过去）
	var pitched := Basis(aim_right, pitch) * aim_forward
	# 限制俯仰角：与世界上方向夹角限制在 [-85°, +85°]
	var up := Vector3.UP
	var cos_limit := cos(deg_to_rad(85.0))
	if pitched.dot(up) > cos_limit:
		# 太朝上了，压回上限
		var flat := (pitched - up * pitched.dot(up)).normalized()
		pitched = (flat * cos_limit + up * sqrt(maxf(0.0, 1.0 - cos_limit * cos_limit))).normalized()
	elif pitched.dot(-up) > cos_limit:
		var flat2 := (pitched + up * pitched.dot(up)).normalized()
		pitched = (flat2 * cos_limit - up * sqrt(maxf(0.0, 1.0 - cos_limit * cos_limit))).normalized()

	# 偏航：绕世界 Y
	var yawed := Basis(Vector3.UP, yaw) * pitched

	# 用「新的 forward + 保持机身上方向尽量不变」重建 aim_basis
	var body_up := aim_basis.y.normalized()
	# 让 up 与 forward 正交
	var right_axis := yawed.cross(body_up)
	if right_axis.length() < 0.001:
		right_axis = yawed.cross(Vector3.RIGHT)
	right_axis = right_axis.normalized()
	var final_up := right_axis.cross(yawed).normalized()
	aim_basis = Basis(right_axis, final_up, -yawed).orthonormalized()


## 第三人称相机：绕着船身转，一直看船。
## 座舱相机是**子节点**（挂在飞船下），所以相机坐标是**船的局部坐标**。
## 要让它看船心，得用局部空间的 look_at —— Node3D.look_at() 用的是全局坐标，
## 直接传局部坐标会转到别的地方去（表现就是「镜头看向太空，看不到船」）。
func _update_third_person_camera(_delta: float) -> void:
	if not third_person:
		return
	var target := Vector3(0.0, ship_model_height * 0.5, 0.0)
	# 相机在船的局部空间里绕圈：yaw 绕 Y，pitch 抬高/压低。
	var offset := Vector3(
		sin(orbit_yaw) * cos(orbit_pitch),
		sin(orbit_pitch),
		cos(orbit_yaw) * cos(orbit_pitch)) * orbit_distance
	camera.position = target + offset
	# 局部空间的朝向：相机的 -Z 要指向船心。
	# 用 Basis.looking_at 手工构造，再转成四元数 —— 这样全程在局部空间里算。
	var dir := (target - camera.position).normalized()
	if dir.length_squared() > 0.0001:
		var up := Vector3.UP
		if absf(dir.dot(up)) > 0.98:
			up = Vector3.FORWARD
		camera.basis = Basis.looking_at(dir, up)
	# 第三人称用固定视场，不再受座舱变焦影响。
	camera.fov = 55.0


## 切换第三人称。返回 true 表示这次切换生效了。
func toggle_third_person() -> bool:
	if game == null or game.state != "ship":
		return false
	third_person = not third_person
	if third_person:
		# 第三人称从「机尾斜后上方」开始看，一眼能看清整艘船。
		orbit_yaw = PI
		orbit_pitch = 0.28
		orbit_distance = 13.0
		# 立刻把相机摆过去 —— 不能等下一帧 _physics_process，
		# 否则切过去的第一帧镜头还留在座舱里（会闪一下）。
		_update_third_person_camera(0.0)
		camera.fov = 55.0
	else:
		# 回座舱：把相机放回座舱位（_ready 里算好的那个）。
		_reset_cockpit_camera()
	game.hud.show_toast("第三人称视角 · 看飞船" if third_person else "座舱视角", 1.8)
	return true


func _reset_cockpit_camera() -> void:
	if ship_model_length > 0.01:
		camera.position = Vector3(0.0, ship_model_height * 0.78, -ship_model_length * 0.125)
	else:
		camera.position = Vector3(0, 1.54, -1.42)
	camera.rotation = Vector3.ZERO
	camera.fov = 72.0


func _physics_process(delta: float) -> void:
	if game.state != "ship" or game.paused or game.supernova_active or game.map_open:
		thrust_level = 0.0
		return
	impact_cooldown = maxf(0.0, impact_cooldown - delta)
	dock_cooldown = maxf(0.0, dock_cooldown - delta)
	# 着陆 / 对接时：姿态锁定在当前朝向，并把 aim 同步过来，
	# 否则下次起飞会因为 aim 停在旧方向而突然甩头。
	if landed or docked:
		aim_basis = global_transform.basis.orthonormalized()
		_turn_velocity = Vector3.ZERO
	if game.station != null:
		var port_now: Vector3 = game.station.docking_point()
		if last_station_port != Vector3.ZERO:
			var measured := (port_now - last_station_port) / maxf(delta, 0.0001)
			station_velocity = measured if measured.length() < 200.0 else Vector3.ZERO
		last_station_port = port_now
	var base_fov := 46.0 if focus else 72.0
	var target_fov := maxf(base_fov / zoom, 3.0)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-delta * 8.0))
	_update_third_person_camera(delta)
	if docked:
		velocity = Vector3.ZERO
		thrust_level = 0.0
		fuel = minf(100.0, fuel + delta * 10.0)
		hull = minf(100.0, hull + delta * 2.0)
		fuel_empty_time = 0.0
		fuel_warning_cooldown = 0.0
		game.player.oxygen = 100.0
		# 对接后跟着站走：远景站会自转，不跟的话船会慢慢「掉」出停靠位。
		# 归航站是绕星公转（位置在变），同理。做法是每帧重贴到站的停靠点。
		if docked_station != null and is_instance_valid(docked_station):
			global_position = docked_station.dock_ship_position()
		if Input.is_action_just_pressed("jump"):
			undock()
		_update_engine(delta)
		return
	if landed:
		velocity = Vector3.ZERO
		thrust_level = 0.0
		fuel = minf(100.0, fuel + delta * 12.0)
		hull = minf(100.0, hull + delta * 2.0)
		fuel_empty_time = 0.0
		fuel_warning_cooldown = 0.0
		game.player.oxygen = 100.0
		if Input.is_action_just_pressed("jump"):
			takeoff()
		_update_engine(delta)
		return

	var planet = game.nearest_planet(global_position)
	var offset: Vector3 = global_position - planet.global_position
	var normal: Vector3 = offset.normalized()
	var altitude: float = offset.length() - planet.radius
	var gravity: Vector3 = -normal * (planet.gravity_strength * clampf(1.0 - altitude / (planet.radius * 0.6), 0.0, 1.0))
	# 卡冈图雅的牵引。它比行星重得多，所以先算它，再和行星重力叠一起。
	gravity += _black_hole_pull(delta)
	var thrusting := false

	if autopilot and target != null:
		var to_target: Vector3 = target.global_position - global_position
		var target_altitude: float = to_target.length() - target.radius
		var desired_speed := clampf((target_altitude - 8.0) * 1.25, 18.0, 900.0)
		if target_altitude < 150.0:
			desired_speed = clampf((target_altitude - 4.0) * 0.28, 3.0, 42.0)
		var aim := _autopilot_aim(target.global_position)
		var desired_direction := (aim - global_position).normalized()
		var desired_velocity := desired_direction * desired_speed
		var before_velocity := velocity
		velocity = velocity.move_toward(desired_velocity, delta * AUTOPILOT_ACCEL)
		var delta_v := velocity.distance_to(before_velocity)
		if delta_v > 0.0001:
			if fuel > 0.0:
				fuel = maxf(0.0, fuel - delta_v * AUTOPILOT_FUEL_PER_DV * bh_fuel_multiplier)
			else:
				velocity = before_velocity
				autopilot = false
				game.hud.show_toast("推进剂耗尽 · 自动航行中止", 3.0)
		var up := normal if altitude < 900.0 else Vector3.UP
		if absf(desired_direction.dot(up)) > 0.96:
			up = Vector3.FORWARD
		var desired_basis := Basis.looking_at(desired_direction, up)
		var transform := global_transform
		transform.basis = transform.basis.slerp(desired_basis, clampf(delta * 3.0, 0.0, 1.0)).orthonormalized()
		global_transform = transform
		thrusting = autopilot and delta_v > 0.02
		thrust_level = 0.8 if thrusting else 0.0
	else:
		# ── 姿态：飞船缓慢转向期望朝向，机头始终对着屏幕中心 ──
		_apply_attitude(delta)

		var thrust := Vector3.ZERO
		# 前后推进照旧；**左右改成滚转**，不再横移。
		# 这是这次改动的关键之一：A/D 横移正是「平移感」的来源。
		thrust.z = Input.get_axis("move_forward", "move_back")
		thrust.y = Input.get_axis("thrust_down", "jump")
		thrust = thrust.limit_length(1.0)
		var boosting := Input.is_action_pressed("jetpack") and fuel > 0.0
		var has_input := thrust.length_squared() > 0.01 or absf(Input.get_axis("move_left", "move_right")) > 0.1

		# 滚转：绕着机头轴转机身（不影响前进方向）
		var roll_input := Input.get_axis("move_right", "move_left")
		if absf(roll_input) > 0.05 and fuel > 0.0:
			var roll := Basis(Vector3.FORWARD, -roll_input * ROLL_RATE * delta)
			aim_basis = (aim_basis * roll).orthonormalized()

		if thrust.length_squared() > 0.01 and fuel > 0.0:
			var acceleration := SHIP_BOOST_THRUST if boosting else SHIP_THRUST
			velocity += global_transform.basis * thrust * acceleration * delta
			fuel = maxf(0.0, fuel - delta * (1.6 if boosting else 0.45) * bh_fuel_multiplier)
			thrusting = true
			thrust_level = 1.0 if boosting else 0.5
		else:
			# 没有推进：尾焰**完全熄灭**（用户要求「没开的时候不要尾焰」）
			thrusting = false
			thrust_level = 0.0

		if Input.is_action_pressed("brake") and fuel > 0.0:
			var before_brake := velocity
			velocity = velocity.move_toward(Vector3.ZERO, delta * SHIP_BRAKE_DECEL)
			var brake_dv := velocity.distance_to(before_brake)
			if brake_dv > 0.0001:
				fuel = maxf(0.0, fuel - brake_dv * MANUAL_FUEL_PER_DV * bh_fuel_multiplier)
				thrusting = true
				thrust_level = 0.35

		# 推进上限：超速时这一帧不加速（不硬压，保留惯性）
		var max_speed: float = SHIP_BOOST_MAX_SPEED if boosting else SHIP_MAX_SPEED
		if thrust.length_squared() > 0.01 and velocity.length() > max_speed:
			velocity -= global_transform.basis * thrust * (SHIP_BOOST_THRUST if boosting else SHIP_THRUST) * delta

		velocity += gravity * delta

	if velocity.length() > 1600.0:
		velocity = velocity.normalized() * 1600.0
	_move_with_station_collision(delta)
	if _apply_black_hole_capture(delta):
		return

	if not docked and not landed and dock_cooldown <= 0.0:
		# 归航站与两座远景站统一处理：谁在范围内就对接谁。
		# 远景站的端口在站顶（自家坐标里），判定半径按它们的体量放大到
		# DOCK_APPROACH_RADIUS 量级，否则 900 米大的站要贴到 24 米才算数，玩家会以为没反应。
		for candidate in _dockable_stations():
			var station_port: Vector3 = candidate.docking_point()
			var reach: float = 24.0
			if candidate.has_method("is_distant_station"):
				reach = candidate.DOCK_SNAP_RADIUS
			if global_position.distance_to(station_port) < reach \
					and (velocity - station_velocity).length() < (18.0 if not candidate.has_method("is_distant_station") else candidate.DOCK_SNAP_SPEED):
				dock_station(candidate)
				return

	planet = game.nearest_planet(global_position)
	offset = global_position - planet.global_position
	normal = offset.normalized()
	altitude = offset.length() - planet.terrain_height(normal)
	if altitude < 3.4:
		var impact_speed := velocity.length()
		if impact_speed < 14.0 or autopilot:
			land(planet)
		else:
			global_position = planet.global_position + planet.surface_position(normal, 5.0)
			velocity = normal * maxf(12.0, impact_speed * 0.42)
			if impact_cooldown <= 0.0:
				hull = maxf(0.0, hull - impact_speed * 0.42)
				impact_cooldown = 1.2
				autopilot = false
				game.hud.show_toast("撞击警告 · 船体 %d%% · X 制动后按 E 着陆" % int(hull), 3.2)
				game.audio.play_impact()
				if hull <= 0.0:
					game.begin_death("飞船在撞击中解体", 4.0)
	var sun_distance := global_position.length()
	if autopilot and sun_distance < game.sun_radius + 500.0:
		autopilot = false
		game.hud.show_toast("自动航行中止：距离恒星过近", 3.0)
	if sun_distance < game.sun_radius + 22.0:
		game.begin_death("飞船坠入了恒星", 4.6)
	elif sun_distance < 950.0:
		var heat_damage := (950.0 - sun_distance) / 950.0 * 22.0 * delta
		hull = maxf(0.0, hull - heat_damage)
		if hull <= 0.0:
			game.begin_death("船体被恒星高温熔穿", 4.2)
	if fuel <= 0.01:
		fuel_empty_time += delta
		fuel_warning_cooldown = maxf(0.0, fuel_warning_cooldown - delta)
		if fuel_warning_cooldown <= 0.0 and fuel_empty_time < FUEL_LIFE_SUPPORT:
			game.hud.show_toast("推进剂耗尽 · 生命维持约 %d 秒后停止" % maxi(0, int(FUEL_LIFE_SUPPORT - fuel_empty_time)), 4.0)
			fuel_warning_cooldown = 15.0
		if fuel_empty_time >= FUEL_LIFE_SUPPORT:
			game.begin_death("推进剂耗尽，飞船在深空失去动力", 4.0)
	else:
		fuel_empty_time = 0.0
	game.audio.set_engine(thrusting, thrust_level)
	_update_engine(delta)


## 卡冈图雅的引力场。
##
## 强度按 1/r² 衰减：在 BH_PULL_RANGE 处大约是 1.6（巡航时几乎察觉不到，只是航线被
## 慢慢掰弯），到视界附近涨到 BH_ACCEL_NEAR。推力只有 72（按 Shift 喷气 150），所以
## 进入内圈之后基本是「看着自己被吸进去」—— 这正是想要的手感。
##
## 外圈加一层「切向拖拽」：飞船会绕着黑洞打转，像被甩进了轨道，而不是笔直撞上去。
## 内圈把这层压掉，改成纯粹往里拽。
##
## 这里只负责算力，落点和死亡判定在 _apply_black_hole_capture 里。
func _black_hole_pull(delta: float) -> Vector3:
	bh_pull = Vector3.ZERO
	bh_pull_strength = 0.0
	bh_radial_accel = 0.0
	bh_fuel_multiplier = 1.0
	if game.gargantua == null:
		bh_distance = INF
		return Vector3.ZERO
	var to_hole: Vector3 = game.gargantua.global_position - global_position
	bh_distance = to_hole.length()
	if bh_distance > BH_PULL_RANGE or bh_distance < 0.001:
		bh_distance = maxf(bh_distance, 0.0)
		bh_orbit_age = 0.0
		return Vector3.ZERO
	bh_orbit_age += delta
	var direction := to_hole / bh_distance
	# 用「离视界的距离」而不是绝对距离来插值，这样近处的加速度才够陡。
	var span := maxf(BH_PULL_RANGE - BH_HORIZON, 1.0)
	var closeness := clampf((BH_PULL_RANGE - bh_distance) / span, 0.0, 1.0)
	var strength := lerpf(BH_ACCEL_FAR, BH_ACCEL_NEAR, pow(closeness, 2.2))
	# 逃逸层：closeness 过了 BH_ESCAPE_FROM 之后，加速度额外乘一个从 1 涨到
	# BH_ESCAPE_BOOST 的系数 —— 表现「越近越难挣脱」。
	# （以前这个系数只定义、没接进公式，所以内圈没有额外梯度，玩家感觉引力不够。）
	var escape_layer := 1.0
	if closeness > BH_ESCAPE_FROM:
		var layer_t := (closeness - BH_ESCAPE_FROM) / maxf(1.0 - BH_ESCAPE_FROM, 0.0001)
		escape_layer = lerpf(1.0, BH_ESCAPE_BOOST, pow(layer_t, 1.5))
	strength *= escape_layer
	bh_pull_strength = closeness
	# 径向分量（不含切向）：HUD 拿它跟推力比，算「推力余量」。
	bh_radial_accel = strength
	# 越靠近黑洞，越要开大推力去对抗牵引，于是同样一次点火烧掉的推进剂更多。
	# 倍率这里就定下来，推力/喷气/制动/自动航行四处的扣油统一乘它。
	bh_fuel_multiplier = lerpf(1.0, BH_FUEL_MULTIPLIER, pow(closeness, BH_FUEL_CURVE))
	var pull := direction * strength
	# ── 擦边逃逸的修法 ──────────────────────────────────────────
	#
	# 问题：玩家实测能靠引力弹弓从黑洞旁边擦边过去，还能逃出来。
	# 原因：纯径向引力只改**方向**、不改**速度大小**。飞船擦边时走的是双曲线轨道，
	# 速度够快就偏一下就溜了 —— 这是真实物理，但在游戏里不行：
	# 卡冈图雅应该是「一旦靠近就别想走」。
	#
	# 做法：在近黑洞区域额外吃切向速度（相当于吸积盘的阻力）,
	# 让高速飞船也被拖住。速率用「速度超出逃逸速度多少」来调 ——
	# 速度越快，吃掉的越多，这样高速度也躲不过。
	var tangential_weight := (1.0 - smoothstep(0.0, BH_ORBIT_FADE, bh_orbit_age)) \
		* (1.0 - smoothstep(0.85, 0.97, closeness))
	if closeness > BH_CAPTURE_FROM:
		# 切向速度（垂直于半径方向的分量）—— 这是「擦边溜走」靠的那个分量。
		var tx := velocity - direction * velocity.dot(direction)
		var tx_speed := tx.length()
		if tx_speed > 0.1:
			# 吃掉的量：近黑洞系数 × 超速倍数。速度越快吃得越狠。
			var grab := smoothstep(BH_CAPTURE_FROM, 1.0, closeness)
			var overspeed := clampf(tx_speed / BH_ESCAPE_SPEED, 0.25, 4.0)
			var bleed := grab * overspeed * BH_TANGENT_SINK * delta
			velocity -= tx * clampf(bleed, 0.0, 0.85)
			# 速度被吃掉后，这部分动量转成一点向心加速度，
			# 让飞船是真的「被卷进去」，而不是单纯停下。
			pull += direction * minf(tx_speed, BH_ESCAPE_SPEED) * grab * BH_SINK_TO_INWARD * delta
	if tangential_weight > 0.001:
		var drift := velocity - direction * velocity.dot(direction)
		var tangent: Vector3
		if drift.length_squared() > 0.0001:
			tangent = drift.normalized()
		else:
			# 正对着黑洞飞：随便取一个垂直于视线的方向，把它推开一点形成绕转。
			tangent = direction.cross(Vector3.UP)
			if tangent.length_squared() < 0.0001:
				tangent = direction.cross(Vector3.RIGHT)
			tangent = tangent.normalized()
		pull += tangent * strength * BH_TANGENT_RATIO * tangential_weight
		# 轨道阻尼：真实的吸积过程靠摩擦耗掉角动量，游戏里也得有这一下。
		# 不然飞船会绕成一条完美的闭合圆轨道、在固定半径上永远打转（实测卡在
		# ~1000 处不动）。这里直接扣掉一点切向速度，让它慢慢往里螺进。
		# 注意：只扣**切向**分量，朝里的那部分速度不动，所以「被吸进去」的手感还在。
		var drag := drift * clampf(BH_ORBIT_DRAG * delta, 0.0, 0.5)
		velocity -= drag
	bh_pull = pull
	return pull

## 探针专用：只读地问「按现在的状态，这一帧会不会被吞掉 / 会不会被强制捕获」，
## 不改任何状态（不触发 begin_death、不动 velocity）。生产路径不走这里。
## 存在的理由：探针要复用真实判定逻辑，否则测的是一份影子实现，
## 改完代码它照样绿 —— 那种测试等于没测。
func _is_swallowed_for_probe(hole_position: Vector3) -> bool:
	var d: float = global_position.distance_to(hole_position)
	return d <= BH_HORIZON

## 视界判定 + 分档警告。返回 true 表示这一帧已经被吞掉，调用方应当停止后续物理。
func _apply_black_hole_capture(delta: float) -> bool:
	if game.gargantua == null:
		return false
	# 自己再量一次距离：bh_distance 是 _black_hole_pull 里写的，而那个函数在上一帧
	# 就可能因为各种原因提前 return。判定视界这么要紧的事不该依赖别处的副作用。
	bh_distance = global_position.distance_to(game.gargantua.global_position)
	bh_warn_cooldown = maxf(0.0, bh_warn_cooldown - delta)
	if bh_distance <= BH_HORIZON:
		autopilot = false
		velocity = Vector3.ZERO
		# 死亡过场 1.6 秒：越过视界就是被吞掉了，没有「在黑洞里飘一会儿」这回事。
		# 原来给的是 5.2 秒，玩家看着镜头继续渲染，像是被吸进去还在里面待着。
		game.begin_death("飞船越过了卡冈图雅的视界", 1.6)
		return true
	# ── 强制捕获：进了内圈就别想走 ─────────────────────────────
	# 引力本身只改方向、不改速度大小，所以理论上高速飞船还能靠双曲线轨道
	# 擦边溜掉。BH_FORCE_CAPTURE 以内直接兜底：不管速度多少，都往视界里拽。
	# 这是「游戏性优先于物理正确性」的一处刻意选择 —— 卡冈图雅不是可以
	# 刷引力弹弓的景点，靠近它就该有代价。
	#
	# 注意用 bh_captured 锁存：1600 全速时一帧能飞 26 单位，只在「这一帧
	# 恰好落在半径内」判定会被直接穿过去（实测 3000 处 1600 速就从兜底圈
	# 里漏了出去）。一旦进过捕获圈就记住，直到退出更外圈才解锁。
	if bh_distance <= BH_FORCE_CAPTURE:
		bh_captured = true
	elif bh_distance > BH_FORCE_CAPTURE * BH_CAPTURE_RELEASE:
		bh_captured = false
	if bh_captured:
		var inward: Vector3 = (game.gargantua.global_position - global_position).normalized()
		# 先把切向速度吃掉，再把径向速度拉满，保证一定会落到视界里。
		var tangential_v: Vector3 = velocity - inward * velocity.dot(inward)
		velocity -= tangential_v * clampf(BH_FORCE_BRAKE * delta, 0.0, 1.0)
		var inward_speed: float = velocity.dot(inward)
		if inward_speed < BH_FORCE_INWARD:
			velocity += inward * (BH_FORCE_INWARD - inward_speed)
		if bh_warn_cooldown <= 0.0:
			bh_warn_cooldown = 2.0
			game.hud.show_toast("⚠ 已被卡冈图雅捕获 · 引擎无法挽回", 2.2)
	# 自动航行一旦进了内圈就中止：让它继续算会自己撞进视界，玩家会以为程序出 bug。
	if autopilot and bh_distance < BH_PULL_RANGE * 0.62:
		autopilot = false
		game.hud.show_toast("自动航行中止：卡冈图雅的引力吞掉了航线", 3.6)
	# 分档按**推力余量**算，不再按距离百分比。
	# 以前按 closeness 分档有个硬伤：closeness 是距离的归一化，而加速度是
	# pow(closeness, 2.2) 插值出来的，低区间两者差得很远 —— 实测在离黑洞
	# 约 4000 处引力（83）就已经超过推力（72）、推不动了，可那时候 HUD 才刚
	# 进入「一级」警告，玩家完全不知道已经逃不出去了。
	# 现在直接拿实际径向加速度跟三档推力比：
	#   还在被慢慢掰弯                        -> 一级
	#   普通推力开始吃力（不到喷气的 1/3 余量） -> 二级
	#   连喷气（150）都顶不住                  -> 三级
	var level := 0
	var thrust_margin := SHIP_THRUST - bh_radial_accel
	if bh_radial_accel >= SHIP_BOOST_THRUST:
		level = 3
	elif thrust_margin <= SHIP_BOOST_THRUST * 0.35:
		level = 2
	elif bh_radial_accel > BH_ACCEL_FAR * 2.0:
		level = 1
	if level > bh_warn_level and bh_warn_cooldown <= 0.0:
		bh_warn_cooldown = 6.0 if level == 1 else 9.0
		match level:
			1:
				game.hud.show_toast("引力警告 · 前方黑洞正在拉扯航线 · 建议调头", 3.6)
			2:
				game.hud.show_toast("引力警告 · 推力已开始不敌牵引 · 按住 Shift 喷气或远离", 3.8)
			3:
				game.hud.show_toast("⚠ 临界 · 你已经逃不掉了 · 视界就近在眼前", 4.0)
			_:
				pass
		game.audio.play_ui(220.0 - level * 30.0)
	elif level < bh_warn_level:
		# 往外退时把档位重置，这样下次再探头还会提醒。
		bh_warn_cooldown = maxf(bh_warn_cooldown, 3.0)
	bh_warn_level = level
	if bh_distance < BH_HORIZON * 2.6 and bh_warn_cooldown <= 0.0:
		game.hud.show_toast("⚠ 视界边缘 · 引擎已接近极限", 2.6)
		bh_warn_cooldown = 2.4
	return false


func _move_with_station_collision(delta: float) -> void:
	var station = game.station
	var motion := velocity * delta
	if station == null or global_position.distance_to(station.global_position) > STATION_COLLISION_RANGE:
		global_position += motion
		return
	if _station_blocked(global_position):
		var rest := _station_rest(global_position)
		var normal: Vector3 = rest.get("normal", (global_position - station.global_position).normalized())
		var escape: Vector3 = global_position + normal * 1.5
		if _station_blocked(escape):
			normal = -normal
			escape = global_position + normal * 1.5
		if not _station_blocked(escape):
			global_position = escape
		velocity = normal * 8.0
		return
	if motion.length_squared() < 0.000001:
		return
	var steps := clampi(ceili(motion.length() / 3.0), 1, 32)
	var step := motion / float(steps)
	for _i in range(steps):
		var next := global_position + step
		if not _station_blocked(next):
			global_position = next
			continue
		var hit := _station_rest(next)
		var hit_normal: Vector3 = hit.get("normal", (global_position - station.global_position).normalized())
		var relative_velocity := velocity - station_velocity
		if hit_normal.dot(relative_velocity) > 0.0:
			hit_normal = -hit_normal
		var impact_speed := relative_velocity.length()
		if relative_velocity.dot(hit_normal) < 0.0:
			velocity -= hit_normal * relative_velocity.dot(hit_normal)
		velocity *= 0.22
		if autopilot:
			autopilot = false
			velocity = Vector3.ZERO
			game.hud.show_toast("自动航行中止：前方是归航站", 3.0)
		elif impact_speed > 14.0 and impact_cooldown <= 0.0:
			hull = maxf(0.0, hull - (impact_speed - 10.0) * 0.55)
			impact_cooldown = 1.2
			game.hud.show_toast("撞击空间站 · 船体 %d%% · X 制动" % int(hull), 3.2)
			game.audio.play_impact()
			if hull <= 0.0:
				game.begin_death("飞船撞上空间站解体", 4.2)
		return


func _station_blocked(at_position: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull_shape
	query.transform = Transform3D(global_transform.basis, at_position + global_transform.basis * Vector3(0.0, -0.2, 0.2))
	query.collision_mask = STATION_COLLISION_MASK
	query.exclude = [hull_body.get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _station_rest(at_position: Vector3) -> Dictionary:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull_shape
	query.transform = Transform3D(global_transform.basis, at_position + global_transform.basis * Vector3(0.0, -0.2, 0.2))
	query.collision_mask = STATION_COLLISION_MASK
	query.exclude = [hull_body.get_rid()]
	return get_world_3d().direct_space_state.get_rest_info(query)


func _autopilot_aim(target_position: Vector3) -> Vector3:
	var to_target := target_position - global_position
	var distance := to_target.length()
	if distance < 1.0:
		return target_position
	var direction := to_target / distance
	var closest_t := clampf(-global_position.dot(direction), 0.0, distance)
	var closest := global_position + direction * closest_t
	var clearance: float = game.sun_radius + 1000.0
	var sun_distance := global_position.length()
	if closest.length() >= clearance and sun_distance >= clearance:
		return target_position
	var lateral := closest - direction * closest.dot(direction)
	if lateral.length_squared() < 1.0:
		lateral = direction.cross(Vector3.UP)
	if lateral.length_squared() < 1.0:
		lateral = direction.cross(Vector3.RIGHT)
	lateral = lateral.normalized()
	var severity := clampf((clearance - closest.length()) / clearance, 0.0, 1.0)
	var steer := direction + lateral * (1.2 + severity * 2.4)
	if sun_distance < clearance:
		steer += global_position.normalized() * (1.0 + (clearance - sun_distance) / clearance * 2.0)
	return global_position + steer.normalized() * distance


## 所有可对接的站：归航站 + 两座远景站。
## 远景站离得远（6000+ 米），先按距离粗筛，避免每帧对每个站算 to_global。
func _dockable_stations() -> Array:
	var out: Array = []
	if game.station != null:
		out.append(game.station)
	var here: Vector3 = global_position
	for s in game.distant_stations:
		if s == null:
			continue
		# 粗筛：站心距离小于「体量 + 余量」才细算端口距离
		var reach: float = 1200.0
		if s.global_position.distance_to(here) < reach:
			out.append(s)
	return out


func dock_station(station_node) -> void:
	if docked or landed:
		return
	docked = true
	docked_station = station_node
	autopilot = false
	landed = false
	landed_planet = null
	velocity = Vector3.ZERO
	global_position = station_node.dock_ship_position()
	look_at(station_node.dock_look_target(), station_node.dock_up_direction())
	game.audio.play_ui(300.0)
	var label := "归航站"
	if station_node.has_method("is_distant_station"):
		label = station_node.display_name
		# 远景站没有内部，所以文案不写「按 E 进入」
		game.hud.show_toast("磁力对接完成 · %s · 按 Space 脱离" % label, 4.0)
		return
	game.hud.show_toast("磁力对接完成 · 按 E 进入%s" % label, 4.0)


func undock() -> void:
	if not docked:
		return
	var station_node = docked_station
	var outward: Vector3 = station_node.up_direction()
	docked = false
	docked_station = null
	autopilot = false
	dock_cooldown = 3.0
	global_position += outward * 7.0
	velocity = outward * 20.0
	game.audio.play_ui(340.0)
	game.hud.show_toast("已脱离对接 · 手动驾驶", 3.0)


func takeoff() -> void:
	if docked:
		undock()
		return
	if not landed or landed_planet == null:
		return
	# 新的一次飞行：上一轮留下的引力警告状态作废，别一升空就弹「你已经逃不掉」。
	bh_warn_level = 0
	bh_warn_cooldown = 2.0
	bh_pull_strength = 0.0
	bh_distance = INF
	var normal: Vector3 = (global_position - landed_planet.global_position).normalized()
	reparent(game, true)
	landed = false
	landed_planet = null
	global_position += normal * 2.8
	velocity = normal * 24.0
	autopilot = false
	game.audio.play_ui(260.0)
	game.hud.show_toast("已升空 · Space 上升 / Ctrl 或 C 下降", 3.0)


func try_land() -> void:
	if landed or docked:
		return
	var planet = game.nearest_planet(global_position)
	var normal: Vector3 = (global_position - planet.global_position).normalized()
	var altitude: float = global_position.distance_to(planet.global_position) - planet.terrain_height(normal)
	if altitude > 70.0:
		game.hud.show_toast("距离地表太远，无法着陆；请先接近到 70 米内。", 2.5)
	elif velocity.length() >= 45.0:
		game.hud.show_toast("相对速度过高 · 按住 X 制动", 2.0)
	else:
		velocity = Vector3.ZERO
		global_position = planet.global_position + planet.surface_position(normal, 3.4)
		land(planet)


func land(planet) -> void:
	if landed:
		return
	var normal: Vector3 = (global_position - planet.global_position).normalized()
	velocity = Vector3.ZERO
	landed = true
	autopilot = false
	landed_planet = planet
	reparent(planet, true)
	global_position = planet.global_position + planet.surface_position(normal, 2.3)
	var transform := global_transform
	var align := Quaternion(transform.basis.y.normalized(), normal)
	transform.basis = (Basis(align) * transform.basis).orthonormalized()
	global_transform = transform
	game.audio.play_ui(330.0)
	game.hud.show_toast("已着陆 · " + planet.display_name + " · E 离船", 3.0)


## 尾焰与引擎光效。
##
## 2026-11-10 用户反馈两条，这里一起解决：
##   1. 「没开的时候不要尾焰」—— 旧版无论有没有推力，尾焰都常亮着
##      （`0.35 + thrust_level * 3.5`，推力为 0 时基线是 0.35，一直有微光）。
##      现在改成：thrust_level 接近 0 就**整束隐藏**，只有真的在推进时才有火。
##   2. 「尾焰要动态特效」—— 旧版只是把锥体沿 Z 拉伸，形状是死的。
##      现在叠加三层动态：
##        · 每帧随机抖动（flicker），火焰不会是一个静止的锥
##        · 横向轻微摆动（sway），像被气流吹
##        · 长度跟随推力平滑变化
##      全部走 `_plume_phase` 累加，不依赖 delta 之外的随机源，
##      所以帧率变化时观感一致。
var _plume_phase := 0.0
var _plume_sway_seed := [0.0, 0.0, 0.0]


func _update_engine(delta: float) -> void:
	_plume_phase += delta

	# 推力趋近 0 就算「没开」：尾焰整体隐藏，不留基线微光。
	var firing: bool = thrust_level > 0.06

	for material in engine_materials:
		var mat_target := 0.0 if not firing else (1.2 + thrust_level * 4.2)
		material.emission_energy_multiplier = lerpf(
			material.emission_energy_multiplier, mat_target, delta * 10.0)
	for light in engine_lights:
		var light_target := 0.0 if not firing else (0.4 + thrust_level * 2.2)
		light.light_energy = lerpf(light.light_energy, light_target, delta * 10.0)

	# 尾焰本体
	for i in range(engine_plumes.size()):
		var node := engine_plumes[i] as Node3D
		if not firing:
			# 直接藏起来，不是缩到 0 —— 缩到 0 仍然会渲染退化三角形
			node.visible = false
			continue
		node.visible = true

		# 每束火有自己的相位偏移，三束不会同步闪烁（同步会像呼吸灯）
		var phase: float = _plume_phase * 18.0 + float(i) * 2.1

		# 长度：跟随推力，叠一层高频抖动做出「燃烧不稳」的感觉
		var base_len: float = 0.45 + thrust_level * 1.25
		var flicker: float = 1.0 + sin(phase) * 0.13 + sin(phase * 2.7) * 0.06
		var target_len: float = base_len * flicker

		# 横向摆动：低频，让火焰略微左右飘
		var sway: float = sin(_plume_phase * 6.0 + float(i) * 1.7) * 0.035

		node.scale = node.scale.lerp(
			Vector3(1.0 + sway, 1.0 + sway, target_len),
			1.0 - exp(-delta * 14.0))


## 把一个盒体塞进按材质分组的 SurfaceTool 批次，用于铆钉 / 格栅 / 防滑条这类重复小件。
func _batch_box(size: Vector3, material: Material, xform: Transform3D) -> void:
	var key := material.get_instance_id()
	if not _batch.has(key):
		var created := SurfaceTool.new()
		created.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batch[key] = {"tool": created, "material": material}
	var entry: Dictionary = _batch[key]
	var tool: SurfaceTool = entry["tool"]
	tool.append_from(_box(size), 0, xform)


## 把批次合并成少量 MeshInstance3D，减少 draw call（网页版单线程，draw call 很贵）。
func _batch_flush() -> void:
	for key in _batch:
		var entry: Dictionary = _batch[key]
		var tool: SurfaceTool = entry["tool"]
		tool.generate_normals()
		var instance := MeshInstance3D.new()
		instance.mesh = tool.commit()
		instance.material_override = entry["material"]
		add_child(instance)
	_batch.clear()


func _light_add(at: Vector3, color: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	add_child(light)


func _material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material


func _mesh(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	return instance


func _sphere(radius: float, segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cylinder(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	return mesh
