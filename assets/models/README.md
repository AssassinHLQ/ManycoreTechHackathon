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
    textures/             贴图（如果 glb 是外链贴图而不是内嵌）
    LICENSE_MANIFEST.json 由 build_license_manifest.py 汇总，见第三节
```

- **一个目录只放一个模型**。多文件（.blend + 贴图）留在 `_tmp_assets/<slug>/` 做溯源，不放进来。
- `.import` 文件由 Godot 生成，**要提交**（它记录了导入设置）。

## 二、导入设置（scale / 材质）

| 项 | 规则 | 理由 |
|---|---|---|
| 单位 | 1 单位 = 1 米，导入后**人工量一遍包围盒** | Sketchfab 导出的比例千奇百怪，1.0 = 1m 不成立 |
| 根节点 | 缩放与旋转**打平到网格里**（Apply Transform），根节点保持 identity | 否则运行时算位置/碰撞要一直补偿 |
| 原点 | 放在**底部中心**（落地物体）或质心（漂浮物体） | 摆放时直接 `global_position = 地面点` |
| 碰撞 | 不信任模型自带碰撞；用 BoxShape3D / 简化凸包自己加 | glb 的碰撞网格往往过于精细 |
| 材质 | 统一转 `StandardMaterial3D`，禁用模型自带的 PBR 极端值 | 有自己的 key_light 与环境光，直接照搬会过曝 |
| 贴图 | ≤ 1024×1024（纯远景 ≤ 512） | 项目是低多边形风，2k/4k 贴图既没必要也吃显存。发光贴图可再降一档并转 JPEG：GLB 是走网页导出的，体积直接算进首包 |
| 三角面 | 单体 ≤ 150k；远景剪影 ≤ 3k | 按**实测**定：probe_model_cost.gd 量到归航站 504,036 面、飞船 9,416 面、整个场景 1,460,256 面。规则取「不超过站体的三分之一」→ 150k（原来拍的 20k / 60k 两个数字都被实测推翻过） |

`check_model_imports.py` 会把上面几条能量化的（三角面 / 贴图尺寸 / 节点数）扫一遍。

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

## 四、接入流程

1. `_tmp_assets/<slug>/` 放原始下载（zip 解开、留 .blend 做溯源）
2. 在 `_合规审查_20261104` 里跑 `build_license_manifest.py` → 确认该资产在 manifest 里
3. 导出/整理成 `assets/models/<slug>/model.glb`，按第二节的规则改比例、打平原点
4. 跑 `check_model_imports.py` 看预算（三角面 / 贴图 / 节点）
5. 在 `_arisu_learn` 那个独立小工程里先摆一次、看一眼（不动主工程）
6. 主工程里用 `preload` / `load` 挂上，**加一处就截一张图**，视觉回归基线跟着更新
