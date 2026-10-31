#!/usr/bin/env bash
# 安装 commit-msg 钩子。每个人 clone 之后执行一次：
#     bash Tools/ci/install-hooks.sh
# 装完会立刻做正反两次自检，确认钩子真的拦得住。

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
hooks="$root/.git/hooks"
mkdir -p "$hooks"
cp "$root/Tools/ci/commit-msg" "$hooks/commit-msg"
chmod +x "$hooks/commit-msg"
printf '已安装：%s\n\n' "$hooks/commit-msg"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

printf 'update\n' > "$tmp"
if bash "$hooks/commit-msg" "$tmp" >/dev/null 2>&1; then
  printf '自检失败：非法提交信息「update」没有被拦截\n' >&2
  exit 1
fi
printf '自检 1/2 通过：非法信息「update」已被拦截\n'

printf 'feat(slash): 三段刃形按蓄力进度切换 [P1-1]\n' > "$tmp"
if ! bash "$hooks/commit-msg" "$tmp" >/dev/null 2>&1; then
  printf '自检失败：合规提交信息被误拦截\n' >&2
  exit 1
fi
printf '自检 2/2 通过：合规信息正常放行\n'

printf '\n装好了。之后 git commit 时会自动校验格式，PR 上 CI 会再查一次。\n'
