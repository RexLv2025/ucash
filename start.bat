@echo off
chcp 65001 >nul
title UCash 启动器
echo ============================================
echo   UCash 线上小额现金贷 - 一键启动
echo ============================================
echo.

if not exist "%~dp0apps\server\node_modules" (
  echo [1/3] 首次运行，安装服务端依赖...
  pushd "%~dp0apps\server" && call npm install --no-audit --no-fund && popd
)
if not exist "%~dp0apps\admin\node_modules" (
  echo [2/3] 安装后台依赖...
  pushd "%~dp0apps\admin" && call npm install --no-audit --no-fund && popd
)

echo [3/3] 启动服务...
start "UCash Server :4000" cmd /k "cd /d %~dp0apps\server && npm run dev"
timeout /t 4 >nul
start "UCash Admin :5173" cmd /k "cd /d %~dp0apps\admin && npm run dev"
timeout /t 3 >nul
start "" http://localhost:4000/admin

echo.
echo 服务端: http://localhost:4000   （后台: http://localhost:4000/admin）
echo 后台开发: http://localhost:5173
echo 演示账号: 13800138000 / 验证码 123456
echo.
pause
