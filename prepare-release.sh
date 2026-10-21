#!/bin/bash
set -e

run_git() {
    git "$@"
    if [ $? -ne 0 ]; then
        echo "错误: git $* 执行失败。"
        exit 1
    fi
}

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
