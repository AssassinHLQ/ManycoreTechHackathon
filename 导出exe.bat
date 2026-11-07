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
if not exist "build\windows" mkdir "build\windows"
rem 工作区目录可能继承低完整性标签；先抬到 Medium，避免导出的 exe 被沙箱限制。
icacls "%~dp0build\windows" /setintegritylevel "(OI)(CI)Medium" >nul 2>&1
echo 正在导出 Windows 版……
"%GODOT%" --headless --path . --export-release "Windows Desktop" "build\windows\game.exe"
if errorlevel 1 (
  echo.
  echo 导出失败：请确认已安装 4.7.1.stable 的 Windows 导出模板。
  pause
  exit /b 1
)
icacls "%~dp0build\windows\game.exe" /setintegritylevel Medium >nul 2>&1
echo.
echo 导出完成：%~dp0build\windows\game.exe
echo 如果 Windows 弹出 SmartScreen，请选择「更多信息 -> 仍要运行」。
pause
