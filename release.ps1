# 1. 物理读取并解析 pubspec.yaml 中的 version 字段
$versionLine = Select-String -Path "pubspec.yaml" -Pattern "^version:" | Select-Object -First 1
if (-not $versionLine) {
    Write-Error "未在 pubspec.yaml 中找到 version 字段"
    exit 1
}

$versionStr = ($versionLine.Line -split ":")[1].Trim()

# 2. 截取 + 前面的文本作为 Git Tag 名称
$tagName = ($versionStr -split "\+")[0]

Write-Host "检测到当前项目版本号为: $versionStr"
Write-Host "即将物理创建并推送 Git Tag: v$tagName"

# 3. 增加交互式询问控制流
$confirmation = Read-Host "是否确认发布？(Y/N)"
if ($confirmation -notmatch "^[yY]$") {
    Write-Host "发布流程已由用户物理中止。" -ForegroundColor Yellow
    exit 0
}

# 4. 物理执行 Git 提交流程
git add pubspec.yaml
git commit -m "chore: bump version to $versionStr"
git push origin main

# 5. 物理创建本地 Tag 并推送到远端
git tag "v$tagName"
git push origin "v$tagName"