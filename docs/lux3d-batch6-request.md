# Lux3D 第六批生成委托（66 个资产 / 858 credits）

> 委托人：星球线 agent（lead）
> 执行方：持有 2000 credits 的协作 agent
> 预算：66 × 13 = **858 credits**（极速版 G1-Turbo 单价 13），2000 额度只用不到一半，
> 留 1142 给试错、返工与后续批次。

---

## 一、为什么是这 66 个

当前仓库已有 **114 个** AI 资产，覆盖度如下（**请不要重复生成这些**）：

| 已有类别 | 数量 | 说明 |
| --- | --- | --- |
| `lm-*` 签名地标 | 20 | 每颗星球 1 个，一眼能认出是哪颗星 |
| 通用件 + 低模变体 | 28 | 树/岩/晶簇/喷口/货舱/菇/冰棱…含 `-lo` 低模 |
| 大地貌件 `lf-*` | 15 | 峡谷壁/天然拱/方山/山脊/环形山缘/冰川壁… |
| 互动机器 | 18 | 电池/控制台/医疗站/破碎机/信标/排热塔… |
| 装饰小件 | 25 | 石堆/苔石/骨骸/玻璃碎片/轨道段/珊瑚堆… |
| 基础建筑件 | 6 | 遗迹拱门/方尖碑/穹顶/信号塔/石桥/浮岩 |

**还没覆盖的五个空缺**，就是这批要补的：

1. **星球上一只活物都没有** → A 外星生物
2. **洞穴里是空的**（`underground.gd` 只能复用地面摆件）→ B 洞穴陈设
3. **每颗星球只有一个地标**，走远一点就只剩通用件 → C 第二地标
4. **植被只有 4 种形态**（树/蘑菇/棘丛/枯树）→ D 植被补充
5. **建筑是整块的，无法拼接** → E 模块化建筑件

---

## 二、资产清单

机器可读的规格在 **`tools/batch6_spec.py`**（含每条完整英文 prompt）。
运行 `python tools/batch6_spec.py` 会直接打印可粘进 `gen_props.py` 的条目。

### A · 外星生物（12 个 / 156 credits）

| # | 资产 id | 中文名 | 面数 |
| --- | --- | --- | --- |
| 1 | `creature-grazer` | 食草兽 | 26000 |
| 2 | `creature-glider` | 滑翔生物 | 24000 |
| 3 | `creature-beetle-swarm` | 甲虫群 | 24000 |
| 4 | `creature-tall-walker` | 高足行者 | 28000 |
| 5 | `creature-burrower` | 掘地兽 | 26000 |
| 6 | `creature-crystal-crawler` | 晶壳爬虫 | 26000 |
| 7 | `creature-glow-jelly` | 浮空光母 | 24000 |
| 8 | `creature-pack-hound` | 群猎兽 | 26000 |
| 9 | `creature-ruin-guardian` | 遗迹守卫 | 30000 |
| 10 | `creature-spore-drifter` | 孢子漂游体 | 22000 |
| 11 | `creature-ice-herd` | 冰原群兽 | 26000 |
| 12 | `creature-lava-mite` | 熔岩螨 | 22000 |

### B · 洞穴陈设（12 个 / 156 credits）

| # | 资产 id | 中文名 | 面数 |
| --- | --- | --- | --- |
| 13 | `cave-stalagmite` | 石笋 | 22000 |
| 14 | `cave-stalactite` | 钟乳石 | 22000 |
| 15 | `cave-crystal-cluster` | 地下晶簇 | 24000 |
| 16 | `cave-mine-cart` | 矿车 | 26000 |
| 17 | `cave-elevator` | 升降平台 | 28000 |
| 18 | `cave-lantern` | 矿灯 | 20000 |
| 19 | `cave-altar` | 地下祭坛 | 26000 |
| 20 | `cave-pillar` | 溶洞石柱 | 24000 |
| 21 | `cave-lake-stone` | 地下湖石 | 22000 |
| 22 | `cave-bridge` | 溶洞石桥 | 26000 |
| 23 | `cave-fossil-wall` | 化石壁 | 24000 |
| 24 | `cave-rail` | 矿道轨道 | 22000 |

### C · 每星球第二地标（20 个 / 260 credits）

| # | 资产 id | 中文名 | 面数 |
| --- | --- | --- | --- |
| 25 | `lm2-qinglan` | 青岚 · 石砌哨塔 | 26000 |
| 26 | `lm2-zheya` | 赭崖 · 盐蚀测量桅 | 26000 |
| 27 | `lm2-cangbo` | 沧波 · 冰芯钻机 | 26000 |
| 28 | `lm2-xuanjing` | 悬晶 · 残骸祭环 | 26000 |
| 29 | `lm2-xuanyuan` | 玄渊 · 黑石甬道 | 26000 |
| 30 | `lm2-baiyao` | 白曜 · 冰晶拱门 | 24000 |
| 31 | `lm2-pansha` | 磐砂 · 半埋商队车架 | 24000 |
| 32 | `lm2-taiyuan` | 苔垣 · 阶式园圃 | 24000 |
| 33 | `lm2-liuwu` | 硫坞 · 倒塌龙门吊 | 26000 |
| 34 | `lm2-jianmo` | 缄默 · 哑钟塔 | 24000 |
| 35 | `lm2-jiangxiao` | 绛霄 · 竖井矿口 | 26000 |
| 36 | `lm2-cangwu` | 苍梧 · 空心巨桩 | 26000 |
| 37 | `lm2-jinwu` | 金乌 · 盐壳枯井 | 24000 |
| 38 | `lm2-yuheng` | 玉衡 · 石英切场 | 24000 |
| 39 | `lm2-sue` | 素娥 · 环形观测墙 | 24000 |
| 40 | `lm2-danxia` | 丹霞 · 条纹岩桥 | 26000 |
| 41 | `lm2-biluo` | 碧落 · 潮汐祭台 | 24000 |
| 42 | `lm2-youdu` | 幽都 · 冰洞洞口 | 26000 |
| 43 | `lm2-yaoguang` | 瑶光 · 镜面巨碑 | 26000 |
| 44 | `lm2-xuanpu` | 玄圃 · 苔阶祭坛 | 24000 |

### D · 植被补充（12 个 / 156 credits）

| # | 资产 id | 中文名 | 面数 |
| --- | --- | --- | --- |
| 45 | `fern-cluster` | 蕨丛 | 18000 |
| 46 | `vine-drape` | 垂藤帷幕 | 18000 |
| 47 | `moss-mat` | 苔垫 | 16000 |
| 48 | `spore-pod` | 孢子荚 | 18000 |
| 49 | `giant-fungus` | 巨菌 | 22000 |
| 50 | `grass-plume` | 羽草原 | 16000 |
| 51 | `reed-stand` | 芦苇丛 | 18000 |
| 52 | `bulb-plant` | 球茎植物 | 18000 |
| 53 | `thorn-vine` | 刺藤 | 18000 |
| 54 | `canopy-shrub` | 伞状灌木 | 20000 |
| 55 | `lichen-rock` | 地衣石 | 16000 |
| 56 | `seed-head` | 干种穗 | 16000 |

### E · 模块化建筑件（10 个 / 130 credits）

| # | 资产 id | 中文名 | 面数 |
| --- | --- | --- | --- |
| 57 | `mod-doorframe` | 门框 | 22000 |
| 58 | `mod-railing` | 栏杆段 | 20000 |
| 59 | `mod-stairs` | 楼梯段 | 22000 |
| 60 | `mod-tower-top` | 塔顶 | 22000 |
| 61 | `mod-platform` | 平台板 | 20000 |
| 62 | `mod-archway` | 拱门 | 22000 |
| 63 | `mod-window-panel` | 采光窗板 | 18000 |
| 64 | `mod-ladder` | 梯子 | 18000 |
| 65 | `mod-pipe-run` | 管线组 | 20000 |
| 66 | `mod-signage` | 标识牌 | 18000 |

---

## 三、生成命令

约定与现有资产完全一致（这样接进代码时不用改任何东西）：

- **版本**：必须 `G1-Turbo`（13 credits/个；`G1` 是 20 credits/个，贵 54% 且没必要）
- **输出**：`assets/models/props/<id>/model.glb`
- **风格**：`photorealistic`
- **PBR**：开 `--enable-pbr`
- **尺寸**：加 `--no-ai-predict-size`（尺寸由游戏侧 `prop_scale` 控制）

单条命令：

```powershell
python core/runtime/lux3d_client.py --region cn text "<prompt>" `
  "assets/models/props/<id>/model" `
  --style photorealistic --version G1-Turbo --face-count <面数> `
  --format glb --enable-pbr --no-ai-predict-size
```

> ⚠ `--region` 是**全局参数**，必须放在子命令 `text` **之前**。

批量：把 `tools/batch6_spec.py` 的条目并入 `tools/gen_props.py` 的 `PROPS`，然后

```powershell
python tools/gen_props.py                       # 生成全部缺的
python tools/gen_props.py --only id1,id2,id3    # 只生成指定几个
python tools/gen_props.py --list                # 查看哪些缺
```

`gen_props.py` 已内置：跳过已存在的、失败重试、写完自动切到 `assets/models/props/<id>/model.glb`。

---

## 四、生成后处理（**这一步最容易翻车，务必照做**）

```powershell
# 1) 贴图降到 1024²（省显存：2048² RGBA 每张约 16MB）
python tools/downscale_prop_textures.py

# 2) 🔴 必须删掉 model.glb 的导入缓存再重新导入
Get-ChildItem .godot\imported -Filter 'model.glb-*' | Remove-Item
& 'D:\GAME\godot\Godot_v4.7.1-stable_win64.exe' --headless --path . --import

# 3) 更新资产清单（实测面数/顶点/体积）
python tools/manifest_props.py
```

### 为什么第 2 步不能省

就地重写 PNG 会让贴图**重新导入并换新 UID**，而 `model.glb` 的缓存场景
（`.godot/imported/model.glb-*.scn`）里存的是**旧 UID**，且**不会**自动重建。症状：

```
invalid UID: 'uid://xxxx' - using text path instead
Failed loading resource: res://assets/models/xxx/model.glb
```

模型全部加载失败、冒烟测试连带翻红。**本项目已踩过一次**（2026-11-12）。
修法就是上面第 2 步。验证脚本：`tests/probe_load_fail.gd`。

---

## 五、交付与验收

**交付方式**：把 `assets/models/props/<id>/` 整个目录放进本仓库同路径即可
（目录在 `.gitignore` 里，不入库，只留在工作区）。

**验收标准**（我方 agent 会跑）：

| 检查 | 命令 | 通过标准 |
| --- | --- | --- |
| 模型能加载 | `tests/probe_load_fail.gd` | 全部 `loaded=true` |
| 星球构建正常 | `tests/smoke_test.gd` | 0 failure |
| 行走碰撞正常 | `tests/walk_test.gd` | 0 failure |
| 资源清单完整 | `LICENSE_MANIFEST.json` | 条目数 = 148 + 66 = 214 |

**接到游戏里**由我方完成（代码侧接线：`PROP_MODELS` / 铺量表 / 交互表 / 地貌表），
不需要执行方改任何 `.gd` 文件。

---

## 六、优先级（额度不够时按此顺序删减）

| 优先级 | 类别 | 理由 |
| --- | --- | --- |
| 1 | **A 外星生物** | 星球现在完全没有活物，观感差距最大 |
| 2 | **C 第二地标** | 走远就只剩通用件，重复感最明显 |
| 3 | **D 植被补充** | 植被只有 4 种形态，一眼就能看出重复 |
| 4 | **B 洞穴陈设** | 洞穴是主要玩法点，但只有愿意下洞的玩家会看到 |
| 5 | **E 模块化建筑件** | 收益最长期（能拼出更多建筑），但短期不影响观感 |

若只做 1+2：32 个 = **416 credits**。
若做 1+2+3：44 个 = **572 credits**。
