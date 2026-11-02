# 余晖回声 · StarwardWilds

一个第一人称太空探索原型：在微型太阳系里驾船、扫描遗迹、钻地下洞穴，并在 17 分钟一次的恒星爆发轮回中保留知识。

> 原创垂直切片，灵感来自《Outer Wilds》，与原作及其发行商无关联。

## 在线游玩

- GitHub Pages：<https://assassinhlq.github.io/ManycoreTechHackathon/demo/>
- 网页版必须通过 **http(s)** 访问；不要直接双击 `index.html`（浏览器会拦截 wasm / 音频）。

本地预览：

```bash
cd demo
python -m http.server 8060
# 打开 http://127.0.0.1:8060/
```

## 操作

| 场景 | 按键 |
|---|---|
| 徒步 | WASD 移动 · 鼠标观察 · Space 跳跃 · Shift 喷气 · Ctrl 奔跑 |
| 徒步 | F 扫描 · 右键信号镜（滚轮 2.1×–16.9×） · L 头灯 · R 地形脱困 · E 登船 / 烤棉花糖 |
| 飞船 | 鼠标转向 · 滚轮长焦（1×–16×） · W/S 前后 · A/D 横向 · Space/Ctrl（或 C）垂直 · Shift 加力 · X 制动（耗推进剂） |
| 飞船 | Tab 切换目的地 · T 自动航行 / 着陆（按实际 Δv 耗推进剂） · E 着陆 / 离船 |
| 界面 | M 星图 · J 航海日志 · Esc 暂停与设置 |

篝火边按 E 取出棉花糖，火候条走到金黄时再按 E 取下，可补满氧气与燃料。

## 手机 / 触屏

- 手机浏览器会自动显示触屏层，无需额外设置；也可在地址后加 `?touch=1` 强制开启。
- 左侧摇杆移动 / 飞船平移，右侧空白拖动视角；右侧圆钮会根据徒步或飞船自动切换。
- 飞船圆钮：起飞 / 着陆 / 离船 / 上升 / 下降 / 加力 / 制动 / 自动航行；另有星图、日志、菜单。
- 星图右下角提供缩放、设为目标和关闭按钮，空白处拖动平移。
- 首次触摸会请求全屏并尝试锁定横屏，左上角「横屏全屏」按钮可手动重试；竖屏会被遮罩拦住，转到横屏后自动进入。
- Android Chrome 可强制横屏；iOS Safari 不允许网页锁定方向，需要手动旋转。

## 技术

- Godot 4.7.1（Compatibility / WebGL2，单线程导出，无需 COOP/COEP 头）
- `index.wasm` 原始约 38 MB，gzip 后实际传输约 10.2 MB；`index.pck` 约 481 KB
- 已启用 Service Worker：首次加载后 wasm 会缓存到本地，第二次进入不再下载 wasm，只更新约 0.8 MB 的脚本与 pck
- 校园网限速时首次建议用流量/热点，或部署到 Cloudflare Pages / 国内对象存储
- 星球、地形、建筑、洞穴、量子规则、程序音频均为项目内程序化生成
- 网页版由浏览器控制分辨率与垂直同步；音频需首次点击后播放
- 设置菜单支持画质预设、分辨率、帧率上限（30–240）、MSAA、阴影、视距、草地、主音量与鼠标灵敏度

## 第三方组件与许可

- **Godot Engine 4.7.1**：MIT，许可全文见 [`licenses/godot-MIT.txt`](licenses/godot-MIT.txt)
- **Noto Sans SC / Noto Sans Symbols 2**（按项目用字子集内嵌）：SIL Open Font License 1.1，
  许可全文见 [`licenses/noto-OFL.txt`](licenses/noto-OFL.txt)
- 其余模型、材质、着色器、文本与程序音频由本项目原创生成

完整声明见仓库根目录的 [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)。
