$ErrorActionPreference = "Stop" # 遇到错误立即停止

# 1. 安全检查：必须在 main 分支执行该脚本
$currentBranch = (git branch --show-current).Trim()
if ($currentBranch -ne "main") {
    Write-Error "错误: 发布脚本必须在 main 分支运行！当前处于: $currentBranch"
    exit 1
}

# 2. 检查本地是否有未提交的修改
$gitStatus = git status --porcelain
if ($gitStatus) {
    $hasOtherChanges = $gitStatus | Where-Object { $_ -notmatch "pubspec.yaml" }
    if ($hasOtherChanges) {
        Write-Error "错误: 存在未提交的代码修改，请先 clean 或 commit 后再执行发布。"
        exit 1
    }
}

# 3. 解析当前修改后的 pubspec.yaml 中的 version 字段
$versionLine = Select-String -Path "pubspec.yaml" -Pattern "^version:" | Select-Object -First 1
if (-not $versionLine) {
    Write-Error "错误: 未在 pubspec.yaml 中找到 version 字段"
    exit 1
}
$versionStr = ($versionLine.Line -split ":")[1].Trim()

# 4. 截取 + 前面的文本作为 Git Tag 的名字
$tagName = ($versionStr -split "\+")[0]
$releaseBranch = "release/v$tagName"
$targetTag = "v$tagName"

Write-Host "========== 发布准备 ==========" -ForegroundColor Cyan
Write-Host "基于 main 分支创建: $releaseBranch"
Write-Host "即将创建并推送 Tag : $targetTag"
Write-Host "==============================" -ForegroundColor Cyan

# 5. 交互式询问
$confirmation = Read-Host "是否确认开始自动化发布流程？(Y/N)"
if ($confirmation -notmatch "^[yY]$") {
    Write-Host "发布流程已由用户物理中止。" -ForegroundColor Yellow
    exit 0
}

# 6. 核心流转逻辑
Write-Host "1. 创建并切换到独立发布分支: $releaseBranch..." -ForegroundColor Green
git checkout -b $releaseBranch

Write-Host "2. 提交版本号变更并推送到远程发布分支..." -ForegroundColor Green
git add pubspec.yaml
git commit -m "chore: bump version to $versionStr"
git push origin $releaseBranch

Write-Host "3. 物理创建本地 Tag 并推送到远端激活 GitHub Actions..." -ForegroundColor Green
git tag $targetTag
git push origin $targetTag

Write-Host "4. 正在切回 main 分支并【精准合并】pubspec.yaml..." -ForegroundColor Green
git checkout main

# 【核心修改点】不使用全局 merge，而是只把 release 分支的 pubspec.yaml 捞过来
git checkout $releaseBranch -- pubspec.yaml

# 提交这个独立文件的变更并推送到远程 main
git add pubspec.yaml
git commit -m "chore: sync version bump from $releaseBranch to main"
git push origin main

Write-Host "5. 清理本地临时发布分支..." -ForegroundColor Green
git branch -d $releaseBranch