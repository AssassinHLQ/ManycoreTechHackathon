@echo off
setlocal
set "GODOT=D:\SOFTWARE\Godot-4.7.1-dotnet\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe"
if not exist "%GODOT%" (
  echo [借一扇晴天] 未找到 Godot 4.7.1，请编辑本文件中的 GODOT 路径。
  pause
  exit /b 1
)
start "借一扇晴天" "%GODOT%" --path "%~dp0" %*
endlocal
