# -*- coding: utf-8 -*-
"""更新 THIRD_PARTY_NOTICES.md：3.2.2 改为准确的星球清单，并新增阁楼/站内/道具署名。"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

P = "THIRD_PARTY_NOTICES.md"
s = io.open(P, encoding="utf-8").read()

START = "#### 3.2.2 "
END = "其余模型（"

i = s.find(START)
j = s.find(END, i)
if i < 0 or j < 0:
    print("anchor not found: i=%d j=%d" % (i, j))
    raise SystemExit(1)

NEW = """#### 3.2.2 游戏内的星球模型（`assets/models/*-lux3d*`）

游戏里 18 颗可着陆行星的球体模型，由 **Aholo Lux3D（群核科技）** 的文生 3D 服务生成，
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

"""

s = s[:i] + NEW + s[j:]
io.open(P, "w", encoding="utf-8", newline="").write(s)
print("已更新：3.2.2 重写 + 新增 3.2.3 / 3.2.4 / 3.2.5")
print("文件行数:", s.count("\n") + 1)
