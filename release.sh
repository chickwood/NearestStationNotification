#!/bin/bash

# 1. 解析 pubspec.yaml 中 version 行的文本
VERSION_STR=$(grep '^version:' pubspec.yaml | awk '{print $2}')
if [ -z "$VERSION_STR" ]; then
    echo "错误: 未在 pubspec.yaml 中找到 version 字段"
    exit 1
fi

# 2. 截取 + 前面的文本作为 Git Tag 的名字
TAG_NAME=$(echo "$VERSION_STR" | cut -d'+' -f1)

echo "检测到当前项目版本号为: ${VERSION_STR}"
echo "即将物理创建并推送 Git Tag: v${TAG_NAME}"

# 3. 增加交互式询问控制流
unset confirmation
read -p "是否确认发布？(Y/N): " confirmation
if [[ ! "$confirmation" =~ ^[yY]$ ]]; then
    echo "发布流程已由用户物理中止。"
    exit 0
fi

# 4. 执行 Git 提交流程
git add pubspec.yaml
COMMIT_MSG="chore: bump version to ${VERSION_STR}"
git commit -m "${COMMIT_MSG}"
git push origin main

# 5. 创建本地 Tag 并推送到远端
TARGET_TAG="v${TAG_NAME}"
git tag "${TARGET_TAG}"
git push origin "${TARGET_TAG}"