# THIRD_PARTY_NOTICES / 第三方组件与内容声明

> 本文件用于履行第三方组件的署名、许可声明义务，并说明仓库内的非原创内容来源。
> 最后更新：2026-10-23

## 0. 版权与许可状态

本仓库**未采用开源许可证（No License）**，仓库内由项目作者创作的内容版权归作者所有，
保留所有权利（All Rights Reserved）。未经书面许可，不得复制、修改、分发或用于商业用途。

GitHub 平台上允许的查看与 fork 行为遵循 GitHub 服务条款，不构成对上述内容的再许可。
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

- 该视频为**手机拍摄的电脑屏幕录屏**，内容为网页端的 3D 空间 / 装修方案浏览界面，
  属于竞品与方案调研记录，**不是 AI 生成视频**。
- 画面中出现的第三方产品名称、界面布局、图标与配色，其权利归各自权利人所有。
- 收录目的仅为技术调研与内部讨论记录，**不构成任何关联、合作、授权或背书**。
- ⚠️ 该片段包含第三方产品界面。若本仓库转为对外商业宣传物料，建议删除该视频或另行取得授权。

---

## 3. 第三方开源组件

### 3.1 Three.js

仓库内三个 HTML 为**单文件交付物**，各自内嵌了 Three.js 运行时代码（含 `GLTFLoader`、
`OrbitControls` 等 examples 模块，与主库同为 MIT 许可）：

| 文件 | 内嵌 Three.js 版本 |
|---|---|
| `前期讨论/parallel-world-home.html` | r186（ES Module 构建） |
| `前期讨论/世界种子-Demo04.html` | r147（UMD 构建） |
| `前期讨论/文物修复师-Demo03.html` | r147（UMD 构建） |

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

> 说明：三个 HTML 是单独分发即可运行的成品，为满足 MIT 条款中“随副本附带版权与许可声明”的要求，
> 建议在每个 HTML 文件头部 `<!DOCTYPE html>` 之前追加一段指向本文件的注释。

### 3.2 3D 模型资产（GLB）

`世界种子-Demo04.html` 与 `文物修复师-Demo03.html` 内的 3D 模型（青铜爵、越王勾践剑、
三星堆面具、史莱姆、小恶魔、宝箱、水晶簇等）由 **Aholo Lux3D（群核科技）** 的文生 3D
服务生成，以 base64 内嵌进 HTML。

- 这些资产的权属与使用范围，受 **Aholo Lux3D 平台服务条款** 及 **本次黑客松参赛协议** 约束，
  不由本仓库的版权声明决定。
- 若用于参赛之外的产品化、批量分发或商业发行，需自行向平台确认授权范围。

---

## 4. 免责与纠错

- 本文件按“现状”提供，不构成法律意见；涉及商用、对外发行或专利申请时，请咨询专业法务。
- 如权利人认为本仓库存在未标注或标注不当的第三方内容，请通过仓库 Issue 联系，
  我们将核实后补充署名或移除相关内容。
