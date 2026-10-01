#!/usr/bin/env bash
# 第三轮：第 3 项「判据留档」的实际强度
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

note_case() {
  local name="$1" d="$2" act
  ( cd "$d" && powershell -NoProfile -File "$GATE" >/dev/null 2>&1 ); act=$?
  printf '  [记录] %-46s 实际退出码=%s\n' "$name" "$act"
}

echo "=== 第三轮：判据留档到底守到什么粒度 ==="

mkbase "$BASE/m1"
printf '# 验收判据：T-12\n' > "$BASE/m1/docs/验收判据.md"
note_case "判据文件只有一行标题、零条判据" "$BASE/m1"

mkbase "$BASE/m3"
printf '# 判据汇总\n\n本票实现说明见 T-12 备注。\n' > "$BASE/m3/docs/验收判据.md"
run_case "票号只在正文出现（非标题，无「验收判据」字样）" 1 "$BASE/m3"

mkbase "$BASE/m4"
printf '# 判据汇总\n\n验收判据：T-12 见下文。\n' > "$BASE/m4/docs/验收判据.md"
note_case "正文写「验收判据：T-12」但并非小节标题" "$BASE/m4"

echo
echo "=== 不符合项：$MISMATCH / 1（另 2 条为记录）==="
rm -rf "$BASE"
[ "$MISMATCH" -eq 0 ]
