# tools/push_to_github.ps1
# 一键把「轮回回廊」推到 GitHub（默认私有仓库）。
#
# 用法：
#   1) 先登录（只需一次）：
#        gh auth login
#      选择 GitHub.com → HTTPS → Login with a web browser
#      国内网络若卡住，先在当前终端设代理：
#        $env:HTTPS_PROXY="http://127.0.0.1:7890"
#        $env:HTTP_PROXY="http://127.0.0.1:7890"
#
#   2) 然后运行：
#        pwsh -File tools/push_to_github.ps1
#      或指定仓库名：
#        pwsh -File tools/push_to_github.ps1 -RepoName my-game
#
# 脚本会先做敏感文件检查，**发现可疑文件就中止**，不会把密钥推上去。

param(
    [string]$RepoName = "infinite-loop",
    [ValidateSet("private", "public")]
    [string]$Visibility = "private"
)

$ErrorActionPreference = "Stop"
$gh = "C:\Program Files\GitHub CLI\gh.exe"
if (-not (Test-Path $gh)) { $gh = "gh" }

Write-Host ""
Write-Host "=== 1/5  检查 gh 登录状态 ===" -ForegroundColor Cyan
& $gh auth status 2>&1 | ForEach-Object { "  $_" }
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "尚未登录。请先执行：" -ForegroundColor Yellow
    Write-Host "  gh auth login" -ForegroundColor White
    Write-Host "（选择 GitHub.com → HTTPS → Login with a web browser）" -ForegroundColor DarkGray
    exit 1
}

Write-Host ""
Write-Host "=== 2/5  敏感文件检查 ===" -ForegroundColor Cyan
$suspects = git ls-files | Select-String -Pattern "\.env|secret|credential|\.pem$|\.p12$|api[_-]?key|token|cookie|chrome-profile"
if ($suspects) {
    Write-Host "⚠ 发现可疑文件，已中止推送：" -ForegroundColor Red
    $suspects | ForEach-Object { "    $_" }
    Write-Host "请先确认这些文件不含密钥，或从版本控制移除。" -ForegroundColor Yellow
    exit 1
}
Write-Host "  ✓ 已跟踪文件中无敏感文件" -ForegroundColor Green

# 内容级扫描：常见密钥格式
$hits = git grep -n -I -E "sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|AIza[0-9A-Za-z_-]{30,}" HEAD 2>$null
if ($hits) {
    Write-Host "⚠ 文件内容里疑似有密钥，已中止：" -ForegroundColor Red
    $hits | Select-Object -First 5 | ForEach-Object { "    $_" }
    exit 1
}
Write-Host "  ✓ 内容扫描无密钥格式" -ForegroundColor Green

Write-Host ""
Write-Host "=== 3/5  确认分支与提交 ===" -ForegroundColor Cyan
"  当前分支  : " + (git branch --show-current)
"  提交数    : " + (git rev-list --count HEAD)
"  跟踪文件  : " + (git ls-files | Measure-Object).Count
if ((git status --porcelain | Measure-Object).Count -gt 0) {
    Write-Host "  注意：还有未提交的改动，它们不会被推送。" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== 4/5  创建远端仓库并推送 ===" -ForegroundColor Cyan
$existing = & $gh repo view $RepoName --json name 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  仓库已存在，改为推送：" -ForegroundColor DarkGray
    git remote remove origin 2>$null
    & $gh repo set-default $RepoName 2>$null | Out-Null
    $owner = (& $gh api user --jq .login 2>$null)
    git remote add origin "https://github.com/$owner/$RepoName.git"
    git push -u origin main
} else {
    & $gh repo create $RepoName --$Visibility --source=. --remote=origin --push
}

Write-Host ""
Write-Host "=== 5/5  完成 ===" -ForegroundColor Green
git remote -v
Write-Host ""
Write-Host "仓库地址：" -ForegroundColor Cyan
& $gh repo view $RepoName --json url --jq .url 2>$null
