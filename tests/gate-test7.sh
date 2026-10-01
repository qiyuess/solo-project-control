#!/usr/bin/env bash
# 第七轮：对抗用例。
# 前六轮都是「照 SKILL.md 措辞」写的用例；这一轮反过来 ——
# 照「一个想偷懒 / 想蒙混的人实际会怎么写」来设计，专门攻门禁的缝：
# 票号写法一变、在 PLAN 别处加一张表格、一行标多个测试……
# 期望值 = 流程对这些做法给出的承诺。这一轮全绿，才算真守住了。
set -u
GATE="$APPDATA/reasonix/skills/solo-project-control/scripts/gate.ps1"
BASE=$(mktemp -d)
MISMATCH=0

refresh() { { echo '# 变更记录'; echo; echo '> 由 git log 自动生成，勿手改。'; echo; git log --pretty=format:'- %ad  %s' --date=format:'%Y-%m-%d %H:%M'; } > docs/CHANGELOG.md; }

mkfiles() {
  local d="$1"; mkdir -p "$d/docs"
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
## 2026-10-01 选 A
- 选的：A
EOF
}

mkbase() {
  local d="$1"; mkfiles "$d"
  ( cd "$d" && git init -q . && git config core.autocrlf false && git config user.name t && git config user.email t@t \
    && git add -A && git commit -q -m "新增 基线票" -m "追溯：T-12" \
    && refresh && git add docs/CHANGELOG.md && git commit -q --amend --no-edit )
}

addcommit() {  # 真提交（git add -A）——否则测出来的是「未提交」，不是门禁的判断
  local d="$1"
  ( cd "$d" && git add -A && git commit -q -m "$2" -m "$3" \
    && refresh && git add docs/CHANGELOG.md && git commit -q --amend --no-edit )
}

run_case() {  # $1 名称 $2 期望 $3 目录
  local name="$1" exp="$2" d="$3"
  local out act
  out=$( cd "$d" && powershell -NoProfile -File "$GATE" 2>&1 ); act=$?
  if [ "$act" = "$exp" ]; then
    printf '  [一致] %-46s 期望=%s 实际=%s\n' "$name" "$exp" "$act"
  else
    MISMATCH=$((MISMATCH+1))
    printf '  [不符] %-46s 期望=%s 实际=%s  <<<\n' "$name" "$exp" "$act"
    echo "$out" | grep -a '\[FAIL\]' | sed 's/^/           /'
  fi
}

note_case() {  # 只记录实际行为，不判对错（语义类：门禁穿不透，靠人复测）
  local act
  ( cd "$2" && powershell -NoProfile -File "$GATE" >/dev/null 2>&1 ); act=$?
  printf '  [记录] %-46s 实际退出码=%s\n' "$1" "$act"
}

echo "=== 第七轮：对抗用例（票号写法 / PLAN 回写 / 测试标注）==="
echo "--- 基线 ---"
mkbase "$BASE/a00"; run_case "一切照规矩来" 0 "$BASE/a00"

echo "--- 第 4 项：票号写成「合法但容易被忽略」的样子（两张在飞、都没判据）---"
mkbase "$BASE/a01"
printf '| **T-1** | 甲票 | 在干 | x |\n| **T-2** | 乙票 | 在干 | y |\n' >> "$BASE/a01/docs/STATUS.md"
run_case "两张在飞，票号加粗" 1 "$BASE/a01"

mkbase "$BASE/a02"
printf '| T\xe2\x80\x931 | 甲票 | 在干 | x |\n| T\xe2\x80\x911 | 乙票 | 在干 | y |\n' >> "$BASE/a02/docs/STATUS.md"
run_case "两张在飞，连字符是 - / (U+2013/2011)" 1 "$BASE/a02"

mkbase "$BASE/a03"
printf '| T-1（在干） | 甲票 | 在干 | x |\n| T-2（在干） | 乙票 | 在干 | y |\n' >> "$BASE/a03/docs/STATUS.md"
run_case "两张在飞，票号带后缀 T-1（在干）" 1 "$BASE/a03"

mkbase "$BASE/a04"
printf -- '- 在飞：T-1（甲票）\n- 在飞：T-2（乙票）\n' >> "$BASE/a04/docs/STATUS.md"
run_case "两张在飞，写在表格外的正文行" 1 "$BASE/a04"

echo "--- 第 4 项回归：规范写法照样守得住 ---"
mkbase "$BASE/a05"
printf '| T-1 | 甲票 | 在干 | x |\n| T-2 | 乙票 | 在干 | y |\n' >> "$BASE/a05/docs/STATUS.md"
run_case "两张在飞，规范写法（应报）" 1 "$BASE/a05"

mkbase "$BASE/a06"
printf '| T-1 | 甲票 | 在干 | x |\n' >> "$BASE/a06/docs/STATUS.md"
printf '\n# 验收判据：T-1 · 甲票\n| 1 | 甲判据 | 推导 |\n' >> "$BASE/a06/docs/验收判据.md"
run_case "一张在飞，规范写法且有判据" 0 "$BASE/a06"

echo "--- 第 2 项：改 PLAN 必追变更记录（真提交后判定）---"
mkbase "$BASE/a07"
printf '\n## 功能范围（本轮新增）\n| 需求 | 说明 |\n|---|---|\n| 新增导出 | 顺手加的，没进变更记录表 |\n' >> "$BASE/a07/docs/PLAN.md"
addcommit "$BASE/a07" "新增 导出功能" "追溯：T-41"
printf '\n# 验收判据：T-41 · 导出\n| 1 | 判据 | 推导 |\n' >> "$BASE/a07/docs/验收判据.md"
run_case "只在别的表格加行，不追变更记录（应报）" 1 "$BASE/a07"

mkbase "$BASE/a08"
printf '\n## 功能范围（本轮新增）\n- 新增导出（纯文本，一个 | 都没有）\n' >> "$BASE/a08/docs/PLAN.md"
addcommit "$BASE/a08" "新增 导出功能" "追溯：T-42"
printf '\n# 验收判据：T-42 · 导出\n| 1 | 判据 | 推导 |\n' >> "$BASE/a08/docs/验收判据.md"
run_case "改 PLAN 只加纯文本，不追变更记录（应报）" 1 "$BASE/a08"

mkbase "$BASE/a09"
printf '| 2026-10-02 | 新增导出 | 用户要求 |\n' >> "$BASE/a09/docs/PLAN.md"
addcommit "$BASE/a09" "新增 导出功能" "追溯：T-43"
printf '\n# 验收判据：T-43 · 导出\n| 1 | 判据 | 推导 |\n' >> "$BASE/a09/docs/验收判据.md"
run_case "改了 PLAN 并追了变更记录行" 0 "$BASE/a09"

echo "--- 第 7 项：承诺变成测试 ---"
mkbase "$BASE/a10"
mkdir -p "$BASE/a10/test"; : > "$BASE/a10/test/ok.js"
printf '\n## 测试\n- 测试：test/ok.js test/missing.js\n' >> "$BASE/a10/docs/验收判据.md"
run_case "一行两个测试（空格分），第二个不存在（应报）" 1 "$BASE/a10"

mkbase "$BASE/a11"
mkdir -p "$BASE/a11/test"; : > "$BASE/a11/test/ok.js"; : > "$BASE/a11/test/ok2.js"
printf '\n## 测试\n- 测试：test/ok.js, test/ok2.js\n' >> "$BASE/a11/docs/验收判据.md"
run_case "逗号分隔两个测试，文件都在" 0 "$BASE/a11"

mkbase "$BASE/a12"
mkdir -p "$BASE/a12/test"; : > "$BASE/a12/test/my export.test.js"
printf '\n## 测试\n- 测试：test/my export.test.js\n' >> "$BASE/a12/docs/验收判据.md"
run_case "路径含空格，文件存在" 0 "$BASE/a12"

mkbase "$BASE/a13"
mkdir -p "$BASE/a13/test"; : > "$BASE/a13/test/exp.test.js"
printf '\n## 测试\n- 测试：`test/exp.test.js`（覆盖空值）\n' >> "$BASE/a13/docs/验收判据.md"
run_case "路径带中文括注说明" 0 "$BASE/a13"

mkbase "$BASE/a14"
printf '\n## 测试\n- 测试：test/nope.js\n' >> "$BASE/a14/docs/验收判据.md"
run_case "单个测试文件不存在（应报）" 1 "$BASE/a14"

echo "--- 第 3 项回归：票擦它不擦 ---"
mkbase "$BASE/a15"
sed -i '/T-12/,$d' "$BASE/a15/docs/验收判据.md"
run_case "删掉已交付票的判据小节（历史里票号还在）" 1 "$BASE/a15"

echo "--- 第 8 项：最新 commit 前缀合规 ---"
mkbase "$BASE/a19"
printf 'x = 1\n' > "$BASE/a19/src.js"
addcommit "$BASE/a19" "改了点东西" "追溯：T-44"
printf '\n# 验收判据：T-44 · 前缀\n| 1 | 判据 | 推导 |\n' >> "$BASE/a19/docs/验收判据.md"
run_case "commit 没以规定前缀开头（应报）" 1 "$BASE/a19"

echo "--- 第 9 项：最新 commit 的票已擦出台账 ---"
mkbase "$BASE/a18"
printf '| T-12 | 基线票 | 预跑过·待你复测 | 等你复测 |\n' >> "$BASE/a18/docs/STATUS.md"
run_case "最新 commit 的票还留在台账（漏擦票，应报）" 1 "$BASE/a18"

echo "--- 第 3 项：同一票号不得重复留档 ---"
mkbase "$BASE/a20"
mkdir -p "$BASE/a20/docs/判据归档"
printf '# 验收判据：T-12 · 基线票\n| 1 | 又留一份 | 推导 |\n' > "$BASE/a20/docs/判据归档/T-001-T-012.md"
run_case "同一票号在主文件与归档各留一份（应报）" 1 "$BASE/a20"

echo "--- 第 10 项：一票一条 commit ---"
mkbase "$BASE/a21"
printf '\n# 验收判据：T-5 · 某票\n| 1 | 判据 | 推导 |\n' >> "$BASE/a21/docs/验收判据.md"
printf 'x = 1\n' > "$BASE/a21/src.js"
addcommit "$BASE/a21" "新增 某功能" "追溯：T-5"
printf 'y = 2\n' >> "$BASE/a21/src.js"
addcommit "$BASE/a21" "修复 又发现个问题" "追溯：T-5"
run_case "同一张票提交了两次（应报）" 1 "$BASE/a21"

mkbase "$BASE/a22"
printf '\n# 验收判据：T-5 · 甲\n| 1 | a | b |\n\n# 验收判据：T-6 · 乙\n| 1 | c | d |\n' >> "$BASE/a22/docs/验收判据.md"
printf 'x = 1\n' > "$BASE/a22/src.js"
addcommit "$BASE/a22" "新增 两件事一起做" "追溯：T-5
追溯：T-6"
run_case "一条 commit 声明了两个票号（应报）" 1 "$BASE/a22"

mkbase "$BASE/a23"
printf '\n# 验收判据：T-1 · 甲\n| 1 | a | b |\n\n# 验收判据：T-2 · 乙\n| 1 | c | d |\n' >> "$BASE/a23/docs/验收判据.md"
printf 'x = 1\n' > "$BASE/a23/src.js"
addcommit "$BASE/a23" "新增 甲功能" "追溯：T-1"
printf 'y = 2\n' > "$BASE/a23/src2.js"
addcommit "$BASE/a23" "新增 乙功能" "追溯：T-2"
run_case "正常节奏：两张票各一条 commit（含 amend）" 0 "$BASE/a23"

echo "--- 记录型：语义类，门禁穿不透（靠人复测，不算违规）---"
# 借已交付的票号 T-12：它已在 mkbase 那条 commit 里声明过 → 第 10 项（一票一条）会抓
mkbase "$BASE/a16"
echo 'x = 1' > "$BASE/a16/src.js"
addcommit "$BASE/a16" "调整 顺手改了点东西，根本没开票" "追溯：T-12"
run_case "不开票、借已交付票号提交真实改动（应报）" 1 "$BASE/a16"

mkbase "$BASE/a17"
printf '\n## 功能范围\n- 新需求，改了 PLAN 但还没 commit\n' >> "$BASE/a17/docs/PLAN.md"
note_case "改了 PLAN 但未 commit（第 2 项只看本次 commit）" "$BASE/a17"

echo
echo "=== 不符项：$MISMATCH / 23 ==="
rm -rf "$BASE"
[ "$MISMATCH" -eq 0 ]
