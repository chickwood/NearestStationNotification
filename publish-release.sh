#!/bin/bash
set -e

run_git() { git "$@"; }

# 判断 YYYYMMDD 是否为真实存在的日期（含闰年规则）
is_valid_date() {
    local y=$((10#${1:0:4})) m=$((10#${1:4:2})) d=$((10#${1:6:2}))
    if [ "$m" -lt 1 ] || [ "$m" -gt 12 ]; then
        return 1
    fi
    if [ "$d" -lt 1 ]; then
        return 1
    fi
    local max_day
    case "$m" in
        1 | 3 | 5 | 7 | 8 | 10 | 12) max_day=31 ;;
        4 | 6 | 9 | 11) max_day=30 ;;
        2)
            if { [ $((y % 4)) -eq 0 ] && [ $((y % 100)) -ne 0 ]; } || [ $((y % 400)) -eq 0 ]; then
                max_day=29
            else
                max_day=28
            fi
            ;;
    esac
    [ "$d" -le "$max_day" ]
}

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
if [[ ! "$VERSION_STR" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]{10}$ ]]; then
    echo "错误: version 格式无效: ${VERSION_STR}"
    echo "格式应为: X.Y.Z+YYYYMMDDNN"
    exit 1
fi

BUILD_NUMBER="${VERSION_STR##*+}"
BUILD_DATE="${BUILD_NUMBER:0:8}"
if ! is_valid_date "$BUILD_DATE"; then
    echo "错误: 构建日期无效: ${BUILD_DATE}"
    exit 1
fi

if ! REMOTE_TAGS=$(git ls-remote --tags --refs origin 'refs/tags/v*'); then
    echo "错误: 无法读取远端 Tag 列表，versionCode 单调性校验中止。"
    exit 1
fi
MAX_CODE=$(printf '%s\n' "$REMOTE_TAGS" \
    | sed -n 's#.*refs/tags/v[^[:space:]]*+\([0-9]\{10\}\)$#\1#p' \
    | sort -n | tail -n 1)
MAX_CODE=${MAX_CODE:-0}
if [ "$BUILD_NUMBER" -le "$MAX_CODE" ]; then
    echo "错误: versionCode ${BUILD_NUMBER} 不大于已发布最大值 ${MAX_CODE}"
    exit 1
fi

RELEASE_BRANCH="release/v${VERSION_STR}"
TARGET_TAG="v${VERSION_STR}"

if ! git ls-remote --exit-code --heads origin "$RELEASE_BRANCH" >/dev/null 2>&1; then
    echo "错误: 远程 release 分支不存在: ${RELEASE_BRANCH}"
    exit 1
fi
run_git fetch origin "$RELEASE_BRANCH:refs/remotes/origin/$RELEASE_BRANCH"
if ! git merge-base --is-ancestor "origin/${RELEASE_BRANCH}" HEAD; then
    echo "错误: PR 尚未合并到 main，不能创建 Tag。"
    exit 1
fi

# 校验 main 与 release 分支中的版本一致，避免 tag 名与打包内容不符
if ! BRANCH_PUBSPEC=$(git --no-pager show "origin/${RELEASE_BRANCH}:pubspec.yaml"); then
    echo "错误: 无法读取 release 分支的 pubspec.yaml: ${RELEASE_BRANCH}"
    exit 1
fi
BRANCH_VERSION=$(printf '%s\n' "$BRANCH_PUBSPEC" | grep '^version:' | awk '{print $2}')
if [ -z "$BRANCH_VERSION" ]; then
    # 回退：内容读取失败时，仅当两边的 pubspec.yaml 完全一致才放行
    if git diff --quiet "origin/${RELEASE_BRANCH}" HEAD -- pubspec.yaml; then
        echo "警告：无法读取 release 分支的 pubspec.yaml，已改用整文件比对，两者一致，放行。"
        BRANCH_VERSION="$VERSION_STR"
    else
        echo "错误: 无法从 release 分支读取 version 字段: ${RELEASE_BRANCH}"
        exit 1
    fi
fi
if [ "$BRANCH_VERSION" != "$VERSION_STR" ]; then
    echo "错误: main 中版本 ${VERSION_STR} 与 release 分支中 ${BRANCH_VERSION} 不一致"
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
