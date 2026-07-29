#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${REPO_OWNER:-Stardust269}"
REPO_NAME="${REPO_NAME:-放心借客群lookalike}"
SOURCE_BRANCH="${SOURCE_BRANCH:-fxj-lookalike-standalone}"
PROFILE_REPO="${PROFILE_REPO:-https://github.com/${REPO_OWNER}/Stardust269.git}"
TARGET_REPO="${TARGET_REPO:-https://github.com/${REPO_OWNER}/${REPO_NAME}.git}"

echo "==> 目标仓库: ${TARGET_REPO}"
echo "==> 源分支: ${SOURCE_BRANCH}（来自 ${PROFILE_REPO}）"
echo
echo "请先在 GitHub 创建空仓库: ${REPO_OWNER}/${REPO_NAME}"
read -r -p "已创建空仓库？按 Enter 继续，Ctrl+C 取消..."

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

git clone --branch "${SOURCE_BRANCH}" "${PROFILE_REPO}" "${WORKDIR}/repo"
cd "${WORKDIR}/repo"
git remote add lookalike "${TARGET_REPO}" 2>/dev/null || git remote set-url lookalike "${TARGET_REPO}"
git push -u lookalike "${SOURCE_BRANCH}:main"

echo
echo "完成。独立仓库地址: ${TARGET_REPO}"
