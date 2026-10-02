#!/usr/bin/env bash
# 第四轮：覆盖本次新增/加强的三处检查（第 2 项加强 / 第 3 项加强 / 第 7 项）
set -u

# Isolate global git config: these tests cover gate.ps1 logic, not the hooks
# this machine happens to have installed (see gate-test.sh header).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
GATE="$APPDATA/reasonix/skills/solo-project-control/scripts/gate.ps1"
BASE=$(mktemp -d); MISMATCH=0

refresh() { { echo '# 变更记录'; echo; echo '> 由 git log 自动生成，勿手改。'; echo; git log --pretty=format:'- %ad  %s' --date=format:'%Y-%m-%d %H:%M'; } > docs/CHANGELOG.md; }

mkfiles() {
  local d="$1"; mkdir -p "$d/docs"
  printf '# 项目\n## 代码 / 操作在哪\n- 跑代码门禁：echo ok\n' > "$d/AGENTS.md"
  printf '# PLAN\n## 变更记录\n| 日期 | 变更 | 原因 |\n|---|---|---|\n| 2026-10-01 | 建项目 | 起手 |\n' > "$d/docs/PLAN.md"
  printf '# STATUS\n| 票 | 一句话 | 状态 | 下一步 |\n|---|---|---|---|\n' > "$d/docs/STATUS.md"
  printf '# 验收判据：T-12 · 基线票\n【A 组】\n| # | 判据 | 来源 |\n|---|---|---|\n| 1 | 文件存在 | 推导 |\n' > "$d/docs/验收判据.md"
  printf '# DECISIONS\n## 2026-10-01 选 A\n- 选的：A\n' > "$d/docs/DECISIONS.md"
}

mkbase() {
  local d="$1"; mkfiles "$d"
  # ★ 分两条提交，别合成一条（理由见 gate-test.sh 同名函数）：
  #   第 1 条 = 起项目那次（骨架首次进仓库，门禁整段放行）；
  #   第 2 条 = 普通票提交，把 HEAD 推离「引入骨架」的那次。
  ( cd "$d" && git init -q . && git config core.autocrlf false && git config user.name t && git config user.email t@t \
    && git add -A && git commit -q -m "新增 建 git 仓库与骨架" \
    && refresh && git add docs/CHANGELOG.md && git commit -q --amend --no-edit )
  ( cd "$d" && printf '\n## 2026-10-01 基线\n' >> docs/DECISIONS.md && git add -A \
    && git commit -q -m "新增 基线票" -m "追溯：T-12" \
    && refresh && git add docs/CHANGELOG.md && git commit -q --amend --no-edit )
}

addcommit() {  # $1 目录 $2 subject $3 票号 —— commit → 刷 CHANGELOG → amend 并回同一次提交
  # 票号必须每次唯一：第 10 项（一票一条 commit）不允许同一票号出现在两条 commit 里
  local d="$1" subj="$2" tk="$3"
  ( cd "$d" && git add -A && git commit -q -m "$subj" -m "追溯：$tk" \
    && refresh && git add docs/CHANGELOG.md && git commit -q --amend --no-edit )
}

run_case() {
  local name="$1" exp="$2" d="$3" out act
  out=$( cd "$d" && powershell -NoProfile -File "$GATE" 2>&1 ); act=$?
  if [ "$act" = "$exp" ]; then
    printf '  [一致] %-44s 期望=%s 实际=%s\n' "$name" "$exp" "$act"
  else
    MISMATCH=$((MISMATCH+1))
    printf '  [不符] %-44s 期望=%s 实际=%s  <<<\n' "$name" "$exp" "$act"
    echo "$out" | grep -a '\[FAIL\]' | sed 's/^/           /'
  fi
}

echo "=== 第四轮：本次新增/加强的三处检查 ==="
echo "--- 第 2 项：改了 PLAN 就必须追变更记录行 ---"
mkbase "$BASE/t1"
printf '\n## 功能范围（本轮新增）\n- 又加一条需求\n' >> "$BASE/t1/docs/PLAN.md"
addcommit "$BASE/t1" "调整 加需求但忘了追变更记录" "T-71"
printf '\n# 验收判据：T-71 · 忘了追变更记录\n| 1 | 判据 | 推导 |\n' >> "$BASE/t1/docs/验收判据.md"
run_case "改了 PLAN 却没追变更记录行（应报）" 1 "$BASE/t1"

mkbase "$BASE/t2"
printf '| 2026-10-02 | 加一条需求 | 用户要求 |\n' >> "$BASE/t2/docs/PLAN.md"
addcommit "$BASE/t2" "调整 加需求并追了变更记录" "T-72"
printf '\n# 验收判据：T-72 · 追了变更记录\n| 1 | 判据 | 推导 |\n' >> "$BASE/t2/docs/验收判据.md"
run_case "改了 PLAN 且追了变更记录行" 0 "$BASE/t2"

mkbase "$BASE/t3"
printf '\n## 又一条决策\n- 选了 B\n' >> "$BASE/t3/docs/DECISIONS.md"
addcommit "$BASE/t3" "调整 只动 DECISIONS 没动 PLAN" "T-73"
printf '\n# 验收判据：T-73 · 只动决策\n| 1 | 判据 | 推导 |\n' >> "$BASE/t3/docs/验收判据.md"
run_case "最新 commit 没动 PLAN" 0 "$BASE/t3"

echo "--- 第 3 项：空判据小节不算留档 ---"
mkbase "$BASE/t4"
printf '# 验收判据：T-12\n' > "$BASE/t4/docs/验收判据.md"
run_case "判据小节只剩标题（空小节，应报）" 1 "$BASE/t4"

echo "--- 第 7 项：判据标注的测试文件存在 ---"
mkbase "$BASE/t6"
printf '\n## 测试\n- 测试：test/foo.test.js\n' >> "$BASE/t6/docs/验收判据.md"
run_case "判据标了测试、文件却不在（应报）" 1 "$BASE/t6"

mkbase "$BASE/t7"
mkdir -p "$BASE/t7/test"
printf 'ok\n' > "$BASE/t7/test/foo.test.js"
printf '\n## 测试\n- 测试：test/foo.test.js\n' >> "$BASE/t7/docs/验收判据.md"
run_case "判据标了测试、文件也在" 0 "$BASE/t7"

echo
echo "=== 不符合项：$MISMATCH / 6 ==="
rm -rf "$BASE"
[ "$MISMATCH" -eq 0 ]
