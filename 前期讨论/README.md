# MAH 2026 参赛 Demo（03 / 04）

群核科技 Aholo 全球 3D AI 黑客松 · 游戏方向两个可玩原型。

## 打开的姿势

`dist/` 下两个 HTML 是**单文件成品**（Three.js、游戏逻辑、Lux3D 生成的 GLB 资产全部 base64 内嵌）：

- **文物修复师-Demo03.html**（约 2.5 MB）—— 双击即可离线游玩，建议 Chrome / Edge
- **世界种子-Demo04.html**（约 6.2 MB）—— 双击即可离线游玩，建议 Chrome / Edge

无需本地服务器，无需联网。

## Demo 03 · 文物修复师（馆藏三部曲）

- 玩法：勘探出土（点击残片）→ 铭文拼装（残片匹配卡槽）→ **重光仪式**（残片鎏金 + 环绕镜头的拼接动画）→ Lux3D 精修 → 文物重光（360° 检视 + 评级 + **文物科普卡**）
- 三件文物依次解锁：**青铜兽面纹爵 → 越王勾践剑 → 三星堆纵目面具**，每件重光时附博物馆级小百科
- 核心资产：**Aholo Lux3D G1 文生3D**（爵 60,000 面 / 剑 50,000 面 / 面具 60,000 面，PBR 网格）
- 对应评分点：Lux3D 是玩法核心（没有生成就没有"文物重光"），可视化展示 3D AI Harness 工作流（Turbo 草稿 → G1 精修）

## Demo 04 · 世界种子（第一人称 Roguelike）

- 玩法：输入一句话"世界种子" → SpatialGen 叙事编译地牢 → Lux3D 资产装配 → **第一人称**走迷宫打怪 → 找传送门 → 无限层数爬塔
- 战斗系统：**手持武器挥砍**（我的世界式左键斩击）+ **灵力弹**远程法术（F / 右键，2.5s 冷却）+ 宝箱增益（治疗/攻击强化/疾行）
- 视角与导航：指针锁鼠标视角（预览环境自动降级为拖拽视角）、右上角**实时小地图**（怪物/宝箱/传送门/玩家朝向）、传送门 HUD 八向指南针
- 核心资产：**Aholo Lux3D G1**（史莱姆、小恶魔，各 30,000 面 PBR）+ **G1-Turbo**（宝箱、水晶簇）
- 特色：同一种子 = 同一地牢（可复现）；主题词识别（熔岩/冰晶/翡翠/深渊四套配色）；Harness 日志实时展示"Agent 调度 + Lux3D 生成"管线
- 操作：WASD 移动 · 左键挥砍 · F/右键灵弹 · ESC 主菜单

## 资产清单（Lux3D OpenAPI 实际生成）

| 文件 (assets/) | 原始体积 | 优化后 | 生成方式 |
|---|---|---|---|
| jue.glb 青铜爵 | 8.4 MB | 1.38 MB | text-to-3d · G1 · 60,000 面 |
| jian.glb 越王勾践剑 | 6.2 MB | 0.21 MB | text-to-3d · G1 · 50,000 面 |
| mian.glb 三星堆面具 | - | - | text-to-3d · G1 · 60,000 面 |
| slime.glb 史莱姆 | 5.8 MB | 0.66 MB | text-to-3d · G1 · 30,000 面 |
| imp.glb 小恶魔 | 7.0 MB | 1.45 MB | text-to-3d · G1 · 30,000 面 |
| chest.glb 宝箱 | 11.3 MB | 0.88 MB | text-to-3d · G1-Turbo · 20,000 面 |
| crystal.glb 水晶簇 | 13.9 MB | 1.33 MB | text-to-3d · G1-Turbo · 20,000 面 |

优化管线：gltf-transform（webp 纹理 1024 + 网格简化），Three.js r147 渲染（支持 EXT_texture_webp）。

## 目录结构

```
MAH-demos/
├── src/            # 页面骨架(shell03/04.html) + 游戏逻辑(game03/04.js)
├── lib/            # Three.js r147 + GLTFLoader + OrbitControls
├── assets/         # Lux3D 原始 GLB 与 *_opt.glb 优化版
├── dist/           # 最终单文件成品(交付物)
└── build.py        # 打包脚本(python build.py)
```

## 二次开发

改 `src/game03.js` / `game04.js` 后运行：

```
python build.py
```

即可重新打包出 dist 成品。
