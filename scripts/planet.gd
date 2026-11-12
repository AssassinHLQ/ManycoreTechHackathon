extends Node3D

const ArchitectureScript = preload("res://scripts/architecture.gd")
const UndergroundScript = preload("res://scripts/underground.gd")
const PlanetShader = preload("res://shaders/planet.gdshader")
const CloudShader = preload("res://shaders/clouds.gdshader")

var game: Node3D
var planet_id := ""
var display_name := ""
var description := ""
var kind := "rock"
var radius := 300.0
var gravity_strength := 18.0
var orbit_radius := 2000.0
var orbit_phase := 0.0
var orbit_speed := 0.0
var orbit_height := 0.0
var base_color := Color.GRAY
var accent_color := Color.WHITE
var surface: MeshInstance3D
## 行星环（只有悬晶星/玄渊星有）。一整片 annulus，见 _build_ring。
var ring_node: MeshInstance3D
var atmosphere: MeshInstance3D
var clouds: MeshInstance3D
var rng := RandomNumberGenerator.new()
var terrain_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var site_direction := Vector3.UP
var site_height := 0.0
var site_pad_radius := 0.0
var cave_enabled := false
var cave_direction := Vector3.UP
var cave_mouth_radius := 0.0
var cave_hole_angle := 0.0
var water_shell: MeshInstance3D
var terrain_collision_done := false

## AI 生成道具（Lux3D）的模型路径。
##
## ⚠ 2026-11-11 用户要求：「星球需要更多物体、环境、地形、特殊点，
##   而且不能是程序化的，必须 AI 生成」。
##   所以树、岩石、遗迹、晶体、信号塔这些都是 Lux3D 文生 3D 出来的 GLB。
##
## 命名约定：`-lo` 是低模变体（约 2 千面）用来铺量，无后缀是高模用来当地标。
## 某个 id 缺资产时 `_prop_mesh()` 返回 null，调用方自动回退程序化几何。
## 每类 AI 道具的实例上限（防止面数爆炸）。
##
## ⚠ 2026-11-11 实测：青岚星 350 棵高模树 × 34468 面 = 1206 万面，
##   单星球合计 1403 万面 —— 完全渲染不动。
##   Lux3D 的模型是 2~3 万面的「高模」，只能当地标；
##   低模变体（*-lo，1 万面）才能拿来铺量，且每类仍要限额。
const PROP_INSTANCE_CAP := {
	"alien-tree": 18,
	"alien-tree-lo": 40,
	"rock-cluster": 18,
	"rock-cluster-lo": 40,
	"rock-spire": 18,
	"rock-spire-lo": 40,
	"ruin-arch": 6,
	"obelisk": 8,
	"dome-habitat": 4,
	"signal-tower": 4,
	"crystal-cluster": 10,
	"crystal-cluster-lo": 40,
	"vent-lo": 40,
	"stone-bridge": 4,
	"alien-mushroom-lo": 40,
	"dead-tree-lo": 40,
	"thorn-shrub-lo": 40,
	"crystal-flora-lo": 40,
	"ice-spike-lo": 40,
	"lava-boulder-lo": 40,
	"dune-arch-lo": 40,
	"cargo-pod-lo": 40,
	"lm-qinglan": 2,
	"lm-zheya": 2,
	"lm-cangbo": 2,
	"lm-xuanjing": 2,
	"lm-xuanyuan": 2,
	"lm-baiyao": 2,
	"lm-pansha": 2,
	"lm-taiyuan": 2,
	"lm-liuwu": 2,
	"lm-jianmo": 2,
	"lm-jiangxiao": 2,
	"lm-cangwu": 2,
	"lm-jinwu": 2,
	"lm-yuheng": 2,
	"lm-sue": 2,
	"lm-danxia": 2,
	"lm-biluo": 2,
	"lm-youdu": 2,
	"lm-yaoguang": 2,
	"lm-xuanpu": 2,
	"alien-mushroom": 12,
	"dead-tree": 12,
	"thorn-shrub": 12,
	"crystal-flora": 12,
	"ice-spike": 12,
	"dune-arch": 12,
	"cargo-pod": 12,
	"antenna-mast": 12,
	"stone-idol": 12,
	"rubble-wall": 12,
	"lava-boulder": 12,
	"geyser-basin": 12,
	"lf-canyon-wall": 4,
	"lf-natural-arch": 4,
	"lf-mesa-plateau": 4,
	"lf-ridge-spine": 4,
	"vent": 8,
	"floating-rock": 8,
}

## 每颗星球的 AI 道具组合：kind → [prop_id, 数量, 尺寸下限, 尺寸上限, 是否靠基地, 悬浮?]
##
## ⚠ 2026-11-11 目标 ③「按星球类型与 prop_scale 布置更多物体、环境与特殊地标」。
##   组合依据是每颗星球的设定文字（见 main.gd 的 description）：
##     青岚=雾松林+石砌村舍+旧观测塔 → 树密、遗迹拱门、方尖碑、穹顶
##     赭崖=盐碱裂谷+间歇喷泉+断裂观测环 → 喷口、尖峰、中继塔
##     悬晶=环站残骸+磁性矿石+低空碎片 → 晶簇、悬浮石、中继塔
##     缄默=黑曜石暗面+静默门阵 → 方尖碑阵、黑曜石尖峰
##     瑶光=耀眼晶脊+朝下的镜面 → 晶簇极密、尖峰、悬浮石
##   尺寸单位是「设计米数」，运行时会再乘 prop_scale。
const PLANET_PROPS := {
	"qinglan": [["ruin-arch", 3, 20, 31, true], ["obelisk", 4, 24, 42, false],
		["dome-habitat", 2, 20, 30, true], ["rock-cluster", 6, 12, 24, false]],
	"zheya": [["vent", 8, 14, 26, false], ["rock-spire", 10, 18, 42, false],
		["signal-tower", 3, 26, 46, true], ["ruin-arch", 2, 18, 28, false]],
	"cangbo": [["crystal-cluster", 10, 12, 26, false], ["dome-habitat", 3, 18, 28, true],
		["floating-rock", 5, 16, 30, false]],
	"xuanjing": [["crystal-cluster", 12, 13, 30, false], ["floating-rock", 8, 16, 32, false],
		["signal-tower", 3, 26, 46, true]],
	"xuanyuan": [["obelisk", 8, 26, 46, true], ["ruin-arch", 3, 22, 35, false],
		["rock-spire", 6, 20, 46, false]],
	"baiyao": [["rock-spire", 12, 19, 46, false], ["crystal-cluster", 8, 13, 28, false],
		["dome-habitat", 2, 18, 26, true]],
	"pansha": [["rock-spire", 14, 20, 46, false], ["ruin-arch", 3, 19, 31, false],
		["rock-cluster", 10, 13, 28, false]],
	"taiyuan": [["ruin-arch", 4, 19, 32, false], ["rock-cluster", 10, 12, 25, false],
		["dome-habitat", 2, 18, 26, true]],
	"liuwu": [["vent", 10, 16, 29, false], ["dome-habitat", 3, 19, 29, true],
		["signal-tower", 2, 26, 43, false], ["rock-cluster", 6, 12, 23, false]],
	"jianmo": [["obelisk", 12, 26, 46, false], ["rock-spire", 10, 19, 44, false],
		["floating-rock", 5, 14, 29, false]],
	"jiangxiao": [["rock-spire", 10, 18, 41, false], ["vent", 5, 13, 25, false],
		["ruin-arch", 2, 18, 29, false]],
	"cangwu": [["ruin-arch", 3, 19, 31, true], ["rock-cluster", 8, 12, 24, false],
		["obelisk", 3, 24, 40, false]],
	"jinwu": [["rock-cluster", 12, 13, 28, false], ["obelisk", 5, 25, 44, false],
		["vent", 4, 13, 24, false]],
	"yuheng": [["crystal-cluster", 10, 13, 28, false], ["obelisk", 4, 23, 38, false],
		["rock-cluster", 8, 12, 23, false]],
	"sue": [["obelisk", 10, 24, 46, false], ["rock-cluster", 10, 12, 24, false],
		["floating-rock", 4, 14, 28, false]],
	"danxia": [["rock-cluster", 12, 13, 29, false], ["rock-spire", 8, 18, 40, false],
		["ruin-arch", 2, 18, 29, false]],
	"biluo": [["crystal-cluster", 8, 12, 24, false], ["floating-rock", 6, 14, 28, false],
		["dome-habitat", 3, 18, 26, true]],
	"youdu": [["crystal-cluster", 12, 13, 29, false], ["rock-spire", 8, 18, 41, false],
		["alien-tree", 4, 12, 20, false]],
	"yaoguang": [["crystal-cluster", 14, 14, 32, false], ["rock-spire", 8, 18, 42, false],
		["floating-rock", 6, 14, 29, false]],
	"xuanpu": [["alien-tree", 8, 12, 20, false], ["crystal-cluster", 8, 12, 25, false],
		["rock-cluster", 8, 12, 23, false]],
}

## 大型地貌件（目标 ④「大型地貌特征」）。
##
## 复用已生成的 AI 资产、放大到 300~800 米世界高度，做成从轨道上就能看见的地标：
##   floating-rock  → 悬空巨岩（科幻感强）
##   rock-spire     → 千米石柱 / 侵蚀塔
##   rock-cluster   → 整座山丘群
##   crystal-cluster→ 巨型晶脉
## 尺寸是「设计米数」，运行时 × prop_scale。
## ⚠ 这一条**完全零额度**：只是把已有 GLB 放大，不新增生成。
const LANDFORM_PROPS := {
	"qinglan": [["rock-cluster", 1, 26, 34, false], ["lf-ridge-spine", 1, 26, 40, false]],
	"zheya": [["rock-spire", 2, 28, 42, false], ["lf-canyon-wall", 1, 28, 46, false],
		["stone-bridge", 1, 14, 26, false]],
	"cangbo": [["floating-rock", 2, 26, 38, false], ["lf-mesa-plateau", 1, 28, 44, false]],
	"xuanjing": [["floating-rock", 3, 26, 42, false], ["lf-ridge-spine", 1, 26, 40, false]],
	"xuanyuan": [["rock-spire", 2, 30, 46, false], ["stone-bridge", 1, 14, 26, false]],
	"baiyao": [["rock-spire", 2, 28, 44, false], ["lf-canyon-wall", 1, 28, 46, false]],
	"pansha": [["rock-spire", 3, 30, 48, false], ["lf-natural-arch", 1, 26, 40, false]],
	"taiyuan": [["rock-cluster", 2, 26, 36, false], ["lf-ridge-spine", 1, 26, 40, false]],
	"liuwu": [["rock-spire", 1, 28, 40, false], ["lf-canyon-wall", 1, 28, 46, false],
		["stone-bridge", 1, 14, 26, false]],
	"jianmo": [["rock-spire", 3, 30, 48, false], ["floating-rock", 1, 26, 38, false],
		["stone-bridge", 1, 14, 26, false]],
	"jiangxiao": [["rock-spire", 2, 28, 44, false], ["lf-mesa-plateau", 1, 28, 44, false]],
	"cangwu": [["rock-cluster", 2, 26, 36, false], ["lf-ridge-spine", 1, 26, 40, false]],
	"jinwu": [["rock-cluster", 2, 26, 34, false], ["lf-mesa-plateau", 1, 28, 44, false]],
	"yuheng": [["crystal-cluster", 2, 26, 40, false]],
	"sue": [["rock-spire", 2, 26, 40, false], ["lf-canyon-wall", 1, 28, 46, false]],
	"danxia": [["rock-cluster", 2, 26, 38, false], ["rock-spire", 1, 30, 44, false],
		["lf-natural-arch", 1, 26, 40, false], ["stone-bridge", 1, 14, 26, false]],
	"biluo": [["floating-rock", 2, 26, 40, false], ["lf-natural-arch", 1, 26, 40, false]],
	"youdu": [["crystal-cluster", 2, 26, 42, false], ["lf-canyon-wall", 1, 28, 46, false]],
	"yaoguang": [["crystal-cluster", 3, 26, 42, false], ["floating-rock", 1, 26, 38, false],
		["lf-ridge-spine", 1, 26, 40, false]],
	"xuanpu": [["rock-cluster", 1, 26, 36, false], ["crystal-cluster", 1, 26, 40, false]],
}

## 会「悬浮」的道具：放置时抬高，做成浮空岛/浮石。
const PROP_FLOATING := ["floating-rock"]

## 每颗星球的「通用环境物件」组合：[prop_id, 数量, 尺寸下限, 尺寸上限]
##
## 第二批资产（2026-11-12，用户：「怎么才 39，太少了」）里挑的 12 个通用件，
## 按星球气候分配：冰原给冰棱、沙海给沙岩拱、丛林给枯树蘑菇、
## 遗迹区给石像断墙。尺寸是设计米数，运行时 × prop_scale。
## 铺量混排：[prop_id, 数量, 尺寸下限, 尺寸上限]，尺寸是**设计米数**（× prop_scale）。
##
## ⚠ 2026-11-12：原来每颗星球只铺 1~2 种模型 × 90 个，同一个模型重复 90 次，
##   近看非常单调。这里改成 4~5 种混排，**总数仍控制在 ~180**（性能不变），
##   但视觉层次立刻丰富。道具都来自第三批低模（1 万面）。
const SCATTER_MIX := {
	"qinglan": [["alien-tree-lo", 45, 4, 8], ["alien-mushroom-lo", 30, 3, 6],
		["thorn-shrub-lo", 35, 2, 3], ["rock-cluster-lo", 35, 2, 5],
		["dead-tree-lo", 20, 4, 9]],
	"zheya": [["rock-cluster-lo", 40, 2, 6], ["lava-boulder-lo", 40, 2, 5],
		["thorn-shrub-lo", 30, 2, 3], ["dune-arch-lo", 18, 7, 14]],
	"cangbo": [["ice-spike-lo", 55, 3, 9], ["crystal-flora-lo", 45, 1, 3],
		["rock-cluster-lo", 40, 2, 5]],
	"xuanjing": [["crystal-cluster-lo", 40, 3, 7], ["crystal-flora-lo", 45, 1, 3],
		["rock-spire-lo", 35, 3, 8], ["cargo-pod-lo", 15, 3, 6]],
	"xuanyuan": [["rock-spire-lo", 45, 3, 9], ["lava-boulder-lo", 40, 2, 5],
		["dead-tree-lo", 20, 4, 9]],
	"baiyao": [["ice-spike-lo", 60, 3, 10], ["crystal-flora-lo", 40, 1, 3],
		["rock-spire-lo", 35, 3, 8]],
	"pansha": [["rock-spire-lo", 45, 3, 9], ["dune-arch-lo", 25, 8, 16],
		["rock-cluster-lo", 45, 2, 6], ["dead-tree-lo", 18, 4, 9]],
	"taiyuan": [["alien-tree-lo", 40, 4, 8], ["thorn-shrub-lo", 45, 2, 3],
		["rock-cluster-lo", 40, 2, 5], ["alien-mushroom-lo", 20, 3, 6]],
	"liuwu": [["vent-lo", 40, 3, 7], ["lava-boulder-lo", 45, 2, 5],
		["rock-cluster-lo", 40, 2, 5], ["cargo-pod-lo", 15, 3, 6]],
	"jianmo": [["rock-spire-lo", 50, 3, 9], ["crystal-cluster-lo", 40, 3, 7],
		["crystal-flora-lo", 35, 1, 3], ["dead-tree-lo", 15, 4, 9]],
	"jiangxiao": [["rock-cluster-lo", 45, 2, 6], ["rock-spire-lo", 40, 3, 9],
		["lava-boulder-lo", 40, 2, 5]],
	"cangwu": [["alien-tree-lo", 55, 4, 9], ["alien-mushroom-lo", 30, 3, 6],
		["thorn-shrub-lo", 40, 2, 3], ["rock-cluster-lo", 30, 2, 5]],
	"jinwu": [["rock-cluster-lo", 50, 2, 6], ["lava-boulder-lo", 45, 2, 5],
		["dead-tree-lo", 20, 4, 9], ["dune-arch-lo", 15, 8, 15]],
	"yuheng": [["rock-cluster-lo", 50, 2, 6], ["crystal-flora-lo", 40, 1, 3],
		["alien-tree-lo", 30, 4, 8], ["crystal-cluster-lo", 30, 3, 7]],
	"sue": [["rock-cluster-lo", 55, 2, 6], ["rock-spire-lo", 40, 3, 8],
		["crystal-flora-lo", 30, 1, 3]],
	"danxia": [["rock-cluster-lo", 55, 2, 6], ["rock-spire-lo", 40, 3, 9],
		["dune-arch-lo", 20, 8, 16], ["lava-boulder-lo", 35, 2, 5]],
	"biluo": [["crystal-flora-lo", 50, 1, 3], ["rock-cluster-lo", 45, 2, 5],
		["crystal-cluster-lo", 30, 3, 7], ["cargo-pod-lo", 12, 3, 6]],
	"youdu": [["ice-spike-lo", 50, 3, 9], ["crystal-cluster-lo", 40, 3, 7],
		["rock-spire-lo", 35, 3, 8], ["alien-tree-lo", 20, 4, 8]],
	"yaoguang": [["crystal-cluster-lo", 50, 3, 7], ["crystal-flora-lo", 45, 1, 3],
		["rock-spire-lo", 35, 3, 9], ["ice-spike-lo", 25, 3, 8]],
	"xuanpu": [["alien-tree-lo", 45, 4, 8], ["alien-mushroom-lo", 35, 3, 6],
		["thorn-shrub-lo", 40, 2, 3], ["crystal-cluster-lo", 30, 3, 7]],
}

const GENERIC_PROPS := {
	"qinglan": [["alien-mushroom", 5, 3, 8], ["dead-tree", 4, 4, 10], ["stone-idol", 2, 4, 9]],
	"zheya": [["rubble-wall", 5, 4, 10], ["lava-boulder", 6, 2, 6], ["geyser-basin", 4, 3, 8]],
	"cangbo": [["ice-spike", 8, 3, 9], ["crystal-flora", 4, 1, 3]],
	"xuanjing": [["cargo-pod", 4, 3, 7], ["antenna-mast", 3, 5, 12], ["crystal-flora", 5, 1, 3]],
	"xuanyuan": [["stone-idol", 3, 4, 9], ["rubble-wall", 4, 4, 10]],
	"baiyao": [["ice-spike", 10, 3, 9], ["crystal-flora", 3, 1, 3]],
	"pansha": [["dune-arch", 4, 8, 18], ["dead-tree", 3, 4, 10], ["lava-boulder", 5, 2, 6]],
	"taiyuan": [["thorn-shrub", 8, 2, 3], ["dead-tree", 3, 4, 10], ["alien-mushroom", 3, 3, 8]],
	"liuwu": [["geyser-basin", 5, 3, 8], ["cargo-pod", 3, 3, 7], ["antenna-mast", 2, 5, 12]],
	"jianmo": [["stone-idol", 3, 4, 9], ["rubble-wall", 3, 4, 10]],
	"jiangxiao": [["lava-boulder", 7, 2, 6], ["dune-arch", 3, 8, 18]],
	"cangwu": [["alien-mushroom", 6, 3, 8], ["dead-tree", 4, 4, 10], ["thorn-shrub", 5, 2, 3]],
	"jinwu": [["lava-boulder", 6, 2, 6], ["dead-tree", 3, 4, 10]],
	"sue": [["stone-idol", 3, 4, 9], ["rubble-wall", 4, 4, 10]],
	"danxia": [["dune-arch", 4, 8, 18], ["rubble-wall", 3, 4, 10]],
	"biluo": [["crystal-flora", 4, 1, 3], ["cargo-pod", 2, 3, 7]],
	"youdu": [["ice-spike", 8, 3, 9], ["crystal-flora", 5, 1, 3], ["stone-idol", 3, 4, 9]],
	"yaoguang": [["crystal-flora", 8, 1, 3], ["ice-spike", 5, 3, 9]],
	"xuanpu": [["alien-mushroom", 6, 3, 8], ["thorn-shrub", 5, 2, 3], ["dead-tree", 3, 4, 10]],
}

const PROP_MODELS := {
	"alien-tree": "res://assets/models/props/alien-tree/model.glb",
	"alien-tree-lo": "res://assets/models/props/alien-tree-lo/model.glb",
	"rock-cluster": "res://assets/models/props/rock-cluster/model.glb",
	"rock-cluster-lo": "res://assets/models/props/rock-cluster-lo/model.glb",
	"rock-spire": "res://assets/models/props/rock-spire/model.glb",
	"rock-spire-lo": "res://assets/models/props/rock-spire-lo/model.glb",
	"ruin-arch": "res://assets/models/props/ruin-arch/model.glb",
	"obelisk": "res://assets/models/props/obelisk/model.glb",
	"dome-habitat": "res://assets/models/props/dome-habitat/model.glb",
	"signal-tower": "res://assets/models/props/signal-tower/model.glb",
	"crystal-cluster": "res://assets/models/props/crystal-cluster/model.glb",
	"crystal-cluster-lo": "res://assets/models/props/crystal-cluster-lo/model.glb",
	"vent-lo": "res://assets/models/props/vent-lo/model.glb",
	"stone-bridge": "res://assets/models/props/stone-bridge/model.glb",
	"alien-mushroom-lo": "res://assets/models/props/alien-mushroom-lo/model.glb",
	"dead-tree-lo": "res://assets/models/props/dead-tree-lo/model.glb",
	"thorn-shrub-lo": "res://assets/models/props/thorn-shrub-lo/model.glb",
	"crystal-flora-lo": "res://assets/models/props/crystal-flora-lo/model.glb",
	"ice-spike-lo": "res://assets/models/props/ice-spike-lo/model.glb",
	"lava-boulder-lo": "res://assets/models/props/lava-boulder-lo/model.glb",
	"dune-arch-lo": "res://assets/models/props/dune-arch-lo/model.glb",
	"cargo-pod-lo": "res://assets/models/props/cargo-pod-lo/model.glb",
	"lm-qinglan": "res://assets/models/props/lm-qinglan/model.glb",
	"lm-zheya": "res://assets/models/props/lm-zheya/model.glb",
	"lm-cangbo": "res://assets/models/props/lm-cangbo/model.glb",
	"lm-xuanjing": "res://assets/models/props/lm-xuanjing/model.glb",
	"lm-xuanyuan": "res://assets/models/props/lm-xuanyuan/model.glb",
	"lm-baiyao": "res://assets/models/props/lm-baiyao/model.glb",
	"lm-pansha": "res://assets/models/props/lm-pansha/model.glb",
	"lm-taiyuan": "res://assets/models/props/lm-taiyuan/model.glb",
	"lm-liuwu": "res://assets/models/props/lm-liuwu/model.glb",
	"lm-jianmo": "res://assets/models/props/lm-jianmo/model.glb",
	"lm-jiangxiao": "res://assets/models/props/lm-jiangxiao/model.glb",
	"lm-cangwu": "res://assets/models/props/lm-cangwu/model.glb",
	"lm-jinwu": "res://assets/models/props/lm-jinwu/model.glb",
	"lm-yuheng": "res://assets/models/props/lm-yuheng/model.glb",
	"lm-sue": "res://assets/models/props/lm-sue/model.glb",
	"lm-danxia": "res://assets/models/props/lm-danxia/model.glb",
	"lm-biluo": "res://assets/models/props/lm-biluo/model.glb",
	"lm-youdu": "res://assets/models/props/lm-youdu/model.glb",
	"lm-yaoguang": "res://assets/models/props/lm-yaoguang/model.glb",
	"lm-xuanpu": "res://assets/models/props/lm-xuanpu/model.glb",
	"alien-mushroom": "res://assets/models/props/alien-mushroom/model.glb",
	"dead-tree": "res://assets/models/props/dead-tree/model.glb",
	"thorn-shrub": "res://assets/models/props/thorn-shrub/model.glb",
	"crystal-flora": "res://assets/models/props/crystal-flora/model.glb",
	"ice-spike": "res://assets/models/props/ice-spike/model.glb",
	"dune-arch": "res://assets/models/props/dune-arch/model.glb",
	"cargo-pod": "res://assets/models/props/cargo-pod/model.glb",
	"antenna-mast": "res://assets/models/props/antenna-mast/model.glb",
	"stone-idol": "res://assets/models/props/stone-idol/model.glb",
	"rubble-wall": "res://assets/models/props/rubble-wall/model.glb",
	"lava-boulder": "res://assets/models/props/lava-boulder/model.glb",
	"geyser-basin": "res://assets/models/props/geyser-basin/model.glb",
	"lf-canyon-wall": "res://assets/models/props/lf-canyon-wall/model.glb",
	"lf-natural-arch": "res://assets/models/props/lf-natural-arch/model.glb",
	"lf-mesa-plateau": "res://assets/models/props/lf-mesa-plateau/model.glb",
	"lf-ridge-spine": "res://assets/models/props/lf-ridge-spine/model.glb",
	"vent": "res://assets/models/props/vent/model.glb",
	"floating-rock": "res://assets/models/props/floating-rock/model.glb",
}

## 已加载的 AI 网格缓存（prop_id -> Mesh），同一进程里 20 颗星球共用一份。
static var _prop_mesh_cache := {}

## 待落地的高模地标：prop_id -> Array[Dictionary]（见 _add_prop）
var prop_queue: Dictionary = {}
## 待落地的低模散布：同上
var scatter_prop_queue: Dictionary = {}
## 已经 flush 过的 prop_id。_flush_props 可能被调用两次
## （铺量在 _build_landscape 里 flush、地标在 _build_landmark_props 里再 flush），
## 没有这个集合会把铺量那批重复实例化一遍。
var _flushed_prop_ids: Dictionary = {}


func _ready() -> void:
	rng.seed = abs(planet_id.hash()) + 9217
	terrain_noise.seed = abs(planet_id.hash()) + 41
	terrain_noise.frequency = 1.0
	terrain_noise.fractal_octaves = 4
	detail_noise.seed = abs(planet_id.hash()) + 817
	detail_noise.frequency = 1.0
	if kind == "qinglan":
		site_direction = Vector3(-0.06, 1.0, -0.04).normalized()
	site_pad_radius = 34.0
	match kind:
		"qinglan":
			site_pad_radius = 46.0
		"zheya":
			site_pad_radius = 46.0
		"xuanjing":
			site_pad_radius = 42.0
		"xuanyuan":
			site_pad_radius = 30.0
		"baiyao":
			site_pad_radius = 40.0
		"pansha":
			site_pad_radius = 44.0
		"taiyuan":
			site_pad_radius = 42.0
		"liuwu":
			site_pad_radius = 44.0
		"jianmo":
			site_pad_radius = 34.0
	# ⚠ 2026-11-11 平地半径跟着**行星半径**一起放大。
	#
	#   上面那些 34~46 米是按「半径 400 米的青岚星」标定的人类尺度场地。
	#   用户先后把星球放大（半径 ×3 → ×5），但这条一直是**绝对固定值**，
	#   于是星球越大地形起伏越大，而平地还是原来那么一小块 ——
	#   洞穴螺旋坡道（外缘离站点约 39 米）就压到了平地之外的起伏地形上，
	#   walk_test 的 sample 144 因此反复翻红。
	#
	#   这里按「实际半径 / 设计半径 400 米」等比放大，
	#   保证平地的**相对比例**与当初标定时一致。
	if radius > 0.0 and terrain_reference_radius > 0.0:
		prop_scale = radius / terrain_reference_radius
		site_pad_radius *= prop_scale
	site_height = _raw_terrain_height(site_direction)
	_setup_cave()
	_update_orbit()
	_build_surface()
	# ⚠ Lux3D 星球的高度表是在 `_build_surface()` 里烘焙的，上面那次 `site_height`
	# 走的是程序化噪声（表还没就绪）。烘焙完必须**重算一次** ——
	# 建筑平地的基准高度、`terrain_height` 的平地混合都以它为准，
	# 差了几十米的话观测塔会整栋悬空或埋进地里。
	if _lux_height_ready:
		site_height = _raw_terrain_height(site_direction)
	_build_atmosphere()
	_build_landscape()
	ArchitectureScript.build(self, kind)
	UndergroundScript.build(self, kind)
	# 目标 ③：按星球类型布置 AI 地标（少而大，和铺量的树/岩石分工不同）
	_build_landmark_props()
	if kind in ["xuanjing", "xuanyuan"]:
		_build_ring()
	# ⚠ 2026-11-11 Lux3D 星球**不再叠这层半透明水面球**。
	#
	#   用户：「星球上面那些水怎么处理」——沧波星上能看到一层玻璃球罩套在
	#   星球外面，边缘有硬边，还有一块块方块状的穿插痕迹。
	#   原因是 `_build_water()` 用一个**规则球面**（半径 site_height + 潮位）
	#   去表现海水，而 Lux3D 的地表是起伏不规则的 —— 球面和地形到处相交，
	#   交界处就是那些方块。
	#
	#   Lux3D 星球的海洋本来就画在贴图里（沧波是冰架与潮汐裂缝），
	#   叠一层几何水面只会打架，所以这类星球直接跳过。
	if kind == "cangbo" and lux_model_path == "":
		_build_water()


func _setup_cave() -> void:
	cave_enabled = kind in ["qinglan", "zheya", "xuanjing"]
	if not cave_enabled:
		return
	var tangent := site_direction.cross(Vector3.FORWARD)
	if kind == "xuanjing":
		tangent = Vector3.RIGHT.cross(site_direction)
	if tangent.length_squared() < 0.01:
		tangent = site_direction.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var distance := 31.0
	match kind:
		"zheya":
			distance = 33.0
			cave_mouth_radius = 9.0
		"xuanjing":
			distance = 29.0
			cave_mouth_radius = 8.5
		_:
			cave_mouth_radius = 10.0
	# ⚠ 2026-11-11 洞穴也按 prop_scale 放大。
	#
	#   原因：洞体（underground.gd）用的是绝对米数 —— 竖井半径 10.6 米、
	#   洞室 +9.5 米、井深 13 米。星球半径 ×5 之后，这个洞相对星球变成了
	#   一个针眼，而碰撞球面的格子（384 等分 = 33 米弧长）比洞口（10 米）还大，
	#   _cut_cave_hole 连一个三角形都裁不掉 → 洞口被地形封死，
	#   冒烟测试『the open mouth drops all the way to the cave floor』翻红。
	#   放大 5 倍后 cave_hole_angle = 50/2000 = 0.025 rad > 一格 0.0164 rad，
	#   洞口能在碰撞网格上真正开出来；同时和放大后的建筑保持同一尺度。
	# ⚠ 2026-11-11（B 方案，用户定）：洞穴跟着 prop_scale ×5 一起放大。
	#
	#   为什么不放大不行：星球半径 ×5、建筑 65 米高、平地 230 米，
	#   而洞还是 10 米宽、井深 13 米 —— 比例完全不对，而且
	#   cave_hole_angle = 10/2000 = 0.005 rad 比碰撞网格一格（0.0164 rad）还小，
	#   _cut_cave_hole 一个三角形都裁不掉，洞口直接被地形封死。
	#
	#   放大后：竖井半径 53 米、井深 65 米、洞室 +47 米，
	#   cave_hole_angle = 50/2000 = 0.025 rad > 一格 0.0164 rad，
	#   配合 _build_heightfield_surface_mesh 里的洞口局部细分，洞能开得干净。
	#   underground.gd 也必须用 _prop_parent（同一个缩放），两者才对得上。
	# ⚠ cave_mouth_radius **不要**在这里乘 prop_scale。
	#   它是 underground.gd 的**局部单位**（shaft_radius = 本值 + 0.6），
	#   而 underground 整棵子树已经由 _prop_parent 乘了一次 prop_scale。
	#   这里再乘一次 = 缩放两次 → 世界竖井半径 253 米，而洞口只有 57 米，
	#   会变成「小洞口下面一个巨大洞厅」的穿帮。
	#   世界尺度的洞口角只在这里算一次：
	#     洞口世界半径 = cave_mouth_radius * prop_scale（+ 下面 _build_lux3d_surface 的余量）
	distance *= prop_scale
	cave_direction = (site_direction + tangent * (distance / radius)).normalized()
	cave_hole_angle = (cave_mouth_radius * prop_scale) / radius


func _near_cave(direction: Vector3, margin: float) -> bool:
	if not cave_enabled:
		return false
	return direction.angle_to(cave_direction) < cave_hole_angle + margin


## 地形起伏幅度的**参考半径**（米）。0 = 用 `radius` 自己。
##
## ⚠ 2026-11-11 世界放大后新增。`_raw_terrain_height` 原来是
##   `radius + continental*radius*amplitude + detail*radius*0.004`，
##   起伏**绝对值正比于行星半径**。星球半径 ×3 之后，地面起伏也变成 3 倍：
##   青岚星峰峰值 9.4 米 → 28 米，相邻一步落差 0.52 → 1.56 米。
##
##   后果不是「视觉上更崎岖」，而是**贴地行走被判定为瞬移**：
##   walk_test 里「每帧位移 < 1.5 米」有三条直接翻红（出门、进门、潮汐站台阶）。
##   观测塔和潮汐站是**人类尺度**的建筑（台阶十几厘米），地面起伏放大 3 倍后
##   建筑与地面的接缝处就出现了米级的落差。
##
##   所以起伏幅度按「设计半径」算、不按放大后的 radius 算 ——
##   行星变大，但地表的绝对起伏保持原样，建筑、台阶、行走手感都不受影响。
var terrain_reference_radius := 0.0
## 地面物件的统一缩放系数 = 实际半径 / 设计半径（现在 = 5）。
##
## ⚠ 2026-11-11 用户：「为什么每个星球就一个星球在，没有东西」。
##   星球半径 ×5 之后，只有 `site_pad_radius` 跟着放大了（46 → 230 米），
##   而建筑、熔岩柱、晶体、树、岩石的尺寸**全是绝对米数**没动：
##     观测塔 13 米高，搁在半径 2000 米的星球上 = 地球上一根 40 米长的针；
##     全星球 170 棵树，平均 15 万平方米一棵。
##   结果从驾驶舱看下去，每颗星球都是一颗光球，上面什么都没有。
##   这里统一乘上 5：建筑变 20~65 米、树变 18~40 米，从空中一眼就能看见。
var prop_scale := 1.0


func terrain_height(direction: Vector3) -> float:
	var dir := direction.normalized()
	var raw := _raw_terrain_height(dir)
	if radius <= 0.0:
		return raw
	var angular := acos(clampf(dir.dot(site_direction), -1.0, 1.0))
	var pad_angle := site_pad_radius / radius
	var blend := 1.0 - smoothstep(pad_angle, pad_angle * 1.6, angular)
	return lerpf(raw, site_height, blend)


func _raw_terrain_height(direction: Vector3) -> float:
	var dir := direction.normalized()
	# Lux3D 星球：高度直接查烘焙好的表（见 _build_lux3d_surface）
	if _lux_height_ready:
		return _sample_lux_height(dir)
	var continental := terrain_noise.get_noise_3d(dir.x * 5.2, dir.y * 5.2, dir.z * 5.2)
	var detail := detail_noise.get_noise_3d(dir.x * 37.0, dir.y * 37.0, dir.z * 37.0)
	# 起伏按参考半径算（世界放大后 = 设计半径），球面本身仍按 radius。
	var ref: float = terrain_reference_radius if terrain_reference_radius > 0.0 else radius
	var amplitude := 0.026
	match kind:
		"zheya": amplitude = 0.030
		"cangbo": amplitude = 0.005
		"xuanjing": amplitude = 0.055
		"xuanyuan": amplitude = 0.024
		"baiyao": amplitude = 0.018
		"pansha": amplitude = 0.034
		"taiyuan": amplitude = 0.022
		"liuwu": amplitude = 0.028
		"jianmo": amplitude = 0.020
	return radius + continental * ref * amplitude + detail * ref * 0.004


func surface_position(direction: Vector3, altitude := 0.0) -> Vector3:
	var dir := direction.normalized()
	return dir * (terrain_height(dir) + altitude)


## ── Lux3D 生成的星球模型（Aholo Lux3D text-to-3D）──────────────────
##
## 用户 2026-11-11：「青岚星接入 + 其余 9 颗也走 Lux3D」。
##
## 设了 `lux_model_path` 就用它当**可见表面**，否则用程序化球面。
##
## ⚠ 关键约束：游戏里所有地面交互都走 `_raw_terrain_height(direction) -> float`
##   （着陆、玩家贴地、撞击、建筑平地、洞穴裁剪），也就是说星球必须能
##   「按方向取一个高度」。而 Lux3D 给的是一坨静态网格，没有这个函数。
##
##   实测青岚星那颗 GLB：36 万面、最近/最远顶点半径比 4.56（**有内部壳层**）、
##   19.9% 的方向格里有表面折叠（风车塔、洞穴口）。所以不能简单套「星形体」假设。
##
##   做法：从模型**顶点**按方向分格烘一张高度表，每格取 `max r`（最外层表面），
##   空洞用邻格扩散补齐，查询时双线性插值。内部壳层（r=0.137 那层）自然被
##   max 丢掉 —— 玩家要落的是外壳。
var lux_model_path := ""
## 方向 → 高度 的表（单位：米，已是行星世界半径）。空 = 未就绪。
var _lux_height_map := PackedFloat32Array()
var _lux_height_ready := false
## 纬度分格数；经度是它的两倍（经线在极点收敛，这样格子近似方正）。
const LUX_LAT_BINS := 192
const LUX_LON_BINS := 384
## Lux3D 模型的挂载根（缩放后挂在行星下）。
var _lux_root: Node3D
## 站点平地高度（Lux3D 分支压平网格后记下来，供 _ready 重算 site_height 对照）。
var _lux_pad_height := 0.0


func _build_surface() -> void:
	if lux_model_path != "":
		if _build_lux3d_surface():
			return
		push_warning("Lux3D 星球加载失败，退回程序化地形：%s" % lux_model_path)
	surface = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	# ⚠ 这里保持 256/128（原来就是），**不要跟着碰撞那套提到 384×192**。
	#   程序化星球的碰撞体直接复用这块可视网格（见 _ensure_terrain_collision
	#   的非 Lux3D 分支），可视面 = 碰撞面，本来就没有「不一致」。
	#   盲提高分辨率只会让可视网格从 6.5 万面涨到 14.7 万面，白烧 GPU。
	#   （2026-11-11 修「卡死」时误改过这里一次，已回退。）
	sphere.radial_segments = 256 if cave_enabled else 128
	sphere.rings = 128 if cave_enabled else 64
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(vertices.size()):
		var direction := vertices[i].normalized()
		vertices[i] = direction * terrain_height(direction)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if cave_enabled:
		arrays[Mesh.ARRAY_INDEX] = _cut_cave_hole(arrays, vertices)
	var displaced := ArrayMesh.new()
	displaced.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface_tool := SurfaceTool.new()
	surface_tool.create_from(displaced, 0)
	surface_tool.generate_normals()
	surface.mesh = surface_tool.commit()
	var material := ShaderMaterial.new()
	material.shader = PlanetShader
	material.set_shader_parameter("base_color", base_color)
	material.set_shader_parameter("accent_color", accent_color)
	material.set_shader_parameter("seed", float(abs(planet_id.hash()) % 997))
	var biome := 0
	match kind:
		"zheya": biome = 5
		"cangbo": biome = 6
		"xuanjing": biome = 7
		"xuanyuan": biome = 8
		"baiyao": biome = 9
		"pansha": biome = 10
		"taiyuan": biome = 11
		"liuwu": biome = 12
		"jianmo": biome = 13
	material.set_shader_parameter("biome", biome)
	surface.material_override = material
	add_child(surface)
	# 碰撞不在这里建：见 _ensure_terrain_collision()（靠近时才建，省下启动最贵的一项）。


func _ensure_terrain_collision() -> void:
	# 地形碰撞的 trimesh 是启动阶段最贵的一项（三个大星球各约 155 ms，五颗共约 530 ms，
	# 占整场构建的两成）。改成飞船或玩家靠近本星球时再建，落地前早就建好了。
	if terrain_collision_done:
		return
	# ── Lux3D 分支 ──
	#
	# ⚠ 碰撞体**不能用** Lux3D 网格，要用按高度表生成的程序化球面，原因：
	#   Lux3D 网格 15 万面摊在整个球上，顶点间距约 11 米；
	#   而站点平地半径 46 米只容得下约 4 个顶点 —— 那么粗的网格表达不了
	#   「一块平地」，玩家走上去会踩在参差的三角面上，洞穴坡道那 12.85 米
	#   的下沉会被顶穿（实测 walk_test 的 spiral ramp 因此翻红）。
	#
	#   程序化球面是 256×128，间距约 30 米但**均匀且与 terrain_height 同源**，
	#   所以物理表面与地形查询、以及 Lux3D 的可视表面三者一致。
	if _lux_root != null:
		terrain_collision_done = true
		var col_mesh := _build_heightfield_surface_mesh()
		if col_mesh == null:
			push_warning("Lux3D 行星建不出碰撞网格：%s" % planet_id)
			return
		var body := StaticBody3D.new()
		body.name = "TerrainCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		collision.shape = col_mesh.create_trimesh_shape()
		body.add_child(collision)
		add_child(body)
		return
	if surface == null or surface.mesh == null:
		return
	terrain_collision_done = true
	var body2 := StaticBody3D.new()
	body2.name = "TerrainCollision"
	body2.collision_layer = 1
	body2.collision_mask = 0
	var collision2 := CollisionShape3D.new()
	collision2.shape = surface.mesh.create_trimesh_shape()
	body2.add_child(collision2)
	add_child(body2)


## 按 `terrain_height()` 生成一张**专用的地形网格**（只用于碰撞，不显示）。
##
## 与 `_build_surface` 的程序化分支同一套做法，但独立成函数，好让 Lux3D 星球
## 也能拿到一张「与高度查询完全同源」的物理表面。
func _build_heightfield_surface_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	# ⚠ 2026-11-11 分辨率从 128×64（cave 256×128）提到 384×192。
	#
	#   这是「地形把人物卡死」的根因：Lux3D 的高度表本身是 96×192 格
	#   （半径 2000 米时每格约 65 米），而旧碰撞球面在赤道只有 128 格
	#   = **每格 98 米**，比高度表本身还粗 —— 采样不足导致碰撞面在地下
	#   切出一条条几十米宽的大折面，玩家走在折面棱上就被卡住。
	#   现在的 384×192（每格约 32 米）是高度表的 2 倍过采样，能完整表达它。
	sphere.radial_segments = 384
	sphere.rings = 192
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(vertices.size()):
		var d := vertices[i].normalized()
		vertices[i] = d * terrain_height(d)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if cave_enabled:
		# ⚠ 2026-11-11 洞口必须**局部细分**，否则开不出洞。
		#
		#   矛盾点：碰撞球面整球 384×192，一格约 33 米弧长；
		#   而洞口只有 cave_mouth_radius（青岚星 10 米）—— **洞口比一格还小**。
		#   `_cut_cave_hole` 按三角形重心角度判据裁，重心永远落不进洞口，
		#   于是一个三角形都裁不掉，洞口被地形封死（冒烟测试
		#   『the open mouth drops all the way to the cave floor』翻红）。
		#
		#   之前能用是因为星球半径只有 400 米、一格 19 米，也差不多是侥幸。
		#   现在把洞口周围递归切 3 轮（33 → 16.5 → 8.2 → 4.1 米），
		#   洞口边缘才有足够密的顶点，裁出来的洞才对得上 underground 的竖井。
		var refined := _refine_around_cave(vertices, arrays[Mesh.ARRAY_INDEX])
		vertices = refined[0]
		# ⚠⚠ 2026-11-12 修「掉进星球里面」：
		#   细分后顶点数变多了（74,690 → 108,236），但
		#   NORMAL / TANGENT / TEX_UV 还是 SphereMesh 原始的 74,690 个
		#   —— 数组长度不一致，add_surface_from_arrays() 会**直接失败**，
		#   成品面数变成 0，碰撞体为空，玩家一踩就穿到星球内部。
		#   实测：普通星球 148,224 面；带窟穴的青岚/赭崖/悬晶 **0 面**。
		#   法线反正由后面的 generate_normals() 重算，UV/TANGENT 对碰撞没意义，
		#   所以只保留 VERTEX + INDEX 两个槽位。
		var plain: Array = []
		plain.resize(Mesh.ARRAY_MAX)
		plain[Mesh.ARRAY_VERTEX] = vertices
		# ⚠⚠ 2026-11-12 修「掉进星球里面」：
		#   `_refine_around_cave` 返回 [细分后顶点, **细分后索引**]，
		#   旧代码只取了 refined[0]，把 refined[1] 丢掉，
		#   于是 _cut_cave_hole 拿到的还是**细分前**的索引数组。
		#   顶点表与索引表不是同一套拓扑 → 裁洞时大量三角形被判废
		#   → 碰撞面从 148,224 掉到 10,413，玩家一踩就穿到星球内部。
		#   实测：只有带空穴的青岚星（最差 -14.8 m）与
		#   赭崖星（-28.4 m）两颗 30/30 落点全下沉，其余 18 颗正常。
		plain[Mesh.ARRAY_INDEX] = refined[1]
		plain[Mesh.ARRAY_INDEX] = _cut_cave_hole(plain, vertices)
		arrays = plain
	var raw := ArrayMesh.new()
	raw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(raw, 0)
	st.generate_normals()
	var committed := st.commit()
	return committed


## 加载 Lux3D 模型当可见表面，并烘出「方向 → 高度」表。
##
## 返回 true 表示接成功了；失败返回 false，调用方会退回程序化地形。
func _build_lux3d_surface() -> bool:
	var packed: PackedScene = load(lux_model_path)
	if packed == null:
		push_warning("Lux3D 模型加载失败：%s" % lux_model_path)
		return false
	var inst := packed.instantiate() as Node3D
	if inst == null:
		push_warning("Lux3D 模型实例化失败：%s" % lux_model_path)
		return false

	_lux_root = Node3D.new()
	_lux_root.name = "Lux3dSurface"
	_lux_root.add_child(inst)
	add_child(_lux_root)

	# ── 收集顶点 + 法线到 _lux_root 的局部空间 ──
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var inv: Transform3D = _lux_root.global_transform.affine_inverse()
	for mi in _lux_root.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		if node.mesh == null:
			continue
		var rel: Transform3D = inv * node.global_transform
		# 法线要用法线矩阵变换（非等比缩放时不能直接乘 basis）
		var nrm_basis: Basis = rel.basis.inverse().transposed()
		for s in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(s)
			var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var nn: Variant = arrays[Mesh.ARRAY_NORMAL]
			var has_n: bool = nn != null and (nn as PackedVector3Array).size() == vv.size()
			for i in range(vv.size()):
				verts.append(rel * vv[i])
				if has_n:
					normals.append((nrm_basis * (nn as PackedVector3Array)[i]).normalized())
				else:
					normals.append(Vector3.ZERO)
	if verts.is_empty():
		push_warning("Lux3D 模型没有顶点：%s" % lux_model_path)
		return false

	# ── 按方向分格取每格最大的 r（= 最外层表面）──
	#
	# ⚠ 两步过滤，针对实测的「diorama 星球」问题：
	#   ① **法线朝内**的顶点不要 —— 那颗 GLB 有内部壳层（最近顶点 r=0.137，
	#      半径比 4.56），内部壳的法线多半朝里，剔掉能少一大批干扰。
	#   ② 逐格取 max 拿外壳（壳外的树叶、岩石会顶上来，交给后面的中值滤波）。
	var cells := LUX_LAT_BINS * LUX_LON_BINS
	var map := PackedFloat32Array()
	map.resize(cells)
	map.fill(-1.0)
	var skipped_inward := 0
	for i in range(verts.size()):
		var v: Vector3 = verts[i]
		var r: float = v.length()
		if r < 0.000001:
			continue
		var d: Vector3 = v / r
		var n: Vector3 = normals[i]
		# 有法线且明显朝内 → 内部结构，跳过
		if n != Vector3.ZERO and n.dot(d) < -0.15:
			skipped_inward += 1
			continue
		var li := clampi(int((asin(clampf(d.y, -1.0, 1.0)) / PI + 0.5) * LUX_LAT_BINS),
			0, LUX_LAT_BINS - 1)
		var oi := clampi(int((atan2(d.z, d.x) / TAU + 0.5) * LUX_LON_BINS),
			0, LUX_LON_BINS - 1)
		var k := li * LUX_LON_BINS + oi
		if r > map[k]:
			map[k] = r
	if skipped_inward > 0:
		print("[Lux3D] %s：剔除朝内法线顶点 %d 个" % [planet_id, skipped_inward])

	# ── 取中位数当「单位半径」，这样起伏围绕行星半径对称 ──
	var filled: Array[float] = []
	for i in range(cells):
		if map[i] > 0.0:
			filled.append(map[i])
	if filled.is_empty():
		push_warning("Lux3D 高度表全空：%s" % lux_model_path)
		return false
	filled.sort()
	var unit: float = filled[filled.size() / 2]

	# ── 缩放到行星世界半径，并补空洞 ──
	var to_world: float = radius / unit
	for i in range(cells):
		if map[i] > 0.0:
			map[i] = map[i] * to_world
	_fill_lux_gaps(map)
	# ── 中值滤波：压掉树尖 / 岩尖 ──
	#
	# 这一步是「diorama 星球」能落地的关键。逐格取 max 之后，凡是格子里
	# 有树或岩石，取到的就是**树顶**；格子在树之间的，取到的是地面。
	# 于是高度表就是一片锯齿 —— 走上去等于在树冠之间蹦。
	#
	# 中值滤波能把「孤立的尖峰」抹掉而**保留大块平台**：
	#   · 一棵树在赤道上约占 2 格（格宽 = 2πR/192，R=1200 时约 39 米）
	#   · 观测台那块平台约占 10 格以上
	# 半径 2（5×5）、跑 2 遍，正好吃掉树冠、留下平台。
	map = _median_filter_lux(map, 4, 2)
	_lux_height_map = map
	_lux_height_ready = true

	# ── 把模型在「站点附近」压平，让可视网格 = 碰撞体 = terrain_height ──
	#
	# ⚠ 这是 Lux3D 星球特有的坑，程序化星球没有：
	#   `terrain_height()` 在建筑站点附近会把高度**混合压平**成 site_height，
	#   但碰撞体用的是**原始 GLB 网格**（没被压平）。两者一高一低，
	#   洞穴坡道那 12.85 米的下沉就会被地表顶穿 ——
	#   实测 walk_test 的「spiral ramp sample 64」因此翻红。
	#
	#   所以这里按**完全相同的混合公式**把网格顶点也压平，
	#   三份数据（可视 / 碰撞 / 高度查询）从此一致。
	# 平地基准也要走 _lift_lux：terrain_height() 在站点附近会把高度混合成
	# site_height（= 本值），少了这一步整个基地会比周围地形低一截或高一块。
	var site_raw: float = _lift_lux(_sample_lux_map(map, site_direction.normalized()))
	var pad_angle: float = site_pad_radius / radius
	var pad_outer: float = pad_angle * 1.6
	# ⚠ Lux3D 星球把洞穴口稍微放宽一点：
	#   程序化星球的地表在洞口附近本来就是起伏的，玩家被洞口边缘挡住时会顺着
	#   斜坡滑下去；而 Lux3D 星球这里被压成了**一块平地**，洞口边缘变成一道
	#   硬台阶，玩家会被抬到台面上而不是落进坡道。
	#
	#   ⚠ 2026-11-11 B 方案：原来写的是 cave_hole_angle *= 1.4（放宽 40%）。
	#   洞 ×5 之后洞本身就大了 5 倍，再放宽 40% 会开出直径 140 米的大窟窿，
	#   大到射线从洞口穿过去都打不到东西。改成**按米加的固定余量**：
	#   洞口半径 = cave_mouth_radius + 1.5 * prop_scale（放大后多留 7.5 米），
	#   这个余量只用来把压平产生的台阶推出坡道之外，和尺度无关。
	if cave_enabled:
		# 世界尺度算：洞体世界半径 = cave_mouth_radius * prop_scale
		# （underground 的竖井 + 0.6 局部 ≈ +3 世界米，这里一并算进余量）
		var rim_extra: float = 1.5 * prop_scale
		cave_hole_angle = ((cave_mouth_radius + 0.6) * prop_scale + rim_extra) / radius
	_displace_lux_mesh_to_pad(to_world, site_raw, pad_angle, pad_outer)
	# 站点基准高度用**压平后的**值，后面 _ready 里重算时会得到同一个数
	_lux_pad_height = site_raw

	# ── 换成「带平铺细节」的材质 ──
	# Lux3D 原材质是 StandardMaterial3D + 一张 2048² 包全星球的贴图
	# （每像素约 6 米），近看必然糊。这里把它的 albedo 贴图抽出来当基色，
	# 叠一层每 8 米重复的程序化颗粒（三向投影），近看就有质感了。
	_apply_detail_material(to_world)

	# ── 缩放并挂上模型（模型单位 → 米）──
	_lux_root.scale = Vector3.ONE * to_world
	# surface 变量指向第一个网格，供外部只读引用（碰撞走 _lux_root 分支）
	for mi in _lux_root.find_children("*", "MeshInstance3D", true, false):
		surface = mi as MeshInstance3D
		break
	return true


## 把 Lux3D 网格的顶点在站点附近按 `terrain_height` 的平地混合公式压平。
##
## 混合公式必须与 `terrain_height` 里那句完全一致：
##     angular = acos(dir · site_direction)
##     blend   = 1 - smoothstep(pad_angle, pad_outer, angular)
##     h       = lerp(原始高度, site_height, blend)
func _displace_lux_mesh_to_pad(to_world: float, site_h: float,
		pad_angle: float, pad_outer: float) -> void:
	if _lux_root == null or to_world <= 0.0:
		return
	var site_dir: Vector3 = site_direction.normalized()
	var touched := 0
	# ⚠ 2026-11-11 额外一步：把**所有**顶点朝高度表靠拢，消掉尖片。
	#   混入比例 MESH_CONFORM：1 = 完全跟随平滑高度表（最平），0 = 原始几何。
	# ⚠ 2026-11-11 从 0.95 提到 1.0。
	#   0.95 意味着每个顶点仍保留 5% 的原始 GLB 起伏，
	#   而碰撞/地形查询只认 `terrain_height` —— 两份表面差几十米，
	#   玩家就会「看着在地上、实际陷在碰撞面里」，走两步被卡死。
	#   1.0 = 可视网格完全落在 terrain_height 上，三份数据真正同源。
	var conform := 1.0
	# ⚠ 2026-11-11 性能强化（用户：「加载变久那么多,一直卡开始」）。
	#
	#   实测：20 颗行星建场 43.7 秒，其中 41 秒全在这一段 ——
	#   每颗 12~19 万个顶点，每个顶点做三件贵事：
	#     ① _sample_lux_map()  双线性插值查表
	#     ② acos()             反三角函数
	#     ③ generate_normals() 整网格重算法线（在 surface 循环里，按面数跑）
	#
	#   三个优化，都**不改变几何结果**（数学等价，只是少做无用功）：
	#
	#   A. 站点压平只在近处算 acos：
	#      之前对**所有** 16 万顶点都算 acos(dir·site_dir)，
	#      但只有 angular < pad_outer 的才需要。pad_outer 通常 < 0.15 rad，
	#      所以先用**平方距离/点积近似**快速排除远处顶点 —— acos 只在
	#      点积超过 cos(pad_outer) 时才调用。远处顶点直接跳过整个 ② 步。
	#
	#   B. conform == 1.0 时省掉一次 lerp：
	#      lerpf(a, b, 1.0) 恒等于 b，直接赋值即可（本来就要 conform=1.0）。
	#
	#   C. generate_normals 只在**顶点真的动过**时才做：
	#      原代码无条件重算；现在 changed_any 为 false 就跳过，
	#      连 SurfaceTool 都不用建。
	var site_cos: float = cos(pad_outer)
	var site_cos_pad: float = cos(pad_angle)
	for mi in _lux_root.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		if node.mesh == null:
			continue
		var new_mesh := ArrayMesh.new()
		var changed_any := false
		for s in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var local_changed := false
			for i in range(verts.size()):
				var v: Vector3 = verts[i]
				var r: float = v.length()
				if r < 0.000001:
					continue
				var dir: Vector3 = v / r
				# ① 朝平滑高度表靠拢（全星球范围，消尖片）
				# 必须用 _lift_lux 包一层：可视网格 conform 的目标就是
				# terrain_height()，两边不一致玩家就会陷进地里 / 浮在空中。
				var smooth_r: float = _lift_lux(_sample_lux_map(_lux_height_map, dir))
				var blended: float
				if conform >= 0.9999:
					blended = smooth_r
				else:
					blended = lerpf(r * to_world, smooth_r, conform)
				# ② 站点附近再压平 —— **只在近处调 acos**
				var dot: float = dir.dot(site_dir)
				if dot > site_cos:
					# 到这里才真的在 pad_outer 范围内，才值得算角度
					var angular: float = acos(clampf(dot, -1.0, 1.0))
					var blend: float
					if dot >= site_cos_pad:
						blend = 1.0          # 完全在平地区内
					else:
						blend = 1.0 - smoothstep(pad_angle, pad_outer, angular)
					blended = lerpf(blended, site_h, blend)
				verts[i] = dir * (blended / to_world)
				local_changed = true
				touched += 1
			arrays[Mesh.ARRAY_VERTEX] = verts
			if not local_changed:
				# 顶点一个都没动：原样搬过去，省掉 generate_normals
				new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				var mat0: Material = node.mesh.surface_get_material(s)
				if mat0 != null:
					new_mesh.surface_set_material(s, mat0)
				continue
			changed_any = true
			# 顶点动过之后重算法线：尖片的硬边一半来自法线不连续，
			# 平滑法线能让起伏看起来像丘陵而不是碎玻璃。
			var st := SurfaceTool.new()
			st.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
			st.generate_normals()
			var rebuilt := st.commit()
			var mat2: Material = node.mesh.surface_get_material(s)
			if mat2 != null:
				rebuilt.surface_set_material(s, mat2)
			new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
				rebuilt.surface_get_arrays(0))
			if mat2 != null:
				new_mesh.surface_set_material(s, mat2)
			continue

		if changed_any:
			node.mesh = new_mesh
	if touched > 0:
		print("[Lux3D] %s：压平站点周围顶点 %d 个（与 terrain_height 对齐）" % [
			planet_id, touched])


## 把 Lux3D 星球的材质换成「基色贴图 + 平铺细节」。
const DETAIL_SHADER := preload("res://shaders/planet_detail.gdshader")


func _apply_detail_material(world_scale: float) -> void:
	if _lux_root == null:
		return
	for mi in _lux_root.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		if node.mesh == null:
			continue
		for s in range(node.mesh.get_surface_count()):
			var src: Material = node.mesh.surface_get_material(s)
			if src == null:
				src = node.material_override
			if src == null:
				continue
			var albedo_tex: Texture2D = null
			var rough: float = 0.88
			if src is StandardMaterial3D:
				albedo_tex = (src as StandardMaterial3D).albedo_texture
				rough = clampf((src as StandardMaterial3D).roughness, 0.0, 1.0)
			if albedo_tex == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = DETAIL_SHADER
			mat.set_shader_parameter("base_tex", albedo_tex)
			mat.set_shader_parameter("detail_meters", 8.0)
			mat.set_shader_parameter("model_scale", world_scale)
			# 暗色星球（玄渊/缄默）细节弱一点，否则会显得脏
			var strength: float = 0.20 if kind in ["xuanyuan", "jianmo"] else 0.30
			mat.set_shader_parameter("detail_strength", strength)
			mat.set_shader_parameter("roughness_value", rough)
			node.mesh.surface_set_material(s, mat)


## 对高度表做中值滤波（经度环绕、纬度夹紧）。
##
## 为什么用**中值**而不是均值：均值会把树尖的高度「摊」到周围一片，
## 让整片地面抬高；中值直接丢到中间值，孤立的尖峰不影响邻域。
func _median_filter_lux(map: PackedFloat32Array, radius: int, passes: int) -> PackedFloat32Array:
	for _pass in range(passes):
		var src := map.duplicate()
		var side := radius * 2 + 1
		var vals := PackedFloat32Array()
		vals.resize(side * side)
		for li in range(LUX_LAT_BINS):
			for oi in range(LUX_LON_BINS):
				var w := 0
				for dy in range(-radius, radius + 1):
					var yy := clampi(li + dy, 0, LUX_LAT_BINS - 1)
					for dx in range(-radius, radius + 1):
						var xx := (oi + dx + LUX_LON_BINS) % LUX_LON_BINS
						vals[w] = src[yy * LUX_LON_BINS + xx]
						w += 1
				var part := vals.slice(0, w)
				part.sort()
				map[li * LUX_LON_BINS + oi] = part[part.size() / 2]
	return map


## 把高度表里的空洞（没有顶点的方向格）用邻格扩散补上。
##
## 83% 填充率意味着约 17% 的格子是空的：不补的话那些方向采样会得到 -1，
## 玩家走到那里就会掉下去或者瞬移回原点。
func _fill_lux_gaps(map: PackedFloat32Array) -> void:
	var cells := LUX_LAT_BINS * LUX_LON_BINS
	# 最多扩散这么多轮；每轮把「有值格」的邻居填上。
	# 96×192 的格子，17% 空洞最多几轮就能全部覆盖。
	for _pass in range(24):
		var changed := 0
		var snapshot := map.duplicate()
		for li in range(LUX_LAT_BINS):
			for oi in range(LUX_LON_BINS):
				var k: int = li * LUX_LON_BINS + oi
				if snapshot[k] > 0.0:
					continue
				var sum := 0.0
				var n := 0
				# 四邻域；经度环绕，纬度夹紧
				var lon_l: int = (oi - 1 + LUX_LON_BINS) % LUX_LON_BINS
				var lon_r: int = (oi + 1) % LUX_LON_BINS
				var up: int = clampi(li + 1, 0, LUX_LAT_BINS - 1)
				var dn: int = clampi(li - 1, 0, LUX_LAT_BINS - 1)
				for nk in [li * LUX_LON_BINS + lon_l, li * LUX_LON_BINS + lon_r,
						up * LUX_LON_BINS + oi, dn * LUX_LON_BINS + oi]:
					if snapshot[nk] > 0.0:
						sum += snapshot[nk]
						n += 1
				if n > 0:
					map[k] = sum / float(n)
					changed += 1
		if changed == 0:
			break
	# 兜底：极端情况下（整行都空）用行星半径填
	for i in range(cells):
		if map[i] <= 0.0:
			map[i] = radius


## 按方向双线性插值取高度表里的值。
## 地形起伏加强系数（目标 ④「地形也要更多 AI 生成细节，更强的起伏」）。
##
## Lux3D 给的星球模型本身起伏就比程序化强（半径比 4~5 倍），但中值滤波 +
## conform=1.0 之后被抹平了一部分，站在地上看只剩缓坡。
## 这里把「相对设计半径的偏离量」放大，山更高、盆地更深，而球体本身不变。
##
## ⚠ 必须与可视网格、平地基准同步（见文件顶部与本函数的调用点），
##   否则可视面与碰撞面再次分离，玩家会被卡住 —— 那是 2026-11-11 修过一轮的老问题。
const LUX_RELIEF_BOOST := 1.35

## 少数「以水/冰/平原为主」的星球保持较平的起伏，否则海面与冰架会碎成山脊。
const LUX_RELIEF_FLAT_KINDS := ["cangbo", "biluo"]

## 实测起伏最小的几颗（高度表只有 ±2~4%），单独提高加强系数，
## 让它们也有能看的地形层次。实测值见 tests/probe_relief_budget.gd。
const LUX_RELIEF_BOLD_KINDS := ["youdu", "yaoguang", "sue", "yuheng", "danxia", "xuanpu"]
const LUX_RELIEF_BOLD := 1.55

func _lift_lux(h: float) -> float:
	if radius <= 0.0:
		return h
	if kind in LUX_RELIEF_FLAT_KINDS:
		return radius + (h - radius) * 1.06
	if kind in LUX_RELIEF_BOLD_KINDS:
		return radius + (h - radius) * LUX_RELIEF_BOLD
	return radius + (h - radius) * LUX_RELIEF_BOOST


func _sample_lux_height(dir: Vector3) -> float:
	return _lift_lux(_sample_lux_map(_lux_height_map, dir))
	return _sample_lux_map(_lux_height_map, dir)


## 对任意高度表按方向做双线性插值（`_sample_lux_height` 的通用版）。
func _sample_lux_map(map: PackedFloat32Array, dir: Vector3) -> float:
	var lat: float = asin(clampf(dir.y, -1.0, 1.0)) / PI + 0.5     # 0..1
	var lon: float = atan2(dir.z, dir.x) / TAU + 0.5                 # 0..1
	var fy: float = lat * float(LUX_LAT_BINS) - 0.5
	var fx: float = lon * float(LUX_LON_BINS) - 0.5
	var y0 := clampi(int(floorf(fy)), 0, LUX_LAT_BINS - 1)
	var y1 := clampi(y0 + 1, 0, LUX_LAT_BINS - 1)
	var ty: float = clampf(fy - float(y0), 0.0, 1.0)
	var x0i := int(floorf(fx))
	var tx: float = fx - float(x0i)
	var x0 := (x0i % LUX_LON_BINS + LUX_LON_BINS) % LUX_LON_BINS
	var x1 := (x0 + 1) % LUX_LON_BINS
	var v00: float = map[y0 * LUX_LON_BINS + x0]
	var v01: float = map[y0 * LUX_LON_BINS + x1]
	var v10: float = map[y1 * LUX_LON_BINS + x0]
	var v11: float = map[y1 * LUX_LON_BINS + x1]
	var a: float = lerpf(v00, v01, tx)
	var b: float = lerpf(v10, v11, tx)
	return lerpf(a, b, ty)


func _cut_cave_hole(arrays: Array, vertices: PackedVector3Array) -> PackedInt32Array:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices.resize(vertices.size())
		for i in range(vertices.size()):
			indices[i] = i
	var kept := PackedInt32Array()
	var cos_limit := cos(cave_hole_angle)
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		if (a + b + c).normalized().dot(cave_direction) > cos_limit:
			continue
		kept.push_back(indices[i])
		kept.push_back(indices[i + 1])
		kept.push_back(indices[i + 2])
	return kept


## 在洞口附近把三角形递归细分，让洞口边缘的格子小到能表达洞。
##
## 输入输出都是「方向 * terrain_height(方向)」的顶点表 + 索引表，
## 返回 [vertices, indices]。细分只发生在洞口附近的三角形上，
## 整球分辨率不变（否则 20 颗星球的面数会炸）。
##
## 做法：1→4 细分（三条边各取中点）。中点方向取两端点方向的球面中点，
## 再乘 terrain_height 贴地，所以新顶点同样落在地形表面上。
##
## ⚠ 注意 GDScript 的 PackedVector3Array 是**写时复制**：
##   往函数参数里 push_back 不会传回调用方。所以这里自己维护一个
##   Array[Vector3] 工作副本，最后再转回 PackedVector3Array。
func _refine_around_cave(vertices: PackedVector3Array, indices: PackedInt32Array) -> Array:
	if indices.is_empty():
		indices.resize(vertices.size())
		for i in range(vertices.size()):
			indices[i] = i
	var cos_zone: float = cos(cave_hole_angle * 2.6)   # 洞口外 2.6 倍角范围
	var work: Array = []
	work.resize(vertices.size())
	for i in range(vertices.size()):
		work[i] = vertices[i]
	var idx: PackedInt32Array = indices.duplicate()
	for _round in range(3):
		var cache := {}
		var next := PackedInt32Array()
		var refined_count := 0
		for i in range(0, idx.size(), 3):
			var ia: int = idx[i]
			var ib: int = idx[i + 1]
			var ic: int = idx[i + 2]
			var a: Vector3 = work[ia]
			var b: Vector3 = work[ib]
			var c: Vector3 = work[ic]
			var centroid: Vector3 = (a + b + c).normalized()
			if centroid.dot(cave_direction) < cos_zone:
				next.push_back(ia)
				next.push_back(ib)
				next.push_back(ic)
				continue
			var ab: int = _edge_midpoint(cache, work, ia, ib)
			var bc: int = _edge_midpoint(cache, work, ib, ic)
			var ca: int = _edge_midpoint(cache, work, ic, ia)
			next.push_back(ia)
			next.push_back(ab)
			next.push_back(ca)
			next.push_back(ab)
			next.push_back(ib)
			next.push_back(bc)
			next.push_back(ca)
			next.push_back(bc)
			next.push_back(ic)
			next.push_back(ab)
			next.push_back(bc)
			next.push_back(ca)
			refined_count += 1
		idx = next
		if refined_count == 0:
			break
	var out := PackedVector3Array()
	out.resize(work.size())
	for i in range(work.size()):
		out[i] = work[i]
	return [out, idx]


## 取 (ia, ib) 边的球面中点顶点索引（同一轮内同一条边只加一次）。
## work 是 Array[Vector3]，可以原地 push_back。
func _edge_midpoint(cache: Dictionary, work: Array, ia: int, ib: int) -> int:
	var key: int = mini(ia, ib) * 1048576 + maxi(ia, ib)
	if cache.has(key):
		return int(cache[key])
	var a: Vector3 = work[ia]
	var b: Vector3 = work[ib]
	var dir: Vector3 = a.normalized() + b.normalized()
	var new_index: int = work.size()
	if dir.length_squared() < 0.000001:
		work.append((a + b) * 0.5)
	else:
		var d: Vector3 = dir.normalized()
		work.append(d * terrain_height(d))
	cache[key] = new_index
	return new_index


func _build_atmosphere() -> void:
	# 硫坞星 / 磐砂星 / 缄默星 不做大气壳：硫雾用灯光表现，光壳在近距离会露出低模面片。
	# 纭潪鏄?/ 纾愮爞鏄?/ 缂勯粯鏄?涓嶅仛澶ф皵澹筹細纭浘鐢ㄧ伅鍏夎〃鐜帮紝鍏夊３鍦ㄨ繎璺濈浼氶湶鍑轰綆妯￠潰鐗囥€?	# ⚠ 2026-11-11 Lux3D 星球**不加大气层壳**：
	#   实测那圈深色硬边和内部的方块状穿插都来自这个 cull_front 的规则球壳
	#   （Lux3D 贴图本身已经画了大气般的边缘过渡）。
	if lux_model_path != "":
		return
	if kind not in ["qinglan", "cangbo", "zheya", "baiyao", "taiyuan"]:
		return
	# ⚠ 2026-11-11 Lux3D 星球：外壳半径必须**推到地形最高点之外**。
	#
	#   用户：「星球上面那些水怎么处理」——沧波星外面那圈硬边和方块。
	#   根因不是水，是这两个**规则球壳**：
	#     · 大气层 radius × 1.035
	#     · 云层   radius × 1.012
	#   而 Lux3D 地形起伏是 0.92 ~ 1.073 倍半径，于是两个壳都被地形顶穿，
	#   从地表冒出来的那一片就是那些方块状穿插。
	#   这里把壳的基准半径换成「地形最高点」，两个壳整体抬到地表之上。
	var shell_base: float = radius
	if _lux_height_ready:
		var peak := 0.0
		for h in _lux_height_map:
			peak = maxf(peak, h)
		if peak > radius:
			shell_base = peak
	atmosphere = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = shell_base * 1.035
	sphere.height = shell_base * 2.07
	# 分段数提高，避免近距离看到大气球的多边形面片。
	sphere.radial_segments = 96
	sphere.rings = 48
	atmosphere.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.albedo_color = Color(accent_color, 0.07 if kind != "zheya" else 0.035)
	atmosphere.material_override = material
	atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(atmosphere)
	# ⚠ 2026-11-11 Lux3D 星球**不加程序化云层**。
	#
	#   用户：「星球上面那些水怎么处理」——沧波星和青岚星外面的方块状穿插。
	#   排查过程：先怀疑水面球（已关，没用）→ 再怀疑大气层被地形顶穿
	#   （实测高度表只有 1274.6~1302.4，起伏 1.02 倍，根本没顶穿）。
	#   最后把同一个 GLB 拿到 Blender 里渲染对照：**模型本身完全干净**。
	#   所以方块是游戏里额外叠的 `CloudShader` 云层球 —— 噪声贴在一个规则球面上，
	#   而 Lux3D 贴图里本来就画了云和冰盖，两层打架就成块。
	#   这类星球直接跳过云层。
	if kind in ["qinglan", "cangbo"] and lux_model_path == "":
		clouds = MeshInstance3D.new()
		var cloud_sphere := SphereMesh.new()
		cloud_sphere.radius = shell_base * 1.012
		cloud_sphere.height = shell_base * 2.024
		cloud_sphere.radial_segments = 64
		cloud_sphere.rings = 32
		clouds.mesh = cloud_sphere
		var cloud_material := ShaderMaterial.new()
		cloud_material.shader = CloudShader
		cloud_material.set_shader_parameter("cloud_color", Color(0.64, 0.82, 0.88, 0.2 if kind == "qinglan" else 0.32))
		cloud_material.set_shader_parameter("seed", float(abs(planet_id.hash()) % 100))
		clouds.material_override = cloud_material
		clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(clouds)


func _build_landscape() -> void:
	var count := 170
	# ⚠ 星球放大 5 倍后表面积 ×25，物件数量也翻倍，否则空旷得像荒星。
	#   没有再乘 5：每棵树都带一个 StaticBody3D 碰撞体，
	#   20 颗星球 × 850 个碰撞体太贵，×2 已经足够看出层次。
	count *= 2
	match kind:
		"zheya": count = 140
		"cangbo": count = 70
		"xuanjing": count = 160
		"xuanyuan": count = 105
		"baiyao": count = 130
		"pansha": count = 120
		"taiyuan": count = 150
		"liuwu": count = 110
		"jianmo": count = 90
		# 后 10 颗 Lux3D 星球：按设定给不同密度
		"cangwu": count = 160
		"xuanpu": count = 150
		"youdu": count = 130
		"jiangxiao": count = 130
		"danxia": count = 140
		"yaoguang": count = 120
		"jinwu": count = 120
		"sue": count = 110
		"yuheng": count = 110
		"biluo": count = 90
	for i in range(count):
		var direction := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		if direction.distance_to(Vector3.UP) < 0.25:
			continue
		if _near_cave(direction, 0.03):
			continue
		# 基地平地上不长任何东西：那块地形被压平了，长树/晶簇既难看又会堵路
		# （实测：沧波星一个晶簇落在潮汐站台阶上，玩家走不进去）。
		if acos(clampf(direction.dot(site_direction.normalized()), -1.0, 1.0)) \
				< (site_pad_radius / maxf(radius, 1.0)) * 1.1:
			continue
		if kind == "qinglan" and direction.distance_to(Vector3(-0.45, 1.0, -0.28).normalized()) < 0.28:
			continue
		match kind:
			"qinglan":
				if i % 5 == 0:
					_add_rock(direction, rng.randf_range(1.4, 5.8), base_color.lightened(0.15), 0.0)
				else:
					_add_tree(direction, true)
			"zheya":
				if i % 3 == 0:
					_add_crystal(direction, Color("e8e2d2"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.0, 3.6), Color("cdc6b4"), 0.0)
			"cangbo":
				if i % 3 == 0:
					_add_spout(direction)
				else:
					_add_rock(direction, rng.randf_range(2.0, 7.0), Color("286d76"), -1.5)
			"xuanjing":
				if i % 3 == 0:
					_add_crystal(direction, Color("c8cdd4"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(2.0, 8.0), base_color.lightened(0.15), 0.0)
			"xuanyuan":
				_add_rock(direction, rng.randf_range(1.0, 5.0), Color("27373d"), 0.0)
			"baiyao":
				if i % 3 == 0:
					_add_crystal(direction, Color("eef7ff"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.2, 4.8), Color("dfe9ef"), 0.0)
			"pansha":
				_add_rock(direction, rng.randf_range(1.6, 6.4), Color("b99a6b"), 0.0)
			"taiyuan":
				if i % 2 == 0:
					_add_tree(direction, true)
				else:
					_add_rock(direction, rng.randf_range(1.0, 3.8), Color("5e6b52"), 0.0)
			"liuwu":
				if i % 4 == 0:
					_add_crystal(direction, Color("d8e05a"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.4, 5.2), Color("8a8244"), 0.0)
			"jianmo":
				if i % 3 == 0:
					_add_crystal(direction, Color("9b7fd0"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.2, 4.2), Color("241f2b"), 0.0)
			# ── 后 10 颗 Lux3D 星球：只用 AI 资产的树/岩石铺量 ──
			"cangwu":
				if i % 4 != 0:
					_add_tree(direction, true)
				else:
					_add_rock(direction, rng.randf_range(1.6, 5.0), base_color.lightened(0.12), 0.0)
			"xuanpu":
				if i % 3 != 0:
					_add_tree(direction, true)
				else:
					_add_rock(direction, rng.randf_range(1.4, 4.6), base_color.lightened(0.10), 0.0)
			"youdu":
				if i % 6 == 0:
					_add_tree(direction, true)
				else:
					_add_rock(direction, rng.randf_range(1.6, 6.0), Color("2a3550"), 0.0)
			"jiangxiao":
				_add_rock(direction, rng.randf_range(1.8, 6.4), Color("7a3b2a"), 0.0)
			"danxia":
				_add_rock(direction, rng.randf_range(2.0, 7.0), Color("8c4a35"), 0.0)
			"jinwu":
				_add_rock(direction, rng.randf_range(1.8, 6.0), Color("b09050"), 0.0)
			"sue":
				_add_rock(direction, rng.randf_range(1.4, 5.2), Color("cfd4d8"), 0.0)
			"yuheng":
				if i % 7 == 0:
					_add_tree(direction, true)
				else:
					_add_rock(direction, rng.randf_range(1.4, 5.0), Color("9fb6a8"), 0.0)
			"yaoguang":
				_add_rock(direction, rng.randf_range(1.6, 6.2), Color("c8dcea"), 0.0)
			"biluo":
				_add_rock(direction, rng.randf_range(1.2, 4.0), Color("a8c8d0"), -1.0)
	if kind == "cangbo":
		_add_landing_island()
	elif kind == "qinglan":
		_add_home_ruin()
	elif kind == "xuanyuan":
		_add_eye_spires()
	_build_site_cluster()
	_flush_vegetation()


func _build_site_cluster() -> void:
	var site := Vector3.UP
	if kind == "qinglan":
		site = Vector3(-0.06, 1.0, -0.04).normalized()
	for i in range(130):
		var scatter := Vector3(rng.randf_range(-0.32, 0.32), rng.randf_range(-0.32, 0.32), rng.randf_range(-0.32, 0.32))
		var direction := (site + scatter).normalized()
		if direction.distance_to(Vector3.UP) < 0.1:
			continue
		if _near_cave(direction, 0.035):
			continue
		if kind == "qinglan" and direction.distance_to(Vector3.UP) < 0.085:
			continue
		match kind:
			"qinglan":
				if i % 4 == 0:
					_add_rock(direction, rng.randf_range(0.8, 3.2), base_color.lightened(0.18), 0.0)
				else:
					_add_tree(direction, true)
			"zheya":
				if i % 3 == 0:
					_add_crystal(direction, Color("e8e2d2"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.0, 3.6), Color("cdc6b4"), 0.0)
			"cangbo":
				if i % 3 == 0:
					_add_crystal(direction, Color("dff4fb"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.2, 4.0), Color("5c7480"), -1.0)
			"xuanjing":
				if i % 3 == 0:
					_add_crystal(direction, Color("c8cdd4"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(1.2, 4.0), base_color.lightened(0.15), 0.0)
			"xuanyuan":
				_add_rock(direction, rng.randf_range(0.8, 3.0), Color("27373d"), 0.0)
			"baiyao":
				if i % 3 == 0:
					_add_crystal(direction, Color("f2fbff"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(0.8, 3.0), Color("e6eff5"), 0.0)
			"pansha":
				if i % 4 == 0:
					_add_crystal(direction, Color("d8c39a"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(0.9, 3.4), Color("c0a274"), 0.0)
			"taiyuan":
				if i % 3 == 0:
					_add_rock(direction, rng.randf_range(0.7, 2.6), Color("6b7860"), 0.0)
				else:
					_add_tree(direction, true)
			"liuwu":
				if i % 4 == 0:
					_add_crystal(direction, Color("e2e46a"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(0.8, 3.2), Color("8f8748"), 0.0)
			"jianmo":
				if i % 2 == 0:
					_add_crystal(direction, Color("a98ce0"), 0.0)
				else:
					_add_rock(direction, rng.randf_range(0.6, 2.8), Color("2a2433"), 0.0)


func _terrain_normal(direction: Vector3) -> Vector3:
	var dir := direction.normalized()
	var tangent_a := dir.cross(Vector3.UP)
	if tangent_a.length_squared() < 0.01:
		tangent_a = dir.cross(Vector3.RIGHT)
	tangent_a = tangent_a.normalized()
	var tangent_b := dir.cross(tangent_a).normalized()
	var epsilon := 0.008
	var center := surface_position(dir)
	var side_a := surface_position((dir + tangent_a * epsilon).normalized())
	var side_b := surface_position((dir + tangent_b * epsilon).normalized())
	var normal := (side_a - center).cross(side_b - center).normalized()
	if normal.dot(dir) < 0.0:
		normal = -normal
	return normal


func _grass_tuft_mesh() -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = abs(planet_id.hash()) + 3301
	for blade in range(9):
		var angle := local_rng.randf() * TAU
		var distance := local_rng.randf_range(0.0, 0.26)
		var height := local_rng.randf_range(0.36, 0.78)
		var width := local_rng.randf_range(0.025, 0.055)
		var bend := local_rng.randf_range(0.08, 0.22)
		var base := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		var side := Vector3(cos(angle + PI * 0.5), 0.0, sin(angle + PI * 0.5)) * width
		var tip := base + Vector3(cos(angle) * bend, height, sin(angle) * bend)
		surface_tool.add_vertex(base - side)
		surface_tool.add_vertex(base + side)
		surface_tool.add_vertex(tip)
	surface_tool.generate_normals()
	return surface_tool.commit()


## 和 `_surface_parent` 一样，但把整棵子树按 `prop_scale` 放大。
##
## 只给**户外摆件**用（建筑、熔岩柱、晶体、喷口、遗迹、落点岛）。
## 洞穴内部（underground.gd）故意不用它 —— 那是给人走的手工空间，
## 保持人类尺度才对。
func _prop_parent(direction: Vector3, altitude: float) -> Node3D:
	var root := _surface_parent(direction, altitude)
	if root != null and not is_equal_approx(prop_scale, 1.0):
		root.scale = Vector3.ONE * prop_scale
	return root


func _surface_parent(direction: Vector3, altitude: float) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = surface_position(direction, altitude)
	root.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	return root


func _add_tree(direction: Vector3, _collidable := false) -> void:
	# ⚠ 2026-11-12 用户：「程序化的就完全不用了」。
	#   这里只走 Lux3D 的异星树，程序化树已删除。
	#   资产缺失时直接不长树（宁可空一点，也不再拿程序化几何充数）。
	var tree_id := "alien-tree-lo" if _prop_mesh("alien-tree-lo") != null else "alien-tree"
	if _prop_mesh(tree_id) == null:
		return
	_add_prop(tree_id, direction, rng.randf_range(18.0, 40.0) * prop_scale,
		0.0, _prop_tint())


func _crystal_cluster_mesh(height: float) -> ArrayMesh:
	var tool := _merged_tool()
	var main_basis := Basis(Vector3.BACK, 0.06)
	tool.append_from(_cylinder(0.0, 1.15, height, 6), 0,
		Transform3D(main_basis, Vector3(0, height * 0.5, 0)))
	var side_count := 3 + (int(height) % 2)
	for i in range(side_count):
		var angle := TAU * float(i) / float(side_count) + 0.45
		var sub_height := height * (0.34 + 0.16 * float(i % 3))
		var lean := Vector3(cos(angle) * 0.26, 1.0, sin(angle) * 0.26).normalized()
		var basis := Basis(Quaternion(Vector3.UP, lean))
		tool.append_from(_cylinder(0.0, 0.46, sub_height, 5), 0,
			Transform3D(basis, Vector3(cos(angle) * 0.85, sub_height * 0.46, sin(angle) * 0.85)))
	# 底部碎晶座
	tool.append_from(_sphere_mesh(1.5, 7, 4), 0,
		Transform3D(Basis.IDENTITY.scaled(Vector3(1.15, 0.28, 1.15)), Vector3(0, 0.18, 0)))
	tool.generate_normals()
	return tool.commit()


## 载入一个 AI 道具网格（带缓存）。缺失或损坏时返回 null，调用方回退。
##
## GLB 是场景而不是裸网格，所以实例化一次、取第一个 MeshInstance3D 的 mesh，
## 立刻释放实例 —— mesh 资源本身会被 MultiMesh 持有。
static func _prop_mesh(prop_id: String) -> Mesh:
	if _prop_mesh_cache.has(prop_id):
		return _prop_mesh_cache[prop_id]
	var mesh: Mesh = null
	var path: String = PROP_MODELS.get(prop_id, "")
	if path != "" and ResourceLoader.exists(path):
		var packed = load(path)
		if packed is PackedScene:
			var inst = (packed as PackedScene).instantiate()
			if inst != null:
				for mi in inst.find_children("*", "MeshInstance3D", true, false):
					var m: Mesh = (mi as MeshInstance3D).mesh
					if m != null:
						mesh = m
						break
				inst.free()
	_prop_mesh_cache[prop_id] = mesh
	return mesh


## 把 AI 网格包成可被 MultiMesh 实例化的版本：
##   · 复制一份（各星球独立，互不影响材质）
##   · 每个面的材质复制后打开 vertex_color_use_as_albedo，
##     这样 MultiMesh 的实例色能直接给整颗星球的道具调色，
##     而 AI 生成的贴图本身仍然是原样
static func _prop_mesh_for_instancing(prop_id: String) -> Mesh:
	var base: Mesh = _prop_mesh(prop_id)
	if base == null:
		return null
	var copy: Mesh = base.duplicate()
	for s in range(copy.get_surface_count()):
		var mat: Material = copy.surface_get_material(s)
		if mat is StandardMaterial3D:
			var dup: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
			dup.vertex_color_use_as_albedo = true
			copy.surface_set_material(s, dup)
	return copy


## 排入一个 AI 道具（地标）。size 是**世界米数**（道具高度）。
## altitude 是相对地表的抬升（负值=压入地面）。
## 可交互道具：prop_id → 交互类型。全部复用已有 AI 资产，零额度。
##
## ⚠ 只收「走到跟前看得清」的东西；远处高山巨石不入表，
##   否则每颗星球会有几百个可交互点，查询和存档都变贵。
const INTERACTIVE_PROPS := {
	"crystal-cluster": "crystal",
	"crystal-cluster-lo": "crystal",
	"crystal-flora": "crystal",
	"crystal-flora-lo": "crystal",
	"cargo-pod": "cargo",
	"cargo-pod-lo": "cargo",
	"antenna-mast": "cargo",
	"geyser-basin": "vent",
	"vent": "vent",
	"vent-lo": "vent",
	"ruin-arch": "relic",
	"stone-idol": "relic",
	"obelisk": "relic",
	"rubble-wall": "relic",
}

## 每颗星球的可交互点：{id, kind, dir, size, used}
var interactive_spots: Array = []


func _add_prop(prop_id: String, direction: Vector3, size: float,
		altitude := 0.0, tint := Color.WHITE, respect_cap := true) -> void:
	if _prop_mesh(prop_id) == null:
		return
	if not prop_queue.has(prop_id):
		prop_queue[prop_id] = []
	# 限额：超过上限的调用直接丢弃，避免面数爆炸（见 PROP_INSTANCE_CAP 的说明）。
	# 地标（respect_cap=false）由 PLANET_PROPS 精确控制数量，不受铺量限额约束。
	if respect_cap:
		var cap: int = int(PROP_INSTANCE_CAP.get(prop_id, 20))
		if (prop_queue[prop_id] as Array).size() >= cap:
			return
	var ndir: Vector3 = direction.normalized()
	prop_queue[prop_id].append({
		"dir": ndir,
		"size": size,
		"altitude": altitude,
		"yaw": rng.randf() * TAU,
		"tint": tint,
	})
	# 可交互道具另外记一条，供 main.gd 的 E 键查询。
	var ikind := String(INTERACTIVE_PROPS.get(prop_id, ""))
	if ikind != "":
		interactive_spots.append({
			"id": prop_id,
			"kind": ikind,
			"dir": ndir,
			"size": size,
			"altitude": altitude,
			"used": false,
		})


## 离玩家最近的可交互道具。没有则返回空字典。
##
## `world_pos` 是世界坐标（玩家脚下）；内部换成星球局部坐标再比距离。
## 距离用「实体最大半径 x 1.6」当阈值，体量大的东西走近就能触发。
func nearest_interactive(world_pos: Vector3, extra := 4.0) -> Dictionary:
	if interactive_spots.is_empty():
		return {}
	var local: Vector3 = global_transform.affine_inverse() * world_pos
	var best := -1
	var best_d := INF
	for i in range(interactive_spots.size()):
		var spot: Dictionary = interactive_spots[i]
		if bool(spot["used"]):
			continue
		var p: Vector3 = surface_position(spot["dir"], float(spot["altitude"]))
		var reach: float = maxf(float(spot["size"]) * 0.75, 3.0) + extra
		var d: float = local.distance_to(p)
		if d < reach and d < best_d:
			best_d = d
			best = i
	if best < 0:
		return {}
	var out: Dictionary = (interactive_spots[best] as Dictionary).duplicate()
	out["index"] = best
	out["distance"] = best_d
	return out


## 标记某个交互点已用掉（采集/拆解过就不能再采）。
func consume_interactive(index: int) -> void:
	if index >= 0 and index < interactive_spots.size():
		(interactive_spots[index] as Dictionary)["used"] = true


## 给站点附近的道具补静态碰撞体。
##
## 为什么只补站点附近：一颗星球有 ~180 个道具实例，全加 StaticBody3D 太贵
## （每个都是独立物理对象）。玩家真正会走进去的只有基地周围那一片，
## 远处的高山巨石纯属背景，穿过去也没人发现。
## 半径 = 2.2 倍平地半径，正好覆盖「看得清细节」的范围。
## 每类道具最多补多少个碰撞体。
##
## ⚠ 2026-11-11 实测教训：一开始只给「站点 2.2 倍平地半径（506 米弧长）」内的
##   实例加碰撞体，结果 90 个树实例里**命中 0 个** —— 因为 _build_landscape 的
##   方向是整球随机分布，506 米只占周长的 4%。
##   现在改成「站点附近的优先 + 按队列顺序补到上限」，两种覆盖都拿到。
const PROP_COLLIDER_CAP := 34


func _add_prop_colliders(entries: Array, prop_id: String) -> void:
	var limit: float = site_pad_radius * 2.2
	var profile := _prop_collider_profile(prop_id)
	var site_dir: Vector3 = site_direction.normalized()
	# 先挑出站点附近的（玩家真会走过去），再按顺序补到上限。
	var picked: Array = []
	var rest: Array = []
	for e in entries:
		var arc: float = acos(clampf((e["dir"] as Vector3).dot(site_dir), -1.0, 1.0)) * radius
		if arc <= limit:
			picked.append(e)
		else:
			rest.append(e)
	for e in rest:
		if picked.size() >= PROP_COLLIDER_CAP:
			break
		picked.append(e)
	picked = picked.slice(0, PROP_COLLIDER_CAP)
	for e in picked:
		var dir: Vector3 = e["dir"]
		var size: float = float(e["size"])
		var origin: Vector3 = surface_position(dir, float(e["altitude"]))
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), origin)
		var collision := CollisionShape3D.new()
		if profile.x < 0.3:
			var shape := CylinderShape3D.new()
			shape.radius = profile.x * size
			shape.height = profile.y * size
			collision.shape = shape
			collision.position.y = profile.y * size * 0.5
		else:
			var shape := SphereShape3D.new()
			shape.radius = profile.x * size
			collision.shape = shape
			collision.position.y = profile.x * size
		body.add_child(collision)
		add_child(body)


## 把 prop_queue 里排好的道具落成 MultiMeshInstance3D。
##
## 关键点：GLB 自己的尺寸是「1 单位高」的不确定值，所以按**包围盒高度**归一化，
## 让 size 参数真正等于世界米数；原点也对齐到模型底面（否则会一半埋进地里）。
## 某个道具该用什么近似碰撞体。
## 竖直细长的（树/塔/方尖碑/晶簇）用胶囊，块状的（岩石/穹顶）用球。
## 返回 Vector2(半径系数, 高度系数)，都是相对「道具高度 size」的比例。
func _prop_collider_profile(prop_id: String) -> Vector2:
	if prop_id.contains("tree") or prop_id.contains("tower") \
			or prop_id.contains("obelisk") or prop_id.contains("spire") \
			or prop_id.contains("crystal"):
		return Vector2(0.16, 0.92)   # 细高：半径 16% 高度
	return Vector2(0.42, 0.62)       # 块状：半径 42% 高度


## 在星球上挑一个放道具的方向。
## near_site = true 时贴着基地外围（玩家一眼能看到），否则全球散布，
## 两种情况都避开基地平地本身和洞口。
func _pick_prop_direction(near_site: bool, min_clear_m := 0.0) -> Vector3:
	var site: Vector3 = site_direction.normalized()
	var pad_angle: float = site_pad_radius / radius
	# 平地上及「平地 + 净空」范围内一律不放：道具的碰撞半径可能几十米，
	# 只看中心会在边缘压回平地，把基地楼梯/门口堵死（实测沧波星潮汐站）。
	var min_arc: float = pad_angle + min_clear_m / maxf(radius, 1.0)
	for _attempt in range(28):
		var dir: Vector3
		if near_site:
			var perp: Vector3 = site.cross(Vector3.FORWARD)
			if perp.length_squared() < 0.01:
				perp = site.cross(Vector3.RIGHT)
			perp = perp.normalized()
			var axis: Vector3 = perp.rotated(site, rng.randf() * TAU)
			var ang: float = pad_angle * rng.randf_range(1.2, 3.2)
			dir = site.rotated(axis, ang).normalized()
		else:
			dir = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1),
				rng.randf_range(-1, 1))
			if dir.length_squared() < 0.001:
				continue
			dir = dir.normalized()
		var arc: float = acos(clampf(dir.dot(site), -1.0, 1.0))
		if arc < min_arc:
			continue                      # 别压在基地平地 + 净空范围内
		if _near_cave(dir, 0.06):
			continue                      # 别堵洞口
		return dir
	return Vector3.ZERO


## 按 kind 布置这一颗星球的 AI 地标（目标 ③）。
##
## 与铺量的树/岩石分开：这里是「少而大、能认出来」的地标，
## 每颗星球的组合不同，所以 20 颗星球各有各的地貌性格。
func _build_landmark_props() -> void:
	var table: Array = PLANET_PROPS.get(kind, [])
	if table.is_empty():
		return
	for entry in table:
		var prop_id: String = entry[0]
		if _prop_mesh(prop_id) == null:
			continue
		var count: int = int(entry[1])
		var size_min: float = float(entry[2]) * prop_scale
		var size_max: float = float(entry[3]) * prop_scale
		var near: bool = bool(entry[4])
		var floating: bool = PROP_FLOATING.has(prop_id)
		for _i in range(count):
			var size := rng.randf_range(size_min, size_max)
			var dir := _pick_prop_direction(near, size * 0.5)
			if dir == Vector3.ZERO:
				continue
			# 悬浮的抬高到半空；其余底部微沉入地表，避免悬空缝。
			var altitude: float = size * 0.35 if floating else -size * 0.04
			_add_prop(prop_id, dir, size, altitude, _prop_tint(), false)
	# 每颗星球的**签名地标**：一颗一个，尺寸最大、最醒目，一眼能认出是哪颗星。
	# 命名约定 lm-<kind>，见 PROP_MODELS。
	var sig_id := "lm-%s" % kind
	if _prop_mesh(sig_id) != null:
		for _i in range(2):
			var sig_size: float = rng.randf_range(22.0, 40.0) * prop_scale
			# 净空按尺寸的一半给：地标可能 100~200 米高，碰撞半径约 0.42×尺寸
			var sig_dir := _pick_prop_direction(true, sig_size * 0.5)
			if sig_dir == Vector3.ZERO:
				continue
			_add_prop(sig_id, sig_dir, sig_size, -2.0 * prop_scale,
				_prop_tint(), false)
	# 通用环境物件：按星球气候分配的蘑菇/枯树/冰棱/石像…
	for gentry in GENERIC_PROPS.get(kind, []):
		var gid: String = gentry[0]
		if _prop_mesh(gid) == null:
			continue
		for _i in range(int(gentry[1])):
			var gsize: float = rng.randf_range(float(gentry[2]), float(gentry[3])) * prop_scale
			var gdir := _pick_prop_direction(false, gsize * 0.5)
			if gdir == Vector3.ZERO:
				continue
			_add_prop(gid, gdir, gsize, -2.0 * prop_scale, _prop_tint(), false)
	# 基地周边点缀：平地外缘一圈小物件（走出去不再是一片荒）
	_build_base_surroundings()
	# 互动种子：保证每颗星球都有晶簇/货舱/喷口可用
	_build_interactive_seeds()
	# 铺量混排：4~5 种低模混在一起，替代「同一种模型重复 90 次」
	_build_scatter_mix()
	# 目标 ④：大型地貌件（把已有资产放大，零额度）
	_build_landform_props()
	# 地标与地貌件都是在 _build_landscape 之后才排进队列的，所以必须在这里补 flush
	# （_flush_props 内部有 _flushed_prop_ids 去重，铺量那批不会重复实例化）。
	_flush_props()


## 互动种子：保证每颗星球都有四种互动可用。
##
## ⚠ 实测青岚星只有 10 个遗迹点、**晶簇/货舱/喷口一个都没有**，
##   因为它的铺量组合里没这些类型 —— 玩家跑到母星就采不到东西。
##   这里按固定配额补齐，与星球风格无关。
const INTERACTIVE_SEED := [
	["crystal-cluster-lo", 2, 2, 4],
	["cargo-pod-lo", 1, 3, 5],
	["vent-lo", 1, 2, 4],
]


func _build_interactive_seeds() -> void:
	for entry in INTERACTIVE_SEED:
		var pid: String = entry[0]
		if _prop_mesh(pid) == null:
			continue
		for _i in range(int(entry[1])):
			var size: float = rng.randf_range(float(entry[2]), float(entry[3])) * prop_scale
			# 放在基地外缘一圈（和旁边缀同一个区域），玩家一出基地就能碰到
			var site: Vector3 = site_direction.normalized()
			var perp: Vector3 = site.cross(Vector3.FORWARD)
			if perp.length_squared() < 0.01:
				perp = site.cross(Vector3.RIGHT)
			perp = perp.normalized()
			var axis: Vector3 = perp.rotated(site, rng.randf() * TAU)
			var pad_angle: float = site_pad_radius / maxf(radius, 1.0)
			var dir: Vector3 = site.rotated(axis, pad_angle * rng.randf_range(1.05, 1.45)).normalized()
			if _near_cave(dir, 0.03):
				continue
			_add_prop(pid, dir, size, -1.0 * prop_scale, _prop_tint(), false)


## 基地周边点缀（零额度）：平地外缘一圈小体量物件。
##
## 为什么要单独做：`_pick_prop_direction` 为了不堵楼梯/门口，
## 要求道具离站心 ≥ pad_radius + size/2，结果**平地边缘一圈是空的**，
## 玩家走出基地就是荒地。
## 这里用小体量物件贴着平地外缘排一圈（不压平地、不加碰撞）。
func _build_base_surroundings() -> void:
	var ring: Array = BASE_SURROUNDINGS.get(kind, [])
	if ring.is_empty():
		return
	var site: Vector3 = site_direction.normalized()
	var pad_angle: float = site_pad_radius / maxf(radius, 1.0)
	for entry in ring:
		var pid: String = entry[0]
		if _prop_mesh(pid) == null:
			continue
		for _i in range(int(entry[1])):
			# 平地外缘 1.02~1.75 倍角度（不压平地）
			var perp: Vector3 = site.cross(Vector3.FORWARD)
			if perp.length_squared() < 0.01:
				perp = site.cross(Vector3.RIGHT)
			perp = perp.normalized()
			var axis: Vector3 = perp.rotated(site, rng.randf() * TAU)
			var ang: float = pad_angle * rng.randf_range(1.02, 1.75)
			var dir: Vector3 = site.rotated(axis, ang).normalized()
			if _near_cave(dir, 0.03):
				continue
			var size: float = rng.randf_range(float(entry[2]), float(entry[3])) * prop_scale
			_add_prop(pid, dir, size, -1.0 * prop_scale, _prop_tint(), false)


## 每颗星球基地周边的小物件：[prop_id, 数量, 尺寸下限, 尺寸上限]（设计米数）
const BASE_SURROUNDINGS := {
	"qinglan": [["thorn-shrub-lo", 14, 2, 3], ["alien-mushroom-lo", 8, 2, 4], ["rock-cluster-lo", 6, 2, 4]],
	"zheya": [["thorn-shrub-lo", 10, 2, 3], ["lava-boulder-lo", 10, 2, 4], ["rock-cluster-lo", 6, 2, 4]],
	"cangbo": [["ice-spike-lo", 14, 2, 4], ["crystal-flora-lo", 10, 1, 2]],
	"xuanjing": [["crystal-flora-lo", 14, 1, 2], ["rock-spire-lo", 6, 2, 4]],
	"xuanyuan": [["lava-boulder-lo", 12, 2, 4], ["rock-spire-lo", 6, 2, 4]],
	"baiyao": [["ice-spike-lo", 16, 2, 4], ["crystal-flora-lo", 8, 1, 2]],
	"pansha": [["dune-arch-lo", 5, 4, 8], ["rock-cluster-lo", 12, 2, 4]],
	"taiyuan": [["thorn-shrub-lo", 16, 2, 3], ["alien-mushroom-lo", 6, 2, 4]],
	"liuwu": [["lava-boulder-lo", 12, 2, 4], ["vent-lo", 5, 2, 4]],
	"jianmo": [["crystal-flora-lo", 12, 1, 2], ["rock-spire-lo", 8, 2, 5]],
	"jiangxiao": [["lava-boulder-lo", 12, 2, 4], ["rock-cluster-lo", 8, 2, 4]],
	"cangwu": [["thorn-shrub-lo", 14, 2, 3], ["alien-mushroom-lo", 10, 2, 4]],
	"jinwu": [["lava-boulder-lo", 12, 2, 4], ["dune-arch-lo", 4, 4, 7]],
	"yuheng": [["crystal-flora-lo", 12, 1, 2], ["rock-cluster-lo", 10, 2, 4]],
	"sue": [["rock-cluster-lo", 14, 2, 4], ["crystal-flora-lo", 6, 1, 2]],
	"danxia": [["rock-cluster-lo", 12, 2, 4], ["dune-arch-lo", 4, 4, 7]],
	"biluo": [["crystal-flora-lo", 14, 1, 2], ["rock-cluster-lo", 8, 2, 4]],
	"youdu": [["ice-spike-lo", 12, 2, 4], ["crystal-flora-lo", 8, 1, 2]],
	"yaoguang": [["crystal-flora-lo", 16, 1, 2], ["crystal-cluster-lo", 6, 2, 4]],
	"xuanpu": [["alien-mushroom-lo", 12, 2, 4], ["thorn-shrub-lo", 10, 2, 3]],
}

## 铺量混排布置（见 SCATTER_MIX）。
func _build_scatter_mix() -> void:
	for entry in SCATTER_MIX.get(kind, []):
		var pid: String = entry[0]
		if _prop_mesh(pid) == null:
			continue
		for _i in range(int(entry[1])):
			var size: float = rng.randf_range(float(entry[2]), float(entry[3])) * prop_scale
			var dir := _pick_prop_direction(false, size * 0.5)
			if dir == Vector3.ZERO:
				continue
			_add_prop(pid, dir, size, -1.5 * prop_scale, _prop_tint(), false)


## 布置大型地貌件（目标 ④）。复用已有 AI 资产放大，零额度消耗。
func _build_landform_props() -> void:
	var table: Array = LANDFORM_PROPS.get(kind, [])
	if table.is_empty():
		return
	for entry in table:
		var prop_id: String = entry[0]
		if _prop_mesh(prop_id) == null:
			continue
		var count: int = int(entry[1])
		var size_min: float = float(entry[2]) * prop_scale
		var size_max: float = float(entry[3]) * prop_scale
		var floating: bool = PROP_FLOATING.has(prop_id)
		for _i in range(count):
			# 地貌件放得远一点，别压住基地
			var size := rng.randf_range(size_min, size_max)
			var dir := _pick_prop_direction(false, size * 0.5)
			if dir == Vector3.ZERO:
				continue
			var altitude: float = size * 0.45 if floating else -size * 0.05
			_add_prop(prop_id, dir, size, altitude, _prop_tint(), false)


## 这颗星球的道具色调。用 MultiMesh 实例色调制 AI 贴图，
## 让同一套 AI 资产在 20 颗星球上呈现各自的色系（用户：「保留配色，呼应名字」）。
func _prop_tint() -> Color:
	# ⚠ 2026-11-12 修「AI 道具全黑」：
	#   这个值是**乘数**（材质开了 vertex_color_use_as_albedo，
	#   最终 albedo = AI 贴图 × 实例色）。
	#   旧版直接拿星球基色当乘数（青岚 2b4f52 = 0.17/0.31/0.32），
	#   把贴图亮度压掉 70~80%，实机截图里道具几乎全黑。
	#   现在改成「近白 + 轻微色相」：基色提亮到 0.62 以上，
	#   再夹到 0.68~1.0，保留 AI 贴图的明暗层次，只带一点该星球的色调。
	var lifted: Color = base_color.lightened(0.62)
	var j: float = rng.randf_range(-0.05, 0.07)
	return Color(
		clampf(lifted.r + j, 0.68, 1.0),
		clampf(lifted.g + j, 0.68, 1.0),
		clampf(lifted.b + j, 0.68, 1.0),
		1.0)


## 这颗星球的岩石更适合「尖峰」而不是「圆石堆」吗。
## 晶体/黑曜石/裂隙类用尖峰，其余用层积圆石。
func _prefers_spires() -> bool:
	return kind in ["xuanjing", "jianmo", "youdu", "jiangxiao", "xuanpu"]


func _flush_props() -> void:
	if prop_queue.is_empty():
		return
	for prop_id in prop_queue.keys():
		var entries: Array = prop_queue[prop_id]
		if entries.is_empty():
			continue
		if _flushed_prop_ids.has(prop_id):
			continue
		_flushed_prop_ids[prop_id] = true
		var mesh: Mesh = _prop_mesh_for_instancing(prop_id)
		if mesh == null:
			continue
		var aabb: AABB = mesh.get_aabb()
		var base_h: float = maxf(aabb.size.y, 0.001)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = entries.size()
		for i in range(entries.size()):
			var e: Dictionary = entries[i]
			var dir: Vector3 = e["dir"]
			var k: float = float(e["size"]) / base_h
			var basis := Basis(Quaternion(Vector3.UP, dir))
			basis = basis.rotated(dir, float(e["yaw"]))
			basis = basis.scaled(Vector3.ONE * k)
			# 底面贴地：模型底面在 aabb.position.y*k 处，把它抬回 0
			var origin: Vector3 = surface_position(dir,
				float(e["altitude"]) - aabb.position.y * k)
			mm.set_instance_transform(i, Transform3D(basis, origin))
			mm.set_instance_color(i, e["tint"])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Prop_%s" % prop_id
		instance.multimesh = mm
		instance.visibility_range_end = 2200.0
		add_child(instance)
		_add_prop_colliders(entries, prop_id)


func _flush_vegetation() -> void:
	# 只落 AI 道具。程序化的树/岩石/草丛已全部删除（2026-11-12）。
	_flush_props()


func _merged_tool() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return tool


func _add_rock(direction: Vector3, size: float, color: Color, altitude: float) -> void:
	# 同 _add_tree：只走 AI 岩石，程序化岩石已删除。
	size *= prop_scale
	var rock_id := "rock-spire" if _prefers_spires() else "rock-cluster"
	if _prop_mesh(rock_id + "-lo") != null:
		rock_id += "-lo"
	if _prop_mesh(rock_id) == null:
		return
	_add_prop(rock_id, direction, maxf(size, 1.0), altitude, color)


func _add_crystal(direction: Vector3, color: Color, altitude: float) -> void:
	# 只走 AI 发光晶簇（低模变体铺量用）。
	if _prop_mesh("crystal-cluster-lo") == null:
		return
	_add_prop("crystal-cluster-lo", direction,
		rng.randf_range(16.0, 34.0) * prop_scale, altitude, color)


func _add_spout(direction: Vector3) -> void:
	# 只走 AI 喷口（低模变体）。
	if _prop_mesh("vent-lo") == null:
		return
	_add_prop("vent-lo", direction,
		rng.randf_range(14.0, 28.0) * prop_scale, -1.0 * prop_scale, _prop_tint())


func _limit_range(node: Node, end: float) -> void:
	if node is GeometryInstance3D:
		node.visibility_range_end = end
	for child in node.get_children():
		_limit_range(child, end)


func _add_landing_island() -> void:
	# ⚠ 2026-11-12：沧波星的 site_direction 就是 Vector3.UP，
	#   着陆石岛和潮汐站**同位置**。实验对照：
	#     石岛开着 → walk_test「the player enters the tide station」红
	#     石岛关掉 → 0 失败
	#   所以任何「够大能看见」的模型都会把站包进去。
	#   现在改成：偏离站点约 120 米的 AI 平顶方山
	#   （50 米级），**不加碰撞** —— 站点平地本来就被
	#   terrain_height 压平了，玩家走的是地形面。既满足「不用程序化几何」，
	#   也不会挡住基地。
	var pid := "lf-mesa-plateau" if _prop_mesh("lf-mesa-plateau") != null else ""
	if pid == "":
		return
	var site: Vector3 = site_direction.normalized()
	var perp: Vector3 = site.cross(Vector3.FORWARD)
	if perp.length_squared() < 0.01:
		perp = site.cross(Vector3.RIGHT)
	perp = perp.normalized()
	var dir: Vector3 = site.rotated(perp, 120.0 / radius).normalized()
	_add_prop(pid, dir, 10.0 * prop_scale, -2.0 * prop_scale,
		base_color.lightened(0.2), false)


func _add_home_ruin() -> void:
	# 青岚星的巨石遗迹 → AI 遗迹拱门。
	var direction := Vector3(0.68, 0.65, -0.3).normalized()
	var size: float = 30.0 * prop_scale
	if _prop_mesh("ruin-arch") != null:
		_add_prop("ruin-arch", direction, size, -1.0 * prop_scale,
			base_color.lightened(0.25), false)
	var root := _surface_parent(direction, 0.0)
	if root == null:
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = size * 0.22
	shape.height = size * 0.8
	collision.shape = shape
	collision.position.y = size * 0.4
	body.add_child(collision)
	root.add_child(body)
	_limit_range(root, 1600.0)


func _add_eye_spires() -> void:
	# 玄渊星的 11 根尖塔环 → AI 黑曜石尖峰环形排列。
	# ⚠ 用 -lo 版：11 个实例，高模会白吃 20 万面。
	var pid := "rock-spire-lo" if _prop_mesh("rock-spire-lo") != null else "rock-spire"
	if _prop_mesh(pid) == null:
		return
	for i in range(11):
		var angle := float(i) / 11.0 * TAU
		var direction := Vector3(cos(angle) * 0.36, 1.0, sin(angle) * 0.36).normalized()
		# 逐根拔高，保留原来那种「环形渐高」的译峥感
		var size: float = (10.0 + float(i) * 1.1) * prop_scale
		_add_prop(pid, direction, size, -1.5 * prop_scale, base_color.lightened(0.1), false)


const RING_SHADER := preload("res://shaders/planet_ring.gdshader")


func _build_ring() -> void:
	var inner: float = radius * 1.34
	var outer: float = radius * 2.15
	var ring := MeshInstance3D.new()
	ring.name = "PlanetRing"
	ring.mesh = _annulus_mesh(inner, outer, 192)

	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	# 配色从行星主色派生，但**去饱和**——环是碎冰和尘埃，不该是饱和的橙。
	#
	# ⚠ 2026-11-11 调暗一轮：第一版环偏亮偏白，比星球本体还抢眼，
	#   尤其玄渊星（近黑）配亮白环反差过大。整体压暗、透明度也降一点，
	#   让环退到星球后面当背景。暗色行星（玄渊/缄默）再额外压一档。
	var is_dark_planet: bool = kind in ["xuanyuan", "jianmo"]
	var light_col: Color = Color("b8b2a8").lerp(accent_color.lightened(0.35), 0.30)
	var dark_col: Color = Color("4a4642").lerp(accent_color.darkened(0.35), 0.22)
	if is_dark_planet:
		light_col = light_col.darkened(0.28)
		dark_col = dark_col.darkened(0.25)
	mat.set_shader_parameter("ring_light", Vector3(light_col.r, light_col.g, light_col.b))
	mat.set_shader_parameter("ring_dark", Vector3(dark_col.r, dark_col.g, dark_col.b))
	mat.set_shader_parameter("base_alpha", 0.52 if is_dark_planet else 0.64)
	mat.set_shader_parameter("inner_fade", 0.09)
	mat.set_shader_parameter("outer_fade", 0.26)
	mat.set_shader_parameter("seed", float(abs(planet_id.hash()) % 977) * 0.137)
	ring.material_override = mat

	# 整个环面**统一倾角**（不再每条各转一个角度），略绕 Y 轴错开让边缘不总正对镜头
	ring.rotation_degrees = Vector3(22.0, 14.0, 8.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring_node = ring


## 生成一个扁平圆环面（annulus）：法线朝 +Y，UV 的 v = 径向 0→1。
##
## 为什么不用 TorusMesh：那是**有截面厚度的圆管**，从侧面看是一根管子；
## 行星环在视觉上必须是一张零厚度的薄片。
func _annulus_mesh(inner: float, outer: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0: float = TAU * float(i) / float(segments)
		var a1: float = TAU * float(i + 1) / float(segments)
		var c0: float = cos(a0)
		var s0: float = sin(a0)
		var c1: float = cos(a1)
		var s1: float = sin(a1)
		var in0 := Vector3(c0 * inner, 0.0, s0 * inner)
		var in1 := Vector3(c1 * inner, 0.0, s1 * inner)
		var out0 := Vector3(c0 * outer, 0.0, s0 * outer)
		var out1 := Vector3(c1 * outer, 0.0, s1 * outer)
		var u0: float = float(i) / float(segments)
		var u1: float = float(i + 1) / float(segments)
		# 两个三角组成一个环形四边形；法线统一朝上
		_annulus_tri(st, in0, out0, out1,
			Vector2(u0, 0.0), Vector2(u0, 1.0), Vector2(u1, 1.0))
		_annulus_tri(st, in0, out1, in1,
			Vector2(u0, 0.0), Vector2(u1, 1.0), Vector2(u1, 0.0))
	return st.commit()


func _annulus_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	for pair in [[a, ua], [b, ub], [c, uc]]:
		st.set_normal(Vector3.UP)
		st.set_uv(pair[1])
		st.add_vertex(pair[0])


func _build_water() -> void:
	water_shell = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 128
	sphere.rings = 64
	water_shell.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.5, 0.62, 0.32)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.12
	material.metallic = 0.3
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	water_shell.material_override = material
	water_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water_shell)
	_update_water()


func _update_water() -> void:
	if water_shell == null:
		return
	var t: float = game.elapsed if game != null else 0.0
	var loop_length: float = float(game.LOOP_DURATION) if game != null else 1020.0
	var phase := clampf(t / loop_length, 0.0, 1.0)
	var level := lerpf(-21.0, 1.5, smoothstep(0.0, 1.0, phase))
	level += sin(t * 0.018) * 0.7
	var sea_radius := site_height + level
	water_shell.scale = Vector3.ONE * sea_radius
	water_shell.position = Vector3.ZERO


func _process(_delta: float) -> void:
	if game != null:
		_update_orbit()
		_update_water()
		if not terrain_collision_done:
			# 飞船或玩家进入 4 倍半径就建地形碰撞，落地前早就建好。
			var limit := radius * 4.0
			var player_close: bool = game.player != null and global_position.distance_to(game.player.global_position) < limit
			var ship_close: bool = game.ship != null and global_position.distance_to(game.ship.global_position) < limit
			if player_close or ship_close:
				_ensure_terrain_collision()
	if clouds != null:
		clouds.rotation.y += _delta * 0.002


## 垂直起伏幅度（米）。⚠ 2026-11-11 轨道 ×10 之后这里也 ×10，
## 否则星系拉大后这段起伏会缩成几乎一条平线（相对尺度）。
const ORBIT_WOBBLE := 500.0


func _update_orbit() -> void:
	var t: float = game.elapsed if game != null else 0.0
	var angle := orbit_phase + orbit_speed * t
	position = Vector3(cos(angle) * orbit_radius, orbit_height + sin(angle * 1.7) * ORBIT_WOBBLE, sin(angle) * orbit_radius)


## 行星此刻的公转速度（米/秒，世界坐标）。
##
## 就是 `_update_orbit` 里那条轨迹对时间的导数：
##   p = (cos a·R, h + sin(1.7a)·W, sin a·R)，  a = phase + speed·t，W = ORBIT_WOBBLE
##   v = (−sin a·R·ω, cos(1.7a)·W·1.7·ω, cos a·R·ω)
##
## 为什么不直接拿两帧位置差去近似：`_process` 的 delta 会抖，
## 而且行星每秒只走 10～50 米，差分出来的噪声比信号还大。
## 解析式既准确又和 `elapsed` 严格同步。
##
## 飞船侧要用它的两个地方：
##   · 自动航行把「期望速度」加上它 —— 否则飞船是在追一个会跑的靶子，
##     落到地面附近时相对速度全被行星的公转抵掉，剖面就白算了；
##   · 撞击判定用「相对地面」的速度 —— 一颗以 50 m/s 掠过你的行星
##     扫过一艘静止的飞船，那是真撞击，不能因为飞船自己没动就免责。
func orbital_velocity() -> Vector3:
	var t: float = game.elapsed if game != null else 0.0
	var angle := orbit_phase + orbit_speed * t
	var w := orbit_speed
	return Vector3(
		-sin(angle) * orbit_radius * w,
		cos(angle * 1.7) * ORBIT_WOBBLE * 1.7 * w,
		cos(angle) * orbit_radius * w)


func _material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = Color(color, 1.0)
		material.emission_energy_multiplier = emission
	return material


func _mesh(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	return instance


func _sphere_mesh(radius: float, segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


func _cylinder(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	return mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh
