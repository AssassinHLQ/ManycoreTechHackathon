# 四平台导出验证记录

验证日期：2026-11-18。引擎：Godot 4.7.1 标准版，`4.7.1.stable.official.a13da4feb`。构建主机：Windows x86_64。

四个平台均已实际导出，自动验证流程退出码为 0，`build/platform-validation.json` 中 `success=true`。Android 和 Linux 尚未进行目标设备上的运行测试，因此这里的通过范围限定为下表。

## 产物与验证范围

大小以 MiB（1,048,576 字节）计。分发包均保存在项目的 `build/` 下，不入库。

| 平台 | 产物 | 大小 | 本机已完成的验证 |
| --- | --- | ---: | --- |
| Windows x86_64 | `build/SunnyWindow-Windows.zip` | 503.0 MiB | ZIP CRC；内嵌 PCK 的 81 项检查；实际 `game.exe` 无界面启动，加载全部 20 颗星球后正常退出 |
| Linux x86_64 | `build/SunnyWindow-Linux-x86_64.tar.gz` | 489.6 MiB | ELF x86_64 标识；PCK 的 81 项检查；完整读取压缩包；可执行文件权限为 0755 |
| Web | `build/SunnyWindow-Web.zip` | 552.8 MiB | ZIP CRC；PCK 的 81 项检查；缓存测试；后台 Edge 中实际 WebGL2 启动；桌面与手机横屏尺寸切换 |
| Android ARM64 | `build/android/game-debug.apk` | 562.0 MiB | APK ZIP CRC；ARM64 引擎库；移动压缩纹理与预计算场景；授权文件逐字节比对；v2/v3 签名；包名、版本与 SDK 信息 |

Windows 的直接启动文件为 `build/windows/game.exe`。Linux 需将同目录的 `game.x86_64` 与 `game.pck` 一起分发。Web 需解压后部署到 HTTP(S) 服务，入口为 `index.html`。

## 测试结果

- 冒烟测试：163 项通过，0 失败。
- 字体检查：全部 1441 个上屏字符被内嵌字体覆盖，0 失败。
- 触屏测试：16 项通过，0 失败。
- 预计算测试：150 项通过，0 失败。此前已完成 20 颗星球和归航站的静态场景烘焙。
- Windows / Linux / Web 资源包：各 81 项通过，0 失败。包括 20 颗星球、地形 LOD、归航站快照、四个阁楼场景入口、授权署名和抽样 GPU 压缩纹理；开发目录未被打入资源包。
- Web 缓存：启动流式加载、后台缓存与 WASM 复用测试通过。
- Web 浏览器：全部资源请求返回 HTTP 200，无捕获到的 Godot 错误、JavaScript 异常或 WebGL 上下文丢失。本地启动并验证约 37.3 秒，不代表互联网下载或移动设备启动速度。
- Web 截图：桌面 1280×720、手机横屏视口 844×390（DPR 2，画布 1688×780），已检查中文菜单、星球画面和非空像素。

## 本轮修复

新增 Linux 与 Android 导出预设，并补装匹配版本的官方导出模板。Android 首次导出暴露出缺少移动纹理格式，现已启用项目的 ETC2/ASTC 导入；Web 同时启用桌面和移动纹理导出，重新导出后通过检查。双格式会增加 Web 包体，当前 `index.pck` 为 698,832,860 字节。

四个平台均包含授权清单、模型授权台账和许可全文；分发目录同时附带可直接阅读的副本。新增脚本 `tools/export_platforms.py` 可重复执行导出和验证，测试子进程使用无界面模式。

## 待补验与已知限制

- Android：没有连接真机，未验证安装、触控游玩、显存和帧率。当前 APK 使用调试签名，包名为 `org.starwardwilds.sunnywindow`，版本 `0.1.0` / code 1，minSDK 24、targetSDK 36；正式发布需要另配发布密钥。
- Linux：本机没有 Linux / WSL 运行环境。PCK 由 Windows Godot 读取验证，尚未验证 Linux 原生启动、驱动、输入与音频。
- Windows：程序启动使用 `--headless` 和 Dummy 音频驱动，未覆盖图形驱动、实际声音与持续游玩。资源包测试退出时报告两个音频对象未释放，详细日志指向 `AudioStreamPlaybackWAV` / `AudioStreamWAV`；81 项检查与退出码均通过，该退出清理警告仍待处理。
- Web：只验证了本机 Edge 的桌面启动与手机尺寸模拟，没有验证 Android / iOS 浏览器真机、完整游玩和长时间性能。

## 复现与证据

完整执行（需要对应导出模板、Android SDK/JDK、Node.js 22+ 和 Chromium 浏览器）：

```powershell
python tools/export_platforms.py android web windows linux --archives
```

本次已提前完成烘焙，最终统一验证使用了 `--skip-bake`，源码测试仍全部重跑。不要在修改场景或生成逻辑后沿用旧烘焙产物。

机器报告：`build/platform-validation.json`，包含构建开始时的基础提交、78 个源码/配置/授权文件 SHA256、产物 SHA256、各阶段日志与退出码。导出后已比对这 78 个文件，均未发生变化；基础提交字段并不代表这些未提交配置已经包含在该提交中。

日志：`_tools/_tmp/platform_*.log`；烘焙日志：`_tools/_tmp/export_20261118_bake.log`。浏览器详细结果：`_tools/_tmp/web_export_result.json`，截图：`_tools/_tmp/web_export_desktop.png`、`_tools/_tmp/web_export_mobile.png`。Windows 音频退出警告的诊断日志：`_tools/_tmp/platform_package_windows_verbose.log`。

| 产物 | SHA256 |
| --- | --- |
| Android APK | `a2f32b68d15d0ba7f382f198d53f746675d3039d1b96e5a1e11f21c67a536902` |
| Web ZIP | `8de431b9887021305b0ce5bd7e36922dddd3c9e3ffc4a7f3dc4e54514d4a6e7f` |
| Windows ZIP | `87bf49322e70bceeccaabb1a91eca0fbaccbe06cab4f12da88b57f38f4b3fb16` |
| Linux tar.gz | `ed72a738c203a7e48f69cb75857b8279931e8f9e8c1cfd77c04c60fa441f0166` |

相关官方文档：[Web 导出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)、[Android 导出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html)。
