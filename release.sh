#!/bin/bash
set -e # 遇到任何错误立即停止执行

# 1. 安全检查：必须在 main 分支执行该脚本
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "错误: 发布脚本必须在 main 分支运行！当前处于: ${CURRENT_BRANCH}"
    exit 1
fi

# 2. 检查本地是否有未提交的修改（除 pubspec.yaml 外不应有其他杂质）
if [ -n "$(git status --porcelain | grep -v 'pubspec.yaml')" ]; then
    echo "错误: 存在未提交的代码修改，请先 clean 或 commit 后再执行发布。"
    exit 1
fi

# 3. 解析当前修改后的 pubspec.yaml 中的 version 字段
VERSION_STR=$(grep '^version:' pubspec.yaml | awk '{print $2}')
if [ -z "$VERSION_STR" ]; then
    echo "错误: 未在 pubspec.yaml 中找到 version 字段"
    exit 1
fi

# 4. 截取 + 前面的文本作为 Git Tag 的名字
TAG_NAME=$(echo "$VERSION_STR" | cut -d'+' -f1)
RELEASE_BRANCH="release/v${TAG_NAME}"
TARGET_TAG="v${TAG_NAME}"

echo "========== 发布准备 =========="
echo "基于 main 分支创建: ${RELEASE_BRANCH}"
echo "即将创建并推送 Tag : ${TARGET_TAG}"
echo "=============================="

# 5. 交互式询问
unset confirmation
read -p "是否确认开始自动化发布流程？(Y/N): " confirmation
if [[ ! "$confirmation" =~ ^[yY]$ ]]; then
    echo "发布流程已由用户物理中止。"
    exit 0
fi

# 6. 核心流转逻辑
echo "1. 创建并切换到独立发布分支: ${RELEASE_BRANCH}..."
git checkout -b "${RELEASE_BRANCH}"

echo "2. 提交版本号变更并推送到远程发布分支..."
git add pubspec.yaml
git commit -m "chore: bump version to ${VERSION_STR}"
git push origin "${RELEASE_BRANCH}"

echo "3. 物理创建本地 Tag 并推送到远端激活 GitHub Actions..."
git tag "${TARGET_TAG}"
git push origin "${TARGET_TAG}"

echo "4. 正在切回 main 分支并【精准合并】pubspec.yaml..."
git checkout main

# 【核心修改点】不使用全局 merge，而是只把 release 分支的 pubspec.yaml 捞过来
git checkout "${RELEASE_BRANCH}" -- pubspec.yaml

# 提交这个独立文件的变更并推送到远程 main
git add pubspec.yaml
git commit -m "chore: sync version bump from ${RELEASE_BRANCH} to main"
git push origin main

echo "5. 清理本地临时发布分支..."
git branch -D "${RELEASE_BRANCH}"