# UCash 推送到 GitHub
# 用法：在项目根目录执行  powershell -ExecutionPolicy Bypass -File .\push-to-github.ps1
param(
  [string]$Owner = "RexLv2025",
  [string]$Repo  = "ucash"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "== 1. 连通性检查 ==" -ForegroundColor Cyan
try {
  $r = Test-NetConnection github.com -Port 443 -WarningAction SilentlyContinue
  if (-not $r.TcpTestSucceeded) { throw "github.com:443 不可达" }
  Write-Host "github.com:443 可达" -ForegroundColor Green
} catch {
  Write-Host "网络不可达：$_" -ForegroundColor Red
  Write-Host "请确认代理 / 网络后重试" -ForegroundColor Yellow
  exit 1
}

Write-Host "== 2. 仓库状态检查 ==" -ForegroundColor Cyan
$url = "https://github.com/$Owner/$Repo.git"
$exists = $true
try {
  $resp = Invoke-WebRequest -Uri "https://api.github.com/repos/$Owner/$Repo" -UseBasicParsing -TimeoutSec 20
  Write-Host "仓库已存在：$url" -ForegroundColor Green
} catch {
  $exists = $false
  Write-Host "仓库不存在，请先在网页创建空仓库（不要勾选 README / .gitignore / License）" -ForegroundColor Yellow
  Write-Host "创建地址：https://github.com/new?name=$Repo&owner=$Owner" -ForegroundColor Yellow
  Write-Host "创建完成后重新运行本脚本。" -ForegroundColor Yellow
  exit 1
}

Write-Host "== 3. 配置远程 ==" -ForegroundColor Cyan
$current = git remote get-url origin 2>$null
if ($current) {
  git remote set-url origin $url
} else {
  git remote add origin $url
}
Write-Host "origin -> $url" -ForegroundColor Green

Write-Host "== 4. 推送 ==" -ForegroundColor Cyan
git push -u origin main
if ($LASTEXITCODE -ne 0) {
  Write-Host ""
  Write-Host "推送失败。常见原因：" -ForegroundColor Red
  Write-Host "  1) 未登录 GitHub：会弹出浏览器授权窗口，完成登录后重试" -ForegroundColor Yellow
  Write-Host "  2) 账号无该仓库写权限" -ForegroundColor Yellow
  Write-Host "  3) 仓库非空且历史冲突：git pull --rebase origin main 后再推" -ForegroundColor Yellow
  exit 1
}

Write-Host ""
Write-Host "推送成功：" -ForegroundColor Green
Write-Host "  仓库  https://github.com/$Owner/$Repo" -ForegroundColor Green
Write-Host "  Actions https://github.com/$Owner/$Repo/actions" -ForegroundColor Green
Write-Host ""
Write-Host "构建 APK：进入 Actions → 选择 Build UCash APK → Run workflow → 在 Artifacts 下载 ucash-apk" -ForegroundColor Cyan
