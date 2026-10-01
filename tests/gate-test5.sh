#!/usr/bin/env bash
# 第五轮：门禁第 4 项到底怎么数「在飞」——状态词算不算数
set -u
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
  ( cd "$d" && git init -q . && git config core.autocrlf false && git config user.name t && git config user.email t@t \
    && git add -A && git commit -q -m "新增 基线票" -m "追溯：T-12" \
    && refresh && git add docs/CHANGELOG.md && git commit -q --amend --no-edit )
}

run_case() {
  local name="$1" exp="$2" d="$3" out act
  out=$( cd "$d" && powershell -NoProfile -File "$GATE" 2>&1 ); act=$?
  if [ "$act" = "$exp" ]; then
    printf '  [一致] %-46s 期望=%s 实际=%s\n' "$name" "$exp" "$act"
  else
    MISMATCH=$((MISMATCH+1))
    printf '  [不符] %-46s 期望=%s 实际=%s  <<<\n' "$name" "$exp" "$act"
    echo "$out" | grep -a '\[FAIL\]' | sed 's/^/           /'
  fi
}

echo "=== 第五轮：第 4 项怎么数「在飞」（状态词算不算） ==="

mkbase "$BASE/v1"
# 票号特意用 T-13（不占基线的 T-12）：T-12 在 mkbase 里已经交付过（commit 带 追溯：T-12），
# 若让它留在台账里，会被第 9 项「最新 commit 的票已擦出台账」判成漏擦票。
printf '| T-13 | 某票 | 预跑过·待你复测 | 等你复测 |\n' >> "$BASE/v1/docs/STATUS.md"
printf '\n# 验收判据：T-13 · 某票\n| 1 | 某判据 | 推导 |\n' >> "$BASE/v1/docs/验收判据.md"
run_case "台账里只有 1 张「预跑过·待你复测」" 0 "$BASE/v1"

mkbase "$BASE/v2"
printf '| T-13 | 甲票 | 预跑过·待你复测 | 等你复测 |\n' >> "$BASE/v2/docs/STATUS.md"
printf '| T-1 | 乙票 | 在干 | 写判据 |\n' >> "$BASE/v2/docs/STATUS.md"
printf '\n# 验收判据：T-1 · 乙票\n| 1 | 乙判据 | 推导 |\n' >> "$BASE/v2/docs/验收判据.md"
printf '\n# 验收判据：T-13 · 甲票\n| 1 | 甲判据 | 推导 |\n' >> "$BASE/v2/docs/验收判据.md"
run_case "1 张「待你复测」+ 1 张「在干」" 1 "$BASE/v2"

mkbase "$BASE/v3"
printf '| T-13 | 甲票 | 预跑过·待你复测 | 等你复测 |\n' >> "$BASE/v3/docs/STATUS.md"
printf '| T-1 | 乙票 | 预跑过·待你复测 | 等你复测 |\n' >> "$BASE/v3/docs/STATUS.md"
printf '\n# 验收判据：T-1 · 乙票\n| 1 | 乙判据 | 推导 |\n' >> "$BASE/v3/docs/验收判据.md"
printf '\n# 验收判据：T-13 · 甲票\n| 1 | 甲判据 | 推导 |\n' >> "$BASE/v3/docs/验收判据.md"
run_case "2 张都标「待你复测」" 1 "$BASE/v3"

mkbase "$BASE/v4"
printf '作废：需求变了，这张票不做了\n' >> "$BASE/v4/docs/验收判据.md"
run_case "作废的票保留判据小节（已移出台账）" 0 "$BASE/v4"

mkbase "$BASE/v5"
printf '# 验收判据：T-99 · 别的票\n| 1 | x | y |\n' > "$BASE/v5/docs/验收判据.md"
run_case "曾交付过的票把小节整段删掉（应报）" 1 "$BASE/v5"

echo
echo "=== 不符合项：$MISMATCH / 5 ==="
rm -rf "$BASE"
[ "$MISMATCH" -eq 0 ]
