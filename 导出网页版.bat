@echo off
setlocal
chcp 65001 >nul
set "GODOT=D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo [借一扇晴天] 未找到标准版 Godot 4.7.1：%GODOT%
  echo 请修改本文件里的 GODOT 路径。
  pause
  exit /b 1
)
cd /d "%~dp0"
if not exist "build\web" mkdir "build\web"
echo 正在导出 Web 版……
"%GODOT%" --headless --path . --export-release "Web" "build\web\index.html"
if errorlevel 1 (
  echo.
  echo 导出失败：请确认已安装 4.7.1.stable Web 导出模板。
  pause
  exit /b 1
)
if exist "%~dp0web_mobile\mobile_immersive.js" (
  copy /Y "%~dp0web_mobile\mobile_immersive.js" "%~dp0build\web\mobile_immersive.js" >nul
  copy /Y "%~dp0web_mobile\sw.js" "%~dp0build\web\sw.js" >nul
  python "%~dp0web_mobile\inject_immersive.py" "%~dp0build\web\index.html"
  if errorlevel 1 (
    echo [提示] 未找到 Python，未注入手机全屏入口；游戏本体仍可运行。
  )
)
echo.
echo 导出完成：%~dp0build\web
echo 双击「启动网页版.bat」可本地预览。
pause
