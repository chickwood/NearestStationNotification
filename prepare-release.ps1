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

# 1. 安全检查：必须在 main 分支执行该脚本
$currentBranch = (git branch --show-current).Trim()
if ($currentBranch -ne "main") {
    Write-Error "错误: 发布准备脚本必须在 main 分支运行！当前处于: $currentBranch"
    exit 1
}

# 2. 检查本地是否有未提交的修改（只允许 pubspec.yaml）
$gitStatus = git status --porcelain
if ($gitStatus) {
    $hasOtherChanges = $gitStatus | Where-Object {
        $path = $_.Substring(3).Trim()
        $path -ne "pubspec.yaml"
    }
    if ($hasOtherChanges) {
        Write-Error "错误: 除 pubspec.yaml 外存在未提交修改，请先 clean 或 commit。"
        exit 1
    }
}

# 3. 解析并校验 pubspec.yaml 中的 version 字段
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

# 7. 检查目标分支和 Tag 是否已存在
if ((Test-GitRef show-ref --verify --quiet "refs/heads/$releaseBranch") -or
    (Test-GitRef ls-remote --exit-code --heads origin $releaseBranch)) {
    Write-Error "错误: release 分支已存在: $releaseBranch"
    exit 1
}
if ((Test-GitRef show-ref --verify --quiet "refs/tags/$targetTag") -or
    (Test-GitRef ls-remote --exit-code --tags origin "refs/tags/$targetTag")) {
    Write-Error "错误: Tag 已存在: $targetTag"
    exit 1
}

# 8. 用户确认
Write-Host "========== 发布准备 ==========" -ForegroundColor Cyan
Write-Host "将创建并推送: $releaseBranch"
Write-Host "之后请创建 PR: $releaseBranch -> main"
Write-Host "==============================" -ForegroundColor Cyan
$confirmation = Read-Host "确认继续？(Y/N)"
if ($confirmation -notmatch "^[yY]$") {
    Write-Host "发布准备已取消。" -ForegroundColor Yellow
    exit 0
}

# 9. 创建并推送 release 分支
Write-Host "1. 创建并切换到 release 分支..." -ForegroundColor Green
Invoke-Git checkout -b $releaseBranch

Write-Host "2. 提交版本号变更并推送 release 分支..." -ForegroundColor Green
Invoke-Git add pubspec.yaml
Invoke-Git commit -m "chore: bump version to $versionStr"
Invoke-Git push origin $releaseBranch

Write-Host "准备完成，请在 GitHub 创建并合并 PR: $releaseBranch -> main" -ForegroundColor Cyan
