#!/usr/bin/env bash
# 第六轮：判据归档 —— 门禁第 3/7 项能否在主文件 + docs/判据归档/ 两处一起找到
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
    printf '  [一致] %-44s 期望=%s 实际=%s\n' "$name" "$exp" "$act"
  else
    MISMATCH=$((MISMATCH+1))
    printf '  [不符] %-44s 期望=%s 实际=%s  <<<\n' "$name" "$exp" "$act"
    echo "$out" | grep -a '\[FAIL\]' | sed 's/^/           /'
  fi
}

echo "=== 第六轮：判据归档（主文件 + docs/判据归档/）==="

mkbase "$BASE/a1"
mkdir -p "$BASE/a1/docs/判据归档"
printf '# 验收判据：T-12 · 基线票\n| 1 | 文件存在 | 推导 |\n' > "$BASE/a1/docs/判据归档/T-001-T-012.md"
printf '# 判据索引\n已交付的判据见 docs/判据归档/\n' > "$BASE/a1/docs/验收判据.md"
run_case "判据只存在于归档文件里" 0 "$BASE/a1"

mkbase "$BASE/a2"
mkdir -p "$BASE/a2/docs/判据归档"
printf '# 验收判据：T-12\n' > "$BASE/a2/docs/判据归档/T-001-T-012.md"
printf '# 判据索引\n' > "$BASE/a2/docs/验收判据.md"
run_case "归档里的小节是空的（应报）" 1 "$BASE/a2"

mkbase "$BASE/a3"
mkdir -p "$BASE/a3/docs/判据归档"
printf '# 验收判据：T-12 · 基线票\n- 测试：`test/missing.js`\n' > "$BASE/a3/docs/判据归档/T-001-T-012.md"
printf '# 判据索引\n' > "$BASE/a3/docs/验收判据.md"
run_case "归档里标了测试但文件不在（应报）" 1 "$BASE/a3"

mkbase "$BASE/a4"
mkdir -p "$BASE/a4/docs/判据归档" "$BASE/a4/test"
printf 'x\n' > "$BASE/a4/test/ok.js"
printf '# 验收判据：T-12 · 基线票\n- 测试：`test/ok.js`\n' > "$BASE/a4/docs/判据归档/T-001-T-012.md"
printf '# 判据索引\n' > "$BASE/a4/docs/验收判据.md"
run_case "归档里标了测试且文件在" 0 "$BASE/a4"

echo
echo "=== 不符合项：$MISMATCH / 4 ==="
rm -rf "$BASE"
[ "$MISMATCH" -eq 0 ]
