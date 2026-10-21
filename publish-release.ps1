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

function Test-GitAncestor {
    & git merge-base --is-ancestor @args *> $null
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
if ($versionStr -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]{10}$') {
    Write-Error "错误: version 格式无效: $versionStr"
    Write-Error "格式应为: X.Y.Z+YYYYMMDDNN"
    exit 1
}

# 4. 校验构建号中的日期部分（YYYYMMDD）是否为真实存在的日期
$buildNumber = $versionStr.Substring($versionStr.LastIndexOf('+') + 1)
$buildDate = $buildNumber.Substring(0, 8)
$buildDateValue = [datetime]::MinValue
$dateValid = [datetime]::TryParseExact(
    $buildDate,
    'yyyyMMdd',
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::None,
    [ref]$buildDateValue
)
if (-not $dateValid) {
    Write-Error "错误: 构建日期无效: $buildDate"
    exit 1
}

# 5. 校验 versionCode 严格大于远端已发布 Tag 中的最大值
$remoteTags = & git ls-remote --tags --refs origin 'refs/tags/v*'
if ($LASTEXITCODE -ne 0) {
    Write-Error "错误: 无法读取远端 Tag 列表，versionCode 单调性校验中止。"
    exit 1
}
$maxCode = [int64]0
foreach ($line in $remoteTags) {
    if ($line -match '\s+refs/tags/v\S*\+([0-9]{10})$') {
        $code = [int64]($Matches[1])
        if ($code -gt $maxCode) { $maxCode = $code }
    }
}
if ([int64]$buildNumber -le $maxCode) {
    Write-Error "错误: versionCode $buildNumber 不大于已发布最大值 $maxCode"
    exit 1
}

# 6. 生成 release 分支名和 Tag 名
$releaseBranch = "release/v$versionStr"
$targetTag = "v$versionStr"

# 7. 确认 release 分支已经通过 PR 合并到 main
if (-not (Test-GitRef ls-remote --exit-code --heads origin $releaseBranch)) {
    Write-Error "错误: 远程 release 分支不存在: $releaseBranch"
    exit 1
}
Invoke-Git fetch origin "${releaseBranch}:refs/remotes/origin/${releaseBranch}"
if (-not (Test-GitAncestor "origin/$releaseBranch" HEAD)) {
    Write-Error "错误: PR 尚未合并到 main，不能创建 Tag。"
    exit 1
}

# 8. 校验 main 与 release 分支中的版本一致，避免 tag 名与打包内容不符
$branchVersionLine = git show "origin/${releaseBranch}:pubspec.yaml" |
    Select-String -Pattern "^version:" | Select-Object -First 1
if (-not $branchVersionLine) {
    Write-Error "错误: 无法从 release 分支读取 version 字段: $releaseBranch"
    exit 1
}
$branchVersionStr = ($branchVersionLine.Line -split ":", 2)[1].Trim()
if ($branchVersionStr -ne $versionStr) {
    Write-Error "错误: main 中版本 $versionStr 与 release 分支中 $branchVersionStr 不一致"
    exit 1
}

# 9. 检查 Tag 是否已存在
if ((Test-GitRef show-ref --verify --quiet "refs/tags/$targetTag") -or
    (Test-GitRef ls-remote --exit-code --tags origin "refs/tags/$targetTag")) {
    Write-Error "错误: Tag 已存在: $targetTag"
    exit 1
}

# 10. 用户确认并推送 Tag
Write-Host "========== 发布执行 ==========" -ForegroundColor Cyan
Write-Host "将基于版本提交创建并推送 Tag: $targetTag"
Write-Host "==============================" -ForegroundColor Cyan
$confirmation = Read-Host "确认继续？(Y/N)"
if ($confirmation -notmatch "^[yY]$") {
    Write-Host "发布执行已取消。" -ForegroundColor Yellow
    exit 0
}

Write-Host "正在创建并推送 Tag..." -ForegroundColor Green
Invoke-Git tag $targetTag "origin/$releaseBranch"
Invoke-Git push origin $targetTag
Write-Host "发布 Tag 已推送: $targetTag" -ForegroundColor Cyan
