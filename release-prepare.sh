#!/bin/bash
set -e

run_git() {
    git "$@"
    if [ $? -ne 0 ]; then
        echo "错误: git $* 执行失败。"
        exit 1
    fi
}

if [ "$(git branch --show-current)" != "main" ]; then
    echo "错误: 必须在 main 分支运行。"
    exit 1
fi

OTHER_CHANGES=$(git status --porcelain | awk '$2 != "pubspec.yaml" { print }')
if [ -n "$OTHER_CHANGES" ]; then
    echo "错误: 除 pubspec.yaml 外存在未提交修改。"
    exit 1
fi

VERSION_STR=$(grep '^version:' pubspec.yaml | awk '{print $2}')
if [[ ! "$VERSION_STR" =~ ^[0-9]+\.[0-9]+\.[0-9]+-([0-9]{8})(-[0-9]+)?\+([0-9]{8})([0-9]{2})$ ]]; then
    echo "错误: version 格式无效: ${VERSION_STR}"
    echo "格式应为: X.Y.Z-YYYYMMDD[-N]+YYYYMMDDNN"
    exit 1
fi
if [[ "${BASH_REMATCH[1]}" != "${BASH_REMATCH[3]}" ]]; then
    echo "错误: version 中的两个日期必须一致: ${VERSION_STR}"
    exit 1
fi

TAG_NAME="$(echo "$VERSION_STR" | cut -d'+' -f1)"
RELEASE_BRANCH="release/v${TAG_NAME}"
TARGET_TAG="v${TAG_NAME}"

if git show-ref --verify --quiet "refs/heads/${RELEASE_BRANCH}" || \
   git ls-remote --exit-code --heads origin "${RELEASE_BRANCH}" >/dev/null 2>&1; then
    echo "错误: release 分支已存在: ${RELEASE_BRANCH}"
    exit 1
fi
if git show-ref --verify --quiet "refs/tags/${TARGET_TAG}" || \
   git ls-remote --exit-code --tags origin "refs/tags/${TARGET_TAG}" >/dev/null 2>&1; then
    echo "错误: Tag 已存在: ${TARGET_TAG}"
    exit 1
fi

echo "将创建并推送: ${RELEASE_BRANCH}"
echo "之后请创建 PR: ${RELEASE_BRANCH} -> main"
read -p "确认继续？(Y/N): " confirmation
if [[ ! "$confirmation" =~ ^[yY]$ ]]; then
    exit 0
fi

run_git checkout -b "$RELEASE_BRANCH"
run_git add pubspec.yaml
run_git commit -m "chore: bump version to ${VERSION_STR}"
run_git push origin "$RELEASE_BRANCH"

echo "准备完成。请在 GitHub 创建并合并 PR: ${RELEASE_BRANCH} -> main"
