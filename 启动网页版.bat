@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
if not exist "build\web\index.html" (
  echo 还没有网页版，请先运行「导出网页版.bat」。
  pause
  exit /b 1
)
start "借一扇晴天 网页版" cmd /k "cd /d %~dp0build\web && python -m http.server 8060"
timeout /t 2 >nul
start "" "http://127.0.0.1:8060/index.html"
echo 本地服务已启动：http://127.0.0.1:8060/index.html
echo 关闭弹出的命令行窗口即可停止服务。
