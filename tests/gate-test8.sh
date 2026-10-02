#!/usr/bin/env bash
# 第八轮：gate-hook.ps1 端到端（PreToolUse hook 本身）。
# 前七轮只锁 gate.ps1；hook 一直没人测过，而它出 bug 时同样不报错——
# 它会把门禁跑在错的目录上：干净项目被拦下，或者根本没拦。
# 期望值 = SKILL.md「门禁的硬化」一节的承诺（含 commit 就不放行，其余一律放行）。
set -u

# Isolate global git config: these tests cover gate.ps1 logic, not the hooks
# this machine happens to have installed (see gate-test.sh header).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
HOOK="$APPDATA/reasonix/skills/solo-project-control/scripts/gate-hook.ps1"
GATE="$APPDATA/reasonix/skills/solo-project-control/scripts/gate.ps1"
BASE=$(mktemp -d)
MISMATCH=0

mkproj() {  # $1 目录  $2 good|bad（bad = 台账里两张在飞票，触发第 3、4 项）
  local d="$1" kind="$2"
  mkdir -p "$d/docs"
  cat > "$d/AGENTS.md" <<'EOF'
# 项目
## 代码 / 操作在哪
- 跑代码门禁：echo ok
EOF
  cat > "$d/docs/PLAN.md" <<'EOF'
# PLAN
## 变更记录
| 日期 | 变更 | 原因 |
|---|---|---|
| 2026-10-01 | 建项目 | 起手 |
EOF
  cat > "$d/docs/STATUS.md" <<'EOF'
# STATUS
| 票 | 一句话 | 状态 | 下一步 |
|---|---|---|---|
EOF
  cat > "$d/docs/验收判据.md" <<'EOF'
# 验收判据：T-12 · 基线票
【A 组 · 能自动测】
| # | 判据 | 来源 |
|---|---|---|
| 1 | 文件存在 | 推导 |
EOF
  cat > "$d/docs/DECISIONS.md" <<'EOF'
# DECISIONS
EOF
  (
    cd "$d" && git init -q . && git config core.autocrlf false \
      && git config user.name t && git config user.email t@t \
      && git add -A && git commit -q -m "新增 基线票" -m "追溯：T-12" \
      && { echo '# 变更记录'; echo; echo '> 由 git log 自动生成，勿手改。'; echo; \
           git log --pretty=format:'- %ad  %s' --date=format:'%Y-%m-%d %H:%M'; } > docs/CHANGELOG.md \
      && git add docs/CHANGELOG.md && git commit -q --amend --no-edit
  )
  if [ "$kind" = bad ]; then
    printf '| T-1 | 甲票 | 在干 | x |\n| T-2 | 乙票 | 在干 | y |\n' >> "$d/docs/STATUS.md"
  fi
}

run_hook() {  # $1 目录 $2 命令文本 -> 退出码走 stdout 之外，供 run_case 用
  local d="$1" cmd="$2" w
  # 规范 JSON：payload 里的路径必须是双反斜杠
  w=$(cygpath -w "$d" | sed 's/\\/\\\\/g')
  printf '{"hook_event_name":"PreToolUse","tool_name":"bash","tool_input":{"command":"%s","cwd":"%s"}}' \
    "$cmd" "$w" | powershell -NoProfile -File "$HOOK" >/dev/null 2>&1
}

run_case() {  # $1 名称 $2 目录 $3 命令文本 $4 期望退出码
  local name="$1" d="$2" cmd="$3" exp="$4" act
  run_hook "$d" "$cmd"; act=$?
  if [ "$act" = "$exp" ]; then
    printf '  [一致] %-50s 期望=%s 实际=%s\n' "$name" "$exp" "$act"
  else
    MISMATCH=$((MISMATCH+1))
    printf '  [不符] %-50s 期望=%s 实际=%s  <<<\n' "$name" "$exp" "$act"
  fi
}

echo "=== 第八轮：gate-hook.ps1 端到端（提交识别 / cwd 解析）==="

mkproj "$BASE/good" good
mkproj "$BASE/bad"  bad

# 基线：good 项目直接跑 gate 必须全绿——否则下面「hook 拦了」就不是 hook 的问题
( cd "$BASE/good" && powershell -NoProfile -File "$GATE" >/dev/null 2>&1 )
echo "  [基线] good 项目直接跑 gate 退出码=$?（期望 0）"

echo "--- 拦不拦得住 ---"
run_case "违规项目 + git commit（应拦）"          "$BASE/bad"  'git commit -m x' 2
run_case "违规项目 + 多行 git add/commit（应拦）"  "$BASE/bad"  'git add -A\ngit commit -m x' 2
run_case "违规项目 + git -C . commit（应拦）"      "$BASE/bad"  'git -C . commit -m x' 2

echo "--- 别误拦 ---"
run_case "合规项目 + git commit"                  "$BASE/good" 'git commit -m x' 0
run_case "合规项目 + 多行含 commit"               "$BASE/good" 'git status\ngit commit -m x' 0
run_case "合规项目 + git status（不含 commit）"    "$BASE/good" 'git status' 0
run_case "违规项目 + echo \"git commit\"（按设计放行）" "$BASE/bad" 'echo "git commit"' 0

echo "--- cwd 解析：路径里的 \\t / \\r 序列（曾把合规项目误拦）---"
# JSON 里路径的反斜杠是成对的，整段 payload 一起做 \t / \r 还原就会吃掉
# "...\test-project"、"...\reasonix-x" 这类片段，cwd 失效后静默回落到进程当前目录，
# 门禁于是在别的目录上跑。这两条就是那次的回归。
mkproj "$BASE/hook/test-project" good
run_case "合规项目，路径含 \\test-project"        "$BASE/hook/test-project" 'git commit -m x' 0
mkproj "$BASE/hook/reasonix-x" good
run_case "合规项目，路径含 \\reasonix-x"          "$BASE/hook/reasonix-x" 'git commit -m x' 0

echo
echo "=== 不符项：$MISMATCH / 9 ==="
rm -rf "$BASE"
[ "$MISMATCH" -eq 0 ]
