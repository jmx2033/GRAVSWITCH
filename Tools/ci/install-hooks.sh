#!/usr/bin/env bash
# 安装 commit-msg 钩子。每个人 clone 之后执行一次：
#     bash Tools/ci/install-hooks.sh
#
# 装进 .git/hooks/ 的不是规则本体，而是一个转发壳：
# 真正的规则在 Tools/ci/commit-msg（受版本控制）。这样策划改了规则，
# 其他人 git pull 之后立刻生效，不需要每个人重新跑一遍本脚本。
#
# 装完会立刻做三次自检，确认钩子拦得住、也放得过。

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
hooks="$root/.git/hooks"
mkdir -p "$hooks"

cat > "$hooks/commit-msg" <<'SHIM'
#!/usr/bin/env bash
# 自动生成，请勿手改。规则本体在 Tools/ci/commit-msg（随仓库更新）。
root="$(git rev-parse --show-toplevel)"
exec bash "$root/Tools/ci/commit-msg" "$@"
SHIM
chmod +x "$hooks/commit-msg"
printf '已安装转发壳：%s\n' "$hooks/commit-msg"
printf '规则本体：    %s（随 git pull 更新）\n\n' "$root/Tools/ci/commit-msg"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

printf 'update\n' > "$tmp"
if bash "$hooks/commit-msg" "$tmp" >/dev/null 2>&1; then
  printf '自检失败：非法提交信息「update」没有被拦截\n' >&2
  exit 1
fi
printf '自检 1/3 通过：非法信息「update」已被拦截\n'

printf 'feat(slash): 三段刃形按蓄力进度切换 [P1-1]\n' > "$tmp"
if ! bash "$hooks/commit-msg" "$tmp" >/dev/null 2>&1; then
  printf '自检失败：合规提交信息被误拦截\n' >&2
  exit 1
fi
printf '自检 2/3 通过：合规信息正常放行\n'

# 冻结期用的 polish 必须是合法类型，否则 11/7 之后所有人都会被自己拦下
printf 'polish(ui): 卡面描边加粗到 2px [P1-5]\n' > "$tmp"
if ! bash "$hooks/commit-msg" "$tmp" >/dev/null 2>&1; then
  printf '自检失败：polish 类型被误拦截（冻结期只允许 fix / polish）\n' >&2
  exit 1
fi
printf '自检 3/3 通过：polish 类型正常放行\n'

printf '\n装好了。之后 git commit 会自动校验格式；规则更新只需 git pull，不必重装。\n'
