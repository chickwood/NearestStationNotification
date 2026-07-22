$ErrorActionPreference = "Stop" # 遇到错误立即停止

function Invoke-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) {
        throw "git $($args -join ' ') 执行失败。"
    }
}

function Test-GitRef {
    & git @args *> $null
    return ($LASTEXITCODE -eq 0)
}

# 1. 检查工作区，避免自动切换分支时覆盖本地修改
$gitStatus = git status --porcelain
if ($gitStatus) {
    Write-Error "错误: 工作区不干净，请先 clean 或 commit。"
    exit 1
}

# 2. 自动切回 main 并同步远程 main
Write-Host "1. 正在切回 main 分支并同步远程代码..." -ForegroundColor Green
Invoke-Git checkout main
Invoke-Git fetch origin main
Invoke-Git merge --ff-only origin/main
if ((git rev-parse HEAD).Trim() -ne (git rev-parse origin/main).Trim()) {
    Write-Error "错误: 本地 main 未能同步到 origin/main。"
    exit 1
}

# 3. 解析并校验 main 中的 version 字段
$versionLine = Select-String -Path "pubspec.yaml" -Pattern "^version:" | Select-Object -First 1
if (-not $versionLine) {
    Write-Error "错误: 未在 pubspec.yaml 中找到 version 字段"
    exit 1
}
$versionStr = ($versionLine.Line -split ":", 2)[1].Trim()
if ($versionStr -notmatch '^[0-9]+\.[0-9]+\.[0-9]+-(?<versionDate>[0-9]{8})(-[0-9]+)?\+(?<buildDate>[0-9]{8})(?<buildNumber>[0-9]{2})$') {
    Write-Error "错误: version 格式无效: $versionStr"
    Write-Error "格式应为: X.Y.Z-YYYYMMDD[-N]+YYYYMMDDNN"
    exit 1
}
if ($Matches.versionDate -ne $Matches.buildDate) {
    Write-Error "错误: version 中的两个日期必须一致: $versionStr"
    exit 1
}

# 4. 生成 release 分支名和 Tag 名
$tagName = ($versionStr -split "\+")[0]
$releaseBranch = "release/v$tagName"
$targetTag = "v$tagName"

# 5. 确认 release 分支已经通过 PR 合并到 main
if (-not (Test-GitRef ls-remote --exit-code --heads origin $releaseBranch)) {
    Write-Error "错误: 远程 release 分支不存在: $releaseBranch"
    exit 1
}
Invoke-Git fetch origin "${releaseBranch}:refs/remotes/origin/${releaseBranch}"
if (-not (git merge-base --is-ancestor "origin/$releaseBranch" HEAD)) {
    Write-Error "错误: PR 尚未合并到 main，不能创建 Tag。"
    exit 1
}

# 6. 检查 Tag 是否已存在
if ((Test-GitRef show-ref --verify --quiet "refs/tags/$targetTag") -or
    (Test-GitRef ls-remote --exit-code --tags origin "refs/tags/$targetTag")) {
    Write-Error "错误: Tag 已存在: $targetTag"
    exit 1
}

# 7. 用户确认并推送 Tag
Write-Host "========== 发布执行 ==========" -ForegroundColor Cyan
Write-Host "将基于当前 main 创建并推送 Tag: $targetTag"
Write-Host "==============================" -ForegroundColor Cyan
$confirmation = Read-Host "确认继续？(Y/N)"
if ($confirmation -notmatch "^[yY]$") {
    Write-Host "发布执行已取消。" -ForegroundColor Yellow
    exit 0
}

Write-Host "正在创建并推送 Tag..." -ForegroundColor Green
Invoke-Git tag $targetTag
Invoke-Git push origin $targetTag
Write-Host "发布 Tag 已推送: $targetTag" -ForegroundColor Cyan
