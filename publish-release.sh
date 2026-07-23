#!/bin/bash
set -e

run_git() { git "$@"; }

if [ -n "$(git status --porcelain)" ]; then
    echo "错误: 工作区不干净，请先 clean 或 commit。"
    exit 1
fi

run_git checkout main
run_git fetch origin main
run_git merge --ff-only origin/main
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    echo "错误: 本地 main 未能同步到 origin/main。"
    exit 1
fi

VERSION_STR=$(grep '^version:' pubspec.yaml | awk '{print $2}')
if [[ ! "$VERSION_STR" =~ ^[0-9]+\.[0-9]+\.[0-9]+-([0-9]{8})(-[0-9]+)?\+([0-9]{8})([0-9]{2})$ ]]; then
    echo "错误: version 格式无效: ${VERSION_STR}"
    exit 1
fi
if [[ "${BASH_REMATCH[1]}" != "${BASH_REMATCH[3]}" ]]; then
    echo "错误: version 中的两个日期必须一致: ${VERSION_STR}"
    exit 1
fi

TAG_NAME="$(echo "$VERSION_STR" | cut -d'+' -f1)"
RELEASE_BRANCH="release/v${TAG_NAME}"
TARGET_TAG="v${TAG_NAME}"

if ! git ls-remote --exit-code --heads origin "$RELEASE_BRANCH" >/dev/null 2>&1; then
    echo "错误: 远程 release 分支不存在: ${RELEASE_BRANCH}"
    exit 1
fi
run_git fetch origin "$RELEASE_BRANCH:refs/remotes/origin/$RELEASE_BRANCH"
if ! git merge-base --is-ancestor "origin/${RELEASE_BRANCH}" HEAD; then
    echo "错误: PR 尚未合并到 main，不能创建 Tag。"
    exit 1
fi
if git show-ref --verify --quiet "refs/tags/${TARGET_TAG}" || \
   git ls-remote --exit-code --tags origin "refs/tags/${TARGET_TAG}" >/dev/null 2>&1; then
    echo "错误: Tag 已存在: ${TARGET_TAG}"
    exit 1
fi

echo "将基于版本提交创建并推送 Tag: ${TARGET_TAG}"
read -p "确认继续？(Y/N): " confirmation
if [[ ! "$confirmation" =~ ^[yY]$ ]]; then
    exit 0
fi

run_git tag "$TARGET_TAG" "origin/${RELEASE_BRANCH}"
run_git push origin "$TARGET_TAG"
echo "发布 Tag 已推送: ${TARGET_TAG}"
