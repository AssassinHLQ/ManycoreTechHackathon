# THIRD_PARTY_NOTICES / 第三方组件与内容声明

> 本文件用于履行第三方组件的署名、许可声明义务，并说明仓库内的非原创内容来源。
> 最后更新：2026-11-18

## 0. 版权与许可状态

本项目以 **AGPL-3.0** 发布，见第 5 节。全文见仓库根目录 `LICENSE`。

本文件不授予任何第三方内容的再许可——下文所列内容仍归其各自权利人所有。

### 授权署名清单速查

| 内容 | 作者 / 来源 | 许可与分发时需保留的内容 |
|---|---|---|
| 五个已导入的外部模型 / 点云 | Loïc Norgeot、Nestaeric、re1monsen、Ethan Cox | CC BY 4.0；作品名、作者、原作链接、许可证链接及修改说明，逐项见 3.2.6 |
| Pixel UI Sci-Fi Free 图标 | heyheythere / Spyridon Pikoulas | CC BY 4.0；来源和修改说明见 3.6 |
| UI Minimalism SciFi 面板贴图 | Wenrexa | CC0 1.0；自愿致谢，见 3.5 |
| 星野文楷 / Noto Sans Symbols 2 字体子集 | LXGW / The Klee Project Authors / The Noto Project Authors | SIL OFL 1.1；保留版权与许可全文，修改版字体说明见 3.4 |
| Godot Engine 运行时 | Godot Engine contributors、Juan Linietsky、Ariel Manzur | MIT；保留版权与许可全文，见 3.3 |
| Lux3D 生成的星球、家具和道具 | Aholo Lux3D（群核科技） | 平台服务条款与参赛协议；本清单不另行授予商用或再分发权，见 3.2.1–3.2.5 |
| 早期 HTML 原型内嵌的 Three.js | three.js authors | MIT；版权与许可全文见 3.1 |

模型台账为 `assets/models/LICENSE_MANIFEST.json`：截至本次更新共有 214 条记录，
其中 5 条为已导入的 CC BY 4.0 模型、17 条为未导入的历史候选，192 条为 Lux3D 生成记录
（含历史版本；不等于当前场景实际加载数量）。`imported` 记录历史导入状态，不保证文件仍存在。
已导入 CC BY 模型的作者、原作页、路径及修改说明在台账中逐项维护。

主菜单的「授权与署名」可展开查看当前外部模型署名、UI 来源及许可全文。
Win/Web 导出预设显式包含本文件、模型台账、`LICENSE` 和 `assets/licenses/*.txt`；
这些设置适用于后续重新导出的包，不代表旧 `build/` 或 `demo/` 已更新。

---

## 1. AI 生成内容声明（图片）

`前期讨论/` 目录下的 6 个图片文件**均为 AI 图像生成服务的产出**，不是摄影作品，
不对应任何真实的房间、场所或事件：

| 文件 | 尺寸 | 说明 |
|---|---|---|
| `125aad1c8b53184b05307c74dac71ec3.jpg` | 1672×941 | AI 生成概念图 |
| `56c42bac5f74b0c4a34942b9ded0c32d.jpg` | 1672×941 | AI 生成概念图 |
| `b49ac7798214404b942859ee88b7db88.jpg` | 1672×940 | AI 生成概念图 |
| `62748e6a4782e41cc5cce8cee20003fa.png` | 1672×941 | AI 生成概念图 |
| `62ab930484957bcd6f2345e785cfc99b.png` | 2048×768 | AI 生成概念图（三联拼图） |
| `be684e4aa035d9773df7d8d6eaf5cc46.png` | 1672×941 | AI 生成概念图 |

具体说明：

- 图片用于方案可视化与参赛展示，**画面中的人物为模型生成的合成形象**，与任何真实人物无关，
  不表示任何真实人物、品牌或机构对本项目的认可、合作或背书。
- AI 生成结果可能包含虚构、失真或不存在的事物细节，**不应作为产品规格、空间尺寸或工程依据**。
- 图片由外部 AI 图像生成服务产出；生成所用模型名称未随文件记录，故此处不作具体标注。
- 若后续需要将这些图片用于对外商业宣传，建议重新生成并复核构图、文字与人像相关的合规风险。

---

## 2. 视频素材声明

`前期讨论/6272da821cdd122ed205d93f598850c0.mp4`

- 该视频为**团队成员用手机拍摄其本人电脑屏幕**所得的原创录屏素材，**不是 AI 生成视频**，
  也不来自任何第三方素材库。
- 画面中浏览器地址栏为本地回环地址（`127.0.0.1`），即团队成员本机运行的网页原型；
  录屏内容为该项目方案讨论过程中的界面演示。
- 拍摄者已同意将该片段收录于本仓库，用于方案讨论与参赛展示。
- 如画面中出现的任何第三方界面元素、商标或素材，其权利仍归各自权利人所有；
  本仓库对其不作任何关联、合作、授权或背书声明。

---

## 3. 第三方开源组件

### 3.1 Three.js

仓库内六个 HTML 为**单文件交付物**，各自内嵌了 Three.js 运行时代码（含 `GLTFLoader`、
`OrbitControls` 等 examples 模块，与主库同为 MIT 许可）：

| 文件 | 内嵌 Three.js 版本 |
|---|---|
| `前期讨论/parallel-world-home.html` | r186（ES Module 构建） |
| `前期讨论/世界种子-Demo04.html` | r147（UMD 构建） |
| `前期讨论/文物修复师-Demo03.html` | r147（UMD 构建） |
| `前期讨论/MH.html` | r180（ES Module 构建） |
| `前期讨论/世界的夹层.html` | r170 |
| `前期讨论/造物主-Demo07.html` | r147（UMD 构建） |

Three.js 以 MIT 许可证发布，许可全文如下：

```
The MIT License

Copyright © 2010-2024 three.js authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

项目地址：https://github.com/mrdoob/three.js

> 说明：六个 HTML 是单独分发即可运行的成品。为满足 MIT 条款中“随副本附带版权与许可声明”的要求，
> 已在每个文件 `<!DOCTYPE html>` / `<!doctype html>` **之后**（避免触发 quirks 模式）插入许可声明注释，
> 因此单独下载任一 HTML 也能看到许可归属。其中 `世界的夹层.html` 直接内联完整 MIT 全文，
> 其余文件为指向本文件的摘要注释。

### 3.2 3D 模型资产（GLB）

#### 3.2.1 内嵌于 HTML 的模型

`世界种子-Demo04.html` 与 `文物修复师-Demo03.html` 内的 3D 模型（青铜爵、越王勾践剑、
三星堆面具、史莱姆、小恶魔、宝箱、水晶簇等）由 **Aholo Lux3D（群核科技）** 的文生 3D
服务生成，以 base64 内嵌进 HTML。

- 这些资产的权属**以 Aholo Lux3D 平台服务条款与参赛协议为准**，不由本仓库的版权声明决定。
- 若用于参赛之外的产品化、批量分发或商业发行，需自行向平台确认授权范围。

#### 3.2.2 游戏内的星球模型（`assets/models/*-lux3d*`）

游戏中的可着陆行星使用 **Aholo Lux3D（群核科技）** 文生 3D 服务生成的球体模型，
以 `.glb` 文件形式存放：

| 目录 | 对应天体 |
|---|---|
| `assets/models/qinglan-planet` + `qinglan-planet-v5` | 青岚星（母星，两版并存，v5 为当前使用版） |
| `assets/models/zheya-lux3d-v2` | 赭崖星 |
| `assets/models/cangbo-lux3d-v2` | 沧波星 |
| `assets/models/xuanjing-lux3d-v2` | 悬晶星 |
| `assets/models/xuanyuan-lux3d-v2` | 玄渊星 |
| `assets/models/baiyao-lux3d-v2` | 白曜星 |
| `assets/models/pansha-lux3d-v2` | 磐砂星 |
| `assets/models/taiyuan-lux3d-v2` | 苔垣星 |
| `assets/models/liuwu-lux3d-v2` | 硫坞星 |
| `assets/models/jianmo-lux3d-v2` | 缄默星 |
| `assets/models/jiangxiao-lux3d` | 江晓星 |
| `assets/models/cangwu-lux3d` | 苍梧星 |
| `assets/models/jinwu-lux3d` | 金乌星 |
| `assets/models/yuheng-lux3d` | 玉衡星 |
| `assets/models/sue-lux3d` | 素娥星 |
| `assets/models/danxia-lux3d` | 丹霞星 |
| `assets/models/biluo-lux3d` | 碧落星 |
| `assets/models/youdu-lux3d` | 幽都星 |
| `assets/models/yaoguang-lux3d` | 瑶光星 |
| `assets/models/xuanpu-lux3d` | 玄圃星 |

（第一版 `*-lux3d`（无 `-v2` 后缀）曾在开发中用于对比，已于 2026-11-12 删除以控制仓库体积；
现在保留的是各天体的替换版 `-v2`。）

- **生成方式**：通过 Aholo Lux3D 的文生 3D（text-to-3D）能力产出基础球体几何与贴图，
  再由本项目做缩放、地形噪声叠加、高度表烘焙与材质调整。
- **权属**：以 Aholo Lux3D 平台服务条款与参赛协议为准。本项目在此致谢该服务。
- **使用限制**：同 3.2.1，若用于参赛之外的产品化或商业发行，需自行向平台确认授权范围。
- **未使用 AI 图像生成模型**：这些是 3D 生成服务的产出，不是图片生成。

#### 3.2.3 阁楼线家具与摆件（`assets/models/props/attic`、`attic-worlds`）

阁楼及其后的六个口袋世界里共 52 件写实家具与摆件，同样由 **Aholo Lux3D（群核科技）**
的文生 3D 服务生成（G1-Turbo 档），以 `.glb` + 外部贴图形式存放：

| 目录 | 件数 | 内容 |
|---|---|---|
| `assets/models/props/attic` | 32 | 茶桌 / 茶壶 / 茶杯 / 木凳 / 书架 / 旧木箱 / 矮柜 / 提灯 / 唱片机 / 地毯 / 燕子 / 挂画 / 旅行小册；第二批：四扇门 / 门框 / 镜框 / 四件信物 / 天气旋钮 / 茶叶罐 / 小碟 / 云团 / 星图桌 / 雪堆 / 冰柱 / 石火塘 / 倒木 / 雨巷尽头的门 / 墙面立管 / 镜面基座 |
| `assets/models/props/attic-worlds` | 20 | 雪松 / 路灯 / 雪橇 / 火塘 / 木牌 / 望远镜 / 飞艇 / 云灯塔 / 绞盘 / 风琴 / 护林灯 / 水车 / 木鼓 / 蘑菇 / 油纸伞 / 石猫 / 纸船 / 棱镜之心 / 镜塔 |

- **生成方式**：逐件文生 3D，按尺寸设定目标面数（10k~20k）；
  贴图经本项目重打包压缩（2048 PNG → 1024 JPEG，法线贴图保持 PNG 无损）。
- **权属与使用限制**：同 3.2.1 / 3.2.2。
- **回退机制**：这些模型在代码中均为「可选增强」——缺失时自动退回程序化几何，
  游戏不会因缺少模型而无法运行。

#### 3.2.4 太空站站内家具（`assets/models/props/station`，**不入库**）

另有 14 件太空站家具（座椅 / 控制台 / 花箱 / 观景望远镜 / 舱门 / 长凳 / 墙面屏 /
货运箱 / 洞穴工作灯 / 顶撑钢柱 / 木箱 / 补给罐 / 通讯天线 / 信标柱）由 Lux3D 生成，
但**已列入 `.gitignore` 不入版本库**（为控制仓库体积）。
它们同样全部带程序化回退，缺失不影响运行；需要完整复现时见 `tools/gen_batch3.py`。

#### 3.2.5 星球表面道具（`assets/models/props/*`，99 件）

各星球表面的植被、岩石、遗迹、矿机、天线、化石等 99 件道具，同样由
**Aholo Lux3D** 文生 3D 生成，覆盖：异星树 / 岩石群 / 岩柱 / 遗迹拱门 / 方尖碑 /
穹顶居所 / 信号塔 / 晶簇 / 石桥 / 能量电池 / 控制台 / 休眠舱 / 信标 / 采矿机 /
燃料罐 / 全息板 / 补给箱 / 管线 / 通讯碟 / 散热塔 / 数据库 / 化石 / 石堆 等。

- **权属与使用限制**：同 3.2.1。

#### 3.2.6 已导入的外部模型与点云（CC BY 4.0）

以下五项来自 Sketchfab，均按 **Creative Commons Attribution 4.0 International** 使用。
许可证：[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。

| 作品与原作页 | 作者 | 项目路径 / 用途 | 本项目所做修改 |
|---|---|---|---|
| [A Windy Day](https://sketchfab.com/3d-models/fb78f4cc938144e6902dd5cff354d525) | [Loïc Norgeot](https://sketchfab.com/norgeotloic) | `assets/models/one-dim-star/model.glb`；一维星点云 | 去除节点的多余缩放及缩放动画；点云顶点保留；运行时用顶点色着色并按距离分批隐藏 |
| [Black Hole](https://sketchfab.com/3d-models/e410da98b1e5445eae2acafaaa53587d) | [Nestaeric](https://sketchfab.com/Nestaeric) | `assets/models/black-hole/model.glb`；远景黑洞卡冈图雅 | 保留几何；调整运行时缩放和发光；吸积盘改为程序化径向着色 |
| [Space Station](https://sketchfab.com/3d-models/0da4a24e7edd49159737675ffcc06228) | [re1monsen](https://sketchfab.com/re1monsen) | `assets/models/space-station/model.glb`；远景布景站 | FBX 转 GLB、烘焙变换、统一单位、原点移至质心、贴图外链；运行时摆放与自转 |
| [Space Station 3](https://sketchfab.com/3d-models/a7a6ad10261149cab31aa394bfcf8940) | [re1monsen](https://sketchfab.com/re1monsen) | `assets/models/space-station-3/model.glb`；远景布景站 | blend 转 GLB、烘焙变换、统一单位、原点移至质心、重挂三套材质并外链贴图；运行时摆放与自转 |
| [SpaceShip Fighter  - Version 1 [MESHY 6]](https://sketchfab.com/3d-models/68f13997ad7d4e9280c2afdf889a05fe) | [Ethan Cox](https://sketchfab.com/EthanfromEngland) | `assets/models/ship-fighter/model.glb`；玩家飞船 | 贴图外链及性能压缩、移除近黑色发光贴图、烘焙变换、校正原点和朝向；运行时调整尺寸与材质 |

两个外部空间站用于远景布景；可进入的六廊「归航站」站体由项目代码构建。
上表是对已导入素材的署名，不表示原作者对游戏的认可或背书。
标题、作者及授权依据来自项目留存的原始资产授权表 `ASSET_LICENSE_TABLE.html`；
历史授权记录不等同于对当前作品网页或下载权限的保证。

### 3.3 Godot Engine（Windows / Web 运行时）

`demo/` 下的《借一扇晴天》网页版由 **Godot Engine 4.7.1** 导出，
其中 `index.wasm`、`index.js` 与运行时逻辑包含 Godot Engine 代码。

Godot Engine 以 MIT 许可证发布，版权归 Godot Engine contributors 与 Juan Linietsky、Ariel Manzur 所有。
许可全文见 [`assets/licenses/godot-MIT.txt`](assets/licenses/godot-MIT.txt)；
历史网页版另保留 [`demo/licenses/godot-MIT.txt`](demo/licenses/godot-MIT.txt)。

引擎内含第三方库的版权与许可全文见
[`assets/licenses/GODOT_THIRD_PARTY.txt`](assets/licenses/GODOT_THIRD_PARTY.txt)，
由本机 Godot 4.7.1 的 `Engine.get_copyright_info()` 与 `Engine.get_license_info()` 生成。
更换导出用引擎时，用同一引擎 headless 运行 `tools/update_engine_notices.gd` 更新该文件。
官方许可说明：<https://godotengine.org/license/>。

项目地址：https://godotengine.org

### 3.4 字体：星野文楷（上游 LXGW WenKai 霞鹜文楷）/ Noto Sans Symbols 2

界面文本与符号使用两份**修改版**（子集）字体：

| 文件 | 上游字体 | 版权归属 | 许可 | 本项目所做修改 |
|---|---|---|---|---|
| `assets/ui_font.ttf` | LXGW WenKai Medium（霞鹜文楷）1.530 | Copyright 2021-2026 LXGW (https://github.com/lxgw/LxgwWenKai), with Reserved Font Name '霞鹜', '霞鶩', '落霞孤鹜', '落霞孤鶩' and 'LXGW'.<br>Copyright 2020 The Klee Project Authors (https://github.com/fontworks-fonts/Klee) | SIL OFL 1.1 | ① 裁剪为子集（7,864 码点，含 GB2312、常用标点符号及署名所需的补充字形）；② **改名为「星野文楷 Starward WenKai」**（见下方保留字体名合规说明）；③ name 表中的版权与许可声明原样保留 |
| `assets/ui_symbols.ttf` | Noto Sans Symbols 2 2.008 | Copyright 2022 The Noto Project Authors (https://github.com/notofonts/symbols) | SIL OFL 1.1 | 裁剪为子集，仅保留界面用到的 3 个码点（▬ ◈ ✦） |

- 当前导出所附许可全文：[`assets/licenses/OFL-LXGWWenKai.txt`](assets/licenses/OFL-LXGWWenKai.txt)、
  [`assets/licenses/OFL-NotoSansSymbols2.txt`](assets/licenses/OFL-NotoSansSymbols2.txt)。历史网页版的副本位于 `demo/licenses/`。
- SIL OFL 1.1 允许使用、研究、修改、嵌入与随软件分发（含商业发行），但**不得单独售卖字体本身**；
  修改版必须继续以 OFL 发布，且**不得使用原字体声明的保留字体名**。
- **保留字体名合规说明**：LXGW WenKai 声明了保留字体名 `霞鹜` / `霞鶩` / `落霞孤鹜` / `落霞孤鶩` / `LXGW`。
  本项目的子集属于 OFL 意义上的「修改版」，因此**已将家族名改为「星野文楷 Starward WenKai」**，
  不再使用上述任何保留名，也未使用 LXGW / Fontworks 的名称或商标进行宣传、推广或背书；
  `霞鹜文楷` / `LXGW WenKai` 仅在此处以客观描述字体来源的方式出现。
- 字体仅作为界面文本渲染使用，未单独售卖，也未修改字形设计本身（仅做子集裁剪与家族改名）。
- 上游项目：<https://github.com/lxgw/LxgwWenKai>（霞鹜文楷）、
  <https://github.com/fontworks-fonts/Klee>（Klee One，霞鹜文楷的拉丁与假名来源）、
  <https://github.com/notofonts/symbols>（Noto Sans Symbols 2）。
- 历史说明：本项目曾使用 Noto Sans SC 2.04 子集作为 `assets/ui_font.ttf`（Copyright © 2014-2021 Adobe,
  with Reserved Font Name 'Source'，SIL OFL 1.1），2026-11-12 起整体换为上述星野文楷子集。

### 3.5 界面素材：Wenrexa「UI Minimalism SciFi」

HUD 的面板、按钮、滑动条等界面贴图来自 **Wenrexa** 的素材包
**「UI Minimalism SciFi」**（也被作者称为 *FREE UI KIT Nesia v2*）。

| 项目 | 内容 |
|---|---|
| 作者 | Wenrexa（<https://wenrexa.com/>） |
| 原始发布页 | <https://opengameart.org/content/assets-ui-minimalism-scifi> |
| 许可证 | **CC0 1.0 Universal（公共领域贡献）** |
| 全文 | <https://creativecommons.org/publicdomain/zero/1.0/> |
| 落地路径 | `assets/ui/wenrexa/`（33 个 PNG） |
| 原始包 | `wenrexaassetsui_scifi.zip`，6.5 MB，含 1920×1080 分层 PSD |

作者在发布页上明确写明：**“You can use it in COMMERCIAL and FREE projects”**。

> **关于署名**：CC0 1.0 在法律上**不要求**署名、不要求保留版权声明、也不要求以相同方式共享。
> 本项目仍然在此列出，是出于对作者的尊重与致谢，而非许可义务。
> 本项目的 AGPL-3.0 不覆盖这些贴图——它们仍属公共领域，任何人可自由使用。

本项目对这些贴图所做的处理：

- 未修改原始 PNG 文件本身，仅通过 Godot 的 `StyleBoxTexture`（九宫格）与
  `modulate_color` 做运行时染色，以匹配本项目的青蓝／琥珀配色。
- 未将其单独打包、转售或作为素材库再分发。

### 3.6 界面图标：Pixel UI Sci-Fi Free

HUD 里船体／推进剂等小图标来自 **heyheythere（Spyridon Pikoulas）** 的
**「Pixel UI Sci-Fi Free」**。

| 项目 | 内容 |
|---|---|
| 作者 | heyheythere / Spyridon Pikoulas |
| 原始发布页 | <https://godotengine.org/asset-library/asset/5491> |
| 源码仓库 | <https://github.com/Spyridon-Pikoulas/godot-pixel-ui-scifi-free> |
| 许可证 | **Creative Commons Attribution 4.0 International（CC BY 4.0）** |
| 全文 | <https://creativecommons.org/licenses/by/4.0/> |
| 落地路径 | `assets/ui/icons/`（保存 18 个 PNG；当前 HUD 使用 `health.png`、`fuel.png`） |
| 版本 | 1.0.1 |

**CC BY 4.0 要求署名**，本条即为该署名。本项目对其的使用方式：

- 仅使用 `health.png`（船体）与 `fuel.png`（推进剂）两个图标，通过 `modulate` 染色后显示。
- 未修改图标本身的像素内容。
- 未单独售卖或作为素材库再分发。
- 本项目整体以 AGPL-3.0 发布；该图标仍按 CC BY 4.0 授权，两者不冲突
  （CC BY 4.0 允许被纳入采用其他许可证的更大作品，仅要求保留署名）。

### 3.7 《借一扇晴天》原创内容

项目代码构建的地形、六廊归航站站体、建筑、洞穴、程序化几何、着色器、界面布局、
文本与程序音频为本项目创作；外部模型、UI 贴图、图标、字体及 Lux3D 生成内容按上述各节单独声明，
不归入「全部原创模型」或「无限制自有资产」。类型与体验层面受到包括 **Outer Wilds** 在内的探索类作品启发
（限时轮回、恒星爆发、量化观测、篝火烤棉花糖等玩法母题）；未使用其名称、角色、剧情、地点、界面、模型、文本或音频。
十颗天体名（青岚星 / 赭崖星 / 沧波星 / 悬晶星 / 玄渊星 / 白曜星 / 磐砂星 / 苔垣星 / 硫坞星 / 缄默星）、舱室名与全部标牌均为本项目原创。
归航站的环形/六廊外观在类型视觉上参考了《星际穿越》与 Arknights 的环状/移动舰船空间组织，
但未使用其名称、标志、角色、模型、贴图、房间名或镜头；站体几何、A–F 扇区、舱室名与全部标牌均为原创。

归航站的分段环舱、放射辐条与中央枢纽外观参考了 **《星际穿越》（Interstellar）** 中的环形
空间站/Endurance 的视觉组织方式；**未使用**其名称、标志、角色、剧情、模型、贴图或镜头。
站名「归航站」、环舱与栖息长臂布局、舱室名、中央大厅、舰桥与标牌为本项目创作；
家具的程序化几何由代码构建，使用的 Lux3D 家具另见 3.2.4。

归航站「长走廊串联多舱室」的空间母题参考了 **Arknights（明日方舟）** 中罗德岛等移动舰船的
视觉组织方式；**未使用**其名称、标志、角色、剧情、房间名或任何美术素材。

本项目与 Mobius Digital、Annapurna Interactive、Hypergryph 及其他被提及作品的权利方均无关联、
合作或授权关系。

---

## 4. 免责与纠错

- 本文件按“现状”提供，不构成法律意见；涉及商用、对外发行或专利申请时，请咨询专业法务。
- 如权利人认为本仓库存在未标注或标注不当的第三方内容，请通过仓库 Issue 联系，
  我们将核实后补充署名或移除相关内容。

---

## 5. 本项目自身的许可证

`demo/` 下的构建产物与《借一扇晴天》的原创内容（程序化星球、归航站、地形、着色器、界面、文本、
程序音频）以 **GNU Affero General Public License v3.0** 发布，全文见仓库根目录 `LICENSE`。

与之共存的第三方组件各自保留原许可证，彼此不冲突：

| 组件 | 许可证 | 说明 |
|---|---|---|
| Godot Engine 4.7.1 运行时（`index.wasm` / `index.js`） | MIT | 与 AGPL 兼容，可再分发 |
| 星野文楷子集（`assets/ui_font.ttf`，上游 LXGW WenKai 霞鹜文楷） | SIL OFL 1.1 | 修改版（子集裁剪 + 家族改名为「星野文楷 Starward WenKai」以遵守保留字体名），字体本身仍为 OFL，许可全文随包分发 |
| Noto Sans Symbols 2 子集（`assets/ui_symbols.ttf`） | SIL OFL 1.1 | 同上 |
| Wenrexa「UI Minimalism SciFi」贴图（`assets/ui/wenrexa/`） | CC0 1.0 | 公共领域，无需署名；此处列出仅为致谢 |
| Pixel UI Sci-Fi Free 图标（`assets/ui/icons/`） | CC BY 4.0 | **需署名**，见 3.6 |
| A Windy Day / Black Hole / Space Station / Space Station 3 / SpaceShip Fighter  - Version 1 [MESHY 6] | CC BY 4.0 | **需署名并注明修改**，作者、原作链接及用途见 3.2.6 |
| Aholo Lux3D 生成的星球模型（`assets/models/*-lux3d*`） | 平台条款 | **非本仓库可再许可**，见 3.2.2 |
| Aholo Lux3D 生成的阁楼/世界摆件（`assets/models/props/attic*`） | 平台条款 | 同上，见 3.2.3 |
| Aholo Lux3D 生成的星球道具（`assets/models/props/*`） | 平台条款 | 同上，见 3.2.5 |

> AGPL 第 13 条要求：通过网络向用户提供服务时，必须让使用者能够获得对应源代码。
> 因此公开本网页版时，源码必须一并可获取。
