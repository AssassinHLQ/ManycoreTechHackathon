# THIRD_PARTY_NOTICES / 第三方组件与内容声明

> 本文件用于履行第三方组件的署名、许可声明义务，并说明仓库内的非原创内容来源。
> 最后更新：2026-11-11

## 0. 版权与许可状态

本项目以 **AGPL-3.0** 发布，见第 5 节。全文见仓库根目录 `LICENSE`。

本文件不授予任何第三方内容的再许可——下文所列内容仍归其各自权利人所有。

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

#### 3.2.2 游戏内的星球模型（`assets/models/*-lux3d`）

游戏里 9 颗可着陆行星的球体模型，同样由 **Aholo Lux3D（群核科技）** 的文生 3D 服务生成，
以 `.glb` 文件形式存放：

| 目录 | 对应天体 | 文件数 | 体积 |
|---|---|---|---|
| `assets/models/baiyao-lux3d` / `-v2` | 白曜星 | 各 1 | 10.7 / 15.5 MB |
| `assets/models/cangbo-lux3d` / `-v2` | 沧波星 | 各 1 | 13.0 / 12.9 MB |
| `assets/models/jianmo-lux3d` / `-v2` | 缄默星 | 各 1 | 11.0 / 15.7 MB |
| `assets/models/liuwu-lux3d` / `-v2` | 硫坞星 | 各 1 | 12.6 / 14.0 MB |
| `assets/models/pansha-lux3d` / `-v2` | 磐砂星 | 各 1 | 10.0 / 14.3 MB |
| `assets/models/taiyuan-lux3d` / `-v2` | 苔垣星 | 各 1 | 11.7 / 17.5 MB |
| `assets/models/xuanjing-lux3d` / `-v2` | 悬晶星 | 各 1 | 15.0 / 21.3 MB |
| `assets/models/xuanyuan-lux3d` / `-v2` | 玄渊星 | 各 1 | 11.4 / 18.2 MB |
| `assets/models/zheya-lux3d` / `-v2` | 赭崖星 | 各 1 | 11.8 / 13.5 MB |

（`-v2` 为同一天体的第二版生成结果，用于对比与替换。）

- **生成方式**：通过 Aholo Lux3D 的文生 3D（text-to-3D）能力产出基础球体几何与贴图，
  再由本项目做缩放、地形噪声叠加与材质调整。
- **权属**：以 Aholo Lux3D 平台服务条款与参赛协议为准。本项目在此致谢该服务。
- **使用限制**：同 3.2.1，若用于参赛之外的产品化或商业发行，需自行向平台确认授权范围。
- **未使用 AI 图像生成模型**：这些是 3D 生成服务的产出，不是图片生成。

其余模型（`black-hole`、`one-dim-star`、`qinglan-planet*`、`ship-fighter`、
`space-station*`）为本项目自行制作或程序化生成，见 3.7。

### 3.3 Godot Engine（`demo/` 网页版）

`demo/` 下的《借一扇晴天》网页版由 **Godot Engine 4.7.1** 导出，
其中 `index.wasm`、`index.js` 与运行时逻辑包含 Godot Engine 代码。

Godot Engine 以 MIT 许可证发布，版权归 Godot Engine contributors 与 Juan Linietsky、Ariel Manzur 所有。
许可全文已随副本附于 [`demo/licenses/godot-MIT.txt`](demo/licenses/godot-MIT.txt)。

项目地址：https://godotengine.org

### 3.4 Noto Sans SC / Noto Sans Symbols 2（字体）

`demo/index.pck` 内嵌了两份**修改版**（子集）字体，用于网页版的中文与符号显示：

| 文件 | 上游字体 | 版权归属 | 许可 | 本项目所做修改 |
|---|---|---|---|---|
| `assets/ui_font.ttf` | Noto Sans SC 2.04 | Copyright © 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source' | SIL OFL 1.1 | ① 由可变字体实例化（variable font → wght=400 静态字重）；② 裁剪为子集，保留 4,370 个码点（项目全部用字 + GB2312 一级 3,755 常用字 + ASCII / 西文标点 / 箭头 / 几何符号） |
| `assets/ui_symbols.ttf` | Noto Sans Symbols 2 2.008 | Copyright 2022 The Noto Project Authors (https://github.com/notofonts/symbols) | SIL OFL 1.1 | 裁剪为子集，仅保留界面用到的 3 个码点（▬ ◈ ✦） |

- 许可全文随副本分发：[`demo/licenses/OFL-NotoSansSC.txt`](demo/licenses/OFL-NotoSansSC.txt)、
  [`demo/licenses/OFL-NotoSansSymbols2.txt`](demo/licenses/OFL-NotoSansSymbols2.txt)。
- SIL OFL 1.1 允许使用、研究、修改、嵌入与随软件分发（含商业发行），但**不得单独售卖字体本身**；
  修改版必须继续以 OFL 发布，且**不得使用原字体声明的保留字体名**。
- 本项目的保留字体名合规说明：Noto Sans SC 声明的保留字体名为 `Source`，本项目修改版沿用
  `Noto Sans SC` 家族名、**未使用 `Source` 字样**，也未使用 Adobe / Google / The Noto Project Authors
  的名称或商标进行宣传、推广或背书；`Noto` 为 Google 的商标，此处仅用于客观描述字体来源。
- 字体仅作为界面文本渲染使用，未单独售卖，也未修改字形设计本身（仅做字重实例化与子集裁剪）。
- 上游项目：<https://github.com/notofonts/noto-cjk>（Noto Sans SC）、
  <https://github.com/notofonts/symbols>（Noto Sans Symbols 2）。

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
| 落地路径 | `assets/ui/icons/`（从中选取 18 个图标中的 2 个：`health.png`、`fuel.png`） |
| 版本 | 1.0.1 |

**CC BY 4.0 要求署名**，本条即为该署名。本项目对其的使用方式：

- 仅使用 `health.png`（船体）与 `fuel.png`（推进剂）两个图标，通过 `modulate` 染色后显示。
- 未修改图标本身的像素内容。
- 未单独售卖或作为素材库再分发。
- 本项目整体以 AGPL-3.0 发布；该图标仍按 CC BY 4.0 授权，两者不冲突
  （CC BY 4.0 允许被纳入采用其他许可证的更大作品，仅要求保留署名）。

### 3.7 《借一扇晴天》原创内容

`demo/` 中除上述引擎与字体外的星球、地形、归航站、建筑、洞穴、模型、材质、着色器、界面、
文本与程序音频均为本项目原创生成。类型与体验层面受到包括 **Outer Wilds** 在内的探索类作品启发
（限时轮回、恒星爆发、量化观测、篝火烤棉花糖等玩法母题）；未使用其名称、角色、剧情、地点、界面、模型、文本或音频。
十颗天体名（青岚星 / 赭崖星 / 沧波星 / 悬晶星 / 玄渊星 / 白曜星 / 磐砂星 / 苔垣星 / 硫坞星 / 缄默星）、舱室名与全部标牌均为本项目原创。
归航站的环形/六廊外观在类型视觉上参考了《星际穿越》与 Arknights 的环状/移动舰船空间组织，
但未使用其名称、标志、角色、模型、贴图、房间名或镜头；站体几何、A–F 扇区、舱室名与全部标牌均为原创。

归航站的分段环舱、放射辐条与中央枢纽外观参考了 **《星际穿越》（Interstellar）** 中的环形
空间站/Endurance 的视觉组织方式；**未使用**其名称、标志、角色、剧情、模型、贴图或镜头。
站名「归航站」、14 段环舱、栖息长臂、12 间舱室名、中央大厅、舰桥、平面布局、家具与标牌
均为本项目原创重建。

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
| Noto Sans SC 子集（`assets/ui_font.ttf`） | SIL OFL 1.1 | 修改版（实例化为 wght=400 + 子集裁剪），字体本身仍为 OFL，许可全文随包分发 |
| Noto Sans Symbols 2 子集（`assets/ui_symbols.ttf`） | SIL OFL 1.1 | 同上 |
| Wenrexa「UI Minimalism SciFi」贴图（`assets/ui/wenrexa/`） | CC0 1.0 | 公共领域，无需署名；此处列出仅为致谢 |
| Pixel UI Sci-Fi Free 图标（`assets/ui/icons/`） | CC BY 4.0 | **需署名**，见 3.6 |
| Aholo Lux3D 生成的星球模型（`assets/models/*-lux3d`） | 平台条款 | **非本仓库可再许可**，见 3.2.2 |

> AGPL 第 13 条要求：通过网络向用户提供服务时，必须让使用者能够获得对应源代码。
> 因此公开本网页版时，源码必须一并可获取。
