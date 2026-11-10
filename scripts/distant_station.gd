extends Node3D
## 远景空间站：给外部导入的模型挂上「碰撞 + 对接」。
##
## 为什么单独写一个脚本、而不是复用 station.gd：
##   station.gd 是归航站的**程序化几何生成器**（两千多行，造环/臂/六廊/内部房间），
##   它的坐标零点、包围盒、内部结构与这两座外部模型完全不同 —— 硬套会把
##   两套逻辑搅在一起。这两座站只需要很少的东西：
##     · 一层粗略碰撞（ConvexPolygonShape 太贵，用一串 BoxShape 近似）
##     · 四个对接接口（docking_point / dock_ship_position / dock_look_target / up_direction）
##     · 缓慢自转
##
## 对接点怎么定：
##   两座模型都是「圆盘 + 中央轴」的对称结构，正面朝向 ±Y。
##   本脚本在**模型包围盒的正上方**放对接端口，飞船从那儿贴上来。
##   这跟归航站（对接口在塔顶）的思路一致，也符合「低速靠近自动磁力对接」的玩法。
##
## 碰撞怎么近似：
##   用 3~4 个 BoxShape 拼一个「圆盘 + 中心柱」的骨架 —— 玩家飞船撞上去会弹开，
##   但不需要精确到每个舷窗。外部模型动辄十几万面，trimesh 碰撞会拖垮物理。

## 由 main.gd 在建站时注入：模型节点的包围盒（世界尺寸）
var half_extent := Vector3.ONE * 50.0
## 圆盘部分的半径（用于确定碰撞盘与对接半径）
var disk_radius := 50.0
## 圆盘厚度
var disk_thickness := 4.0

## 对接端口相对本节点原点的偏移（本节点局部坐标）
var dock_offset := Vector3(0.0, 0.0, 0.0)

## 接入半径：飞船进到这个距离就开始「磁力吸附」提示
const DOCK_APPROACH_RADIUS := 90.0
## 实际完成对接的距离与相对速度阈值
const DOCK_SNAP_RADIUS := 30.0
const DOCK_SNAP_SPEED := 22.0

var spin_rate := 0.01

## 给 HUD / 提示用：这座站叫什么
var display_name := "远景空间站"


func _ready() -> void:
	_build_collision()


## 用几个盒子近似「圆盘 + 中心柱」。盒子数量克制在 5 个以内，
## 物理开销可以忽略，同时保证飞船不会直接穿过去。
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "StationCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	# ① 中央柱：从包围盒底部到顶部
	var pillar_half := Vector3(
		maxf(disk_radius * 0.22, 4.0),
		half_extent.y,
		maxf(disk_radius * 0.22, 4.0))
	_add_box(body, Vector3(0.0, 0.0, 0.0), pillar_half)

	# ② 圆盘：压扁的盒子近似
	var disk_half := Vector3(disk_radius, maxf(disk_thickness * 0.5, 1.5), disk_radius)
	_add_box(body, Vector3(0.0, disk_center_y(), 0.0), disk_half)

	# ③ 外环：四个斜置盒子拼一圈，挡住环面（环是空的，但碰撞要能撞到）
	var ring_y := disk_center_y()
	var ring_half := Vector3(disk_radius * 0.28, maxf(disk_thickness * 0.5, 1.5), disk_radius * 0.28)
	for i in range(4):
		var angle := TAU * float(i) / 4.0
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * disk_radius * 0.72
		_add_box(body, Vector3(offset.x, ring_y, offset.z), ring_half)

	# ④ 对接塔顶：让飞船撞到对接环时也有碰撞
	_add_box(body, dock_offset, Vector3(disk_radius * 0.16, 3.0, disk_radius * 0.16))


## 圆盘在局部坐标里的高度：模型是居中导入的，盘面大致在 y=0 附近。
func disk_center_y() -> float:
	return 0.0


func _add_box(parent: StaticBody3D, center: Vector3, half: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = half * 2.0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = center
	parent.add_child(collider)


# ── 对接接口（与 station.gd 同名同义，ship.gd 直接调）────────────────

func docking_point() -> Vector3:
	return to_global(dock_offset)


func dock_ship_position() -> Vector3:
	# 停在端口上方一点点，别和碰撞盒穿插
	return to_global(dock_offset + Vector3(0.0, 6.0, 0.0))


func dock_look_target() -> Vector3:
	return to_global(Vector3.ZERO)


func dock_up_direction() -> Vector3:
	# 船顶朝站的 +Z（绕轴线方向），和归航站一致
	return global_transform.basis.z.normalized()


func up_direction() -> Vector3:
	return global_transform.basis.y.normalized()


func is_distant_station() -> bool:
	return true


## 内部舱室：一个环形观景舱，挂在站心下方（盘面以下），
## 从气闸走进去能看到外面的星空与行星。
## 懒加载 —— 玩家第一次按 E 进站时才造，省掉启动开销。
var interior: Node3D = null
const DistantStationInterior = preload("res://scripts/distant_station_interior.gd")


func ensure_interior() -> Node3D:
	if interior != null:
		return interior
	var hall: Node3D = DistantStationInterior.new()
	hall.name = "Interior"
	# 舱室挂在本节点下、但**不从属于自转**：否则玩家站在里面会被转晕。
	# 做法是把它挂到父节点（main）下，位置跟随站点，但朝向固定朝站心。
	add_child(hall)
	# 舱半径由 interior.build() 自己按站体半径换算（那边一处即够）：
	# 这里必须传**站体半径本身**，不能再预先缩放 —— 之前这里写了
	# maxf(disk_radius/12, 20)，build 里又乘 0.042，两处缩放叠加，
	# 358 米的站最后得到 12 米舱（撞到 clamp 下限），舱室小得不像话。
	var tint := Color("d9b879") if display_name.find("环塔") >= 0 else Color("cfe6ff")
	hall.build(disk_radius, tint)
	# 舱中心放在盘面下方，避免和站体几何打架
	hall.position = Vector3(0.0, -maxf(half_extent.y * 0.15, 8.0), 0.0)
	interior = hall
	return interior


func interior_spawn_transform() -> Transform3D:
	return ensure_interior().interior_spawn_transform()


func is_interior_position(position: Vector3) -> bool:
	if interior == null:
		return false
	return interior.is_interior_position(position)


func airlock_position() -> Vector3:
	return ensure_interior().airlock_position()


func is_at_airlock(position: Vector3) -> bool:
	if interior == null:
		return false
	return interior.is_at_airlock(position)


func update_spin(delta: float) -> void:
	rotate_y(spin_rate * delta)
