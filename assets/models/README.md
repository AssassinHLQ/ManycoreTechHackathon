# 外部 3D 资产的导入规则

本项目的几何一直是**程序化生成**的（`architecture.gd` / `planet.gd` / `station.gd` 都是代码建模），
`assets/` 里原先只有字体。从这里开始会有外部模型进来，所以先把规矩写清楚 ——
不然半年后没人说得清「这个 glb 是哪来的、能不能商用、为什么是 1:1 还是 1:100」。

---

## 一、目录与命名

```
assets/models/
  <slug>/                 一个模型一个目录，slug 全小写、连字符分隔
    model.glb             主文件，固定叫 model.glb（不跟原名，原名进 manifest）
    textures/             贴图（**外链**：glb 用 uri 相对路径引用这里）
    LICENSE_MANIFEST.json 由 build_license_manifest.py 汇总，见第三节
```

- **一个目录只放一个模型**。多文件（.blend + 贴图）留在 `_tmp_assets/<slug>/` 做溯源，不放进来。
- `.import` 文件由 Godot 生成，**要提交**（它记录了导入设置）。

### 贴图为什么必须外链

Godot 的 GLTF 导入器（`gltf/embedded_image_handling=1`）会把 GLB 里**内嵌**的贴图
**抽取**成磁盘上的独立文件，材质最终引用的是那些独立文件。
也就是说：贴图在 GLB 里存一遍、在磁盘上又存一遍 —— **双份**。

所以贴图一律走 `textures/` 外链（glb 里 `images[].uri = "textures/xxx.png"`），
磁盘上只有一份，GLB 只剩几何。飞船的 baseColor 单张 18.6 MB，双份就是 37 MB 白扔。

## 二、导入设置（scale / 材质）

| 项 | 规则 | 理由 |
|---|---|---|
| 单位 | 1 单位 = 1 米，导入后**人工量一遍包围盒** | Sketchfab 导出的比例千奇百怪，1.0 = 1m 不成立 |
| 根节点 | 缩放与旋转**打平到网格里**（Apply Transform），根节点保持 identity | 否则运行时算位置/碰撞要一直补偿 |
| 原点 | 放在**底部中心**（落地物体）或质心（漂浮物体） | 摆放时直接 `global_position = 地面点` |
| 朝向 | **Godot 约定：机头/前进 = -Z、机顶 = +Y、翼展 = X** | 朝向必须**实测**，不能照抄注释 —— 见下方「朝向怎么验」 |
| 碰撞 | 不信任模型自带碰撞；用 BoxShape3D / 简化凸包自己加 | glb 的碰撞网格往往过于精细 |
| 材质 | 统一转 `StandardMaterial3D`，禁用模型自带的 PBR 极端值 | 有自己的 key_light 与环境光，直接照搬会过曝 |
| 贴图 | **外链到 `textures/`**；源文件保留原始分辨率，进包尺寸用导入设置里的 `process/size_limit` 控制 | 贴图逐张独立导入，峰值内存只剩单张，不再有「四张 4096² 一起导入撑爆 Godot」的问题。**法线贴图必须无损（PNG）**，JPEG 的块效应会破坏法线产生假高光 |
| 导入压缩 | `compress/mode=2`（VRAM Compressed）+ `mipmaps/generate=true` + `detect_3d/compress_to=0` | mode=0（无损）会把 4096² PNG **原样**塞进 `.ctex`，一张就 11.9 MB；mode=2 走 BC 压缩，4096² 降到 10.7 MB。实测 3 MB 的 WebP 源用 mode=0 导入，出来仍是 9.9 MB —— **无损容器会把有损压缩的收益全吃掉**。网页版 preset 本来就是 `texture_format/s3tc_bptc=true`，mode=2 正好对上 |
| 三角面 | 单体 ≤ 150k；远景剪影 ≤ 3k | 按**实测**定：probe_model_cost.gd 量到归航站 512,736 面、飞船 9,133 面、整个场景 1,626,162 面。规则取「不超过站体的三分之一」→ 150k（原来拍的 20k / 60k 两个数字都被实测推翻过） |

`tools/check_model_imports.py` 会把上面几条能量化的（三角面 / 贴图尺寸 / 节点数）扫一遍
（内嵌与外链贴图都算）。

### 体积怎么控（实测数据）

网页版是唯一的发布形态，包体直接等于首屏下载量，所以贴图尺寸必须算着来。
以飞船为例（原始下载件 38.8 MB）：

| 做法 | baseColor | normal | ORM | pck 体积 |
|---|---|---|---|---|
| 全 4096 PNG + 无损导入 | 4096² | 4096² | 2048² | **35.6 MB**（gzip 24.9 MB） |
| baseColor 4096，其余导入降一档 | 4096² | 2048² | 1024² | **25.6 MB**（gzip 18.5 MB） |

同样是 4K，**baseColor 值得保，normal / ORM 不值得**：
baseColor 是涂装、编号、铆钉、蒙皮划痕 —— 4096² 一眼就比 1024² 清楚；
normal 画的是粗糙蒙皮起伏、ORM 是低频的粗糙度/金属度 —— 降到 2048/1024 后
逐帧对比**看不出差别**。这个取舍由 `tools/fix_ship_mipmaps.py` 的 `SIZE_LIMITS` 表控制。

另外两条：

- **删掉没用的贴图。** 飞船的 emissive 原始贴图整张是黑的（实测最大值 2/255，
  非零像素只有 10398 个），视觉上完全不发光，却占 2.67 MB pck 空间 ——
  用 `tools/ship_textures.py --drop emissive` 从材质和 GLB 里一起摘掉。
- **别信「源码多大」，看 `process/size_limit`。** 源 PNG 可以留 4096 当母版，
  真正进包的是导入时降采样后的版本 —— 两者是不同的事。

### 顶点量化这条路，Godot 走不通（2026-11-09 实测）

高面数模型的顶点数据是体积大头。青岚星（Lux3D 生成，364290 面）的 GLB 里：

| 数据 | 体积 |
|---|---|
| 索引 uint32 | 4.37 MB |
| 位置 float32 | 3.56 MB |
| 法线 float32 | 3.56 MB |
| UV float32 | 2.38 MB |
| **合计** | **13.23 MB**（贴图已外链，不在内） |

直觉上把位置/法线/UV 从 float32 量化成 16-bit 定点（`KHR_mesh_quantization`）
能省 34%（实测 13.23 → 8.70 MB）。**但 Godot 4.7.1 不支持这个扩展**，
导入直接报：

```
ERROR: glTF: Can't import file 'model', required extension
       'KHR_mesh_quantization' is not supported.
```

所以这条路在本项目**暂时不通**，要压体积只能：
① 降面数（重生成或 retopology）；② 接受体积；③ 等 Godot 上游支持。

（量化脚本已删除 —— 留着是死代码。这段记录是为了别再踩一次。）

### 朝向怎么验（2026-11-08 踩过的坑）

旧版 `tools/slim_ship.py` 的注释写「原模型 Y-up，机头 -Y、机顶 +Z，绕 X 轴 +90° 即可」，
脚本也就只做了这一个旋转。**结果飞船是横着飞的** —— 前进方向是 -Z，
而机头仍在 -X，差 90°。玩家从座舱看出去是机腹侧面，还以为是镜头摆歪了。

三个教训：

1. **别信注释，信几何。** 脚本要用端面切片密度自己判定机头端、包围盒自己判定轴语义。
2. **注意坐标系换算。** Blender 是 Z-up，导出 glTF 时（`export_yup=True`）做一次
   `M: (x,y,z) -> (x,z,-y)`；Godot 导入 glTF 时**不再转**。「Blender 里摆好」≠「Godot 里摆好」。
3. **必须有截图回归。** `tests/probe_ship_facing.gd` 从模型六个轴向各拍一张，
   `-Z` 必须看到机头、`+Z` 必须看到发动机 —— 数字对不代表眼睛对。

`tools/slim_ship.py` 现在会自己量、自己算朝向，并在结尾打印 Godot 空间的
「机高应最小 / 机长应最大 / 机头在 -Z / 底部 y=0」四条断言；
`tests/probe_ship_facing.gd` 的六向截图是最终确认。

## 三、许可闸门（硬性）

**没有 manifest 条目的模型不许进 `assets/models/`。**

`LICENSE_MANIFEST.json` 由 `_合规审查_20261104/build_license_manifest.py` 从
根目录的 `ASSET_LICENSE_TABLE.html` 生成，只收「商用 OK」（CC BY 4.0）的条目。每条含：

```json
{
  "slug": "black-hole",
  "original_file": "black-hole.zip",
  "title": "Black Hole",
  "author": "…",
  "license": "CC BY 4.0",
  "attribution": "“Black Hole” by …, CC BY 4.0",
  "source_url": "…"
}
```

- **CC BY 4.0**：可以商用，但**必须署名**。`attribution` 字段的原文要出现在
  游戏的「素材与署名」页（`handbook.gd` 第七节附近）或随包 README 里。
  这条不是形式主义：CC BY 不署名就是违约，和没授权一样。
- **CC BY-NC\***：禁商用。已在 `_隔离区_侵权风险_请勿使用/`，`assets/` 永不接收。
- **授权不明**：等同不可用（见 `_模型授权存档/未查明_授权状态登记.txt`）。

### AI 生成资产（第二类条目）

上面那套是给**第三方**素材准备的。本项目还有一类**自己用 AI 生成**的资产，
例如 `qinglan-planet`（Aholo Lux3D text-to-3D 生成的青岚星）：

- `license` 写「本项目自有（AI 生成内容，无第三方版权与署名义务）」
- 不需要署名（没有第三方权利人），但**仍要留条目**，把生成工具、
  生成参数（模型版本 / 目标面数 / 实际面数 / 消耗的额度）记下来
- 这类条目**手工维护**：`build_license_manifest.py` 只从
  `ASSET_LICENSE_TABLE.html` 重建，重新生成会**冲掉**这些条目，
  跑完生成脚本要检查一下还在不在

## 四、接入流程

1. `_tmp_assets/<slug>/` 放原始下载（zip 解开、留 .blend 做溯源）
2. 在 `_合规审查_20261104` 里跑 `build_license_manifest.py` → 确认该资产在 manifest 里
3. **几何 + 贴图交给脚本**，别手工在 Blender 里摆：
   ```
   python tools/ship_build.py --src <原始.glb> --out-dir assets/models/<slug>
   ```
   这一步做三件事：Blender 烘焙变换并按 Godot 约定修正朝向、原点摆到底部中心；
   贴图按语义名抽成 `textures/` 下的独立文件并让 glb 改用 uri 外链；
   最后打印校验（外链是否成功、三角面数、每张贴图的分辨率与体积）。
   换模型只改 `--src`，脚本会自己量轴向和机头端，不用改代码。
4. **贴图导入设置**：`python tools/fix_ship_mipmaps.py`
   （开 mipmap、切 VRAM 压缩、按 `SIZE_LIMITS` 设每张的进包尺寸上限）
5. **删掉没用的贴图**：`python tools/ship_textures.py --glb ... --out ... --drop emissive`
   （材质和 GLB 里的引用一起摘掉，否则导出时那张图还是会被打进 pck）
6. 跑 `python tools/check_model_imports.py` 看预算（三角面 / 贴图 / 节点 / 许可闸门）
7. 在 `_arisu_learn` 那个独立小工程里先摆一次、看一眼（不动主工程）
8. 主工程里用 `preload` / `load` 挂上，**加一处就截一张图**，视觉回归基线跟着更新
9. **朝向必须用六向截图确认**：跑 `godot --path . --script res://tests/probe_ship_facing.gd`，
   看 `captures/facing_minus_z.png` 是机头、`facing_plus_z.png` 是发动机。
   数字断言过了不代表眼睛过了 —— 这次的横飞就是这么漏过去的。
10. **导一次网页版量体积**：`导出网页版.bat`，看 `build/web/index.pck` 的大小。
    贴图改尺寸后一定要重新量 —— pck 才是玩家下载的东西。
