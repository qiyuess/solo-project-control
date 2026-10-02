#!/usr/bin/env bash
# 第十二轮：第 11 项「票粒度」——每票 A / B 组条数。
# 契约：A 或 B **单独**超过 10 条就提示；**只提示、不拦提交**（退出码仍为 0）。
# 为什么单列一套：这条与其余 10 项性质不同——它是 notice，不影响退出码；
# 一旦退化成 blocks（比如哪天被并进 $failed），「提示」就变成「堵提交」了。
set -u
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
GATE="$APPDATA/reasonix/skills/solo-project-control/scripts/gate.ps1"
BASE=$(mktemp -d)
MISMATCH=0

# 造一票：$2 = A 组条数，$3 = B 组条数
mkproj() {  # $1 目录 $2 A条数 $3 B条数
  local d="$1" na="$2" nb="$3"; mkdir -p "$d/docs"
  printf '# 项目\n- 跑代码门禁：echo ok\n' > "$d/AGENTS.md"
  printf '# PLAN\n## 变更记录\n| 日期 | 变更 | 原因 |\n|---|---|---|\n| 2026-10-01 | 建项目 | 起手 |\n' > "$d/docs/PLAN.md"
  printf '# STATUS\n| 票 | 一句话 | 状态 | 下一步 |\n|---|---|---|---|\n| T-001 | 某票 | 在干 | x |\n' > "$d/docs/STATUS.md"
  printf '# DECISIONS\n## 2026-10-01 选 A\n- 选的：A\n' > "$d/docs/DECISIONS.md"
  printf '# 变更记录\n\n> 由 git log 自动生成，勿手改。\n' > "$d/docs/CHANGELOG.md"
  {
    printf '# 验收判据：T-001 · 某票\n\n- 前置事实：接口 X\n\n## 验收条件（逐条「是 / 否」）\n'
    printf '【A 组 · 能自动测】\n| # | 判据 | 来源 |\n|---|---|---|\n'
    local i
    for ((i=1;i<=na;i++)); do printf '| %d | A 判据 %d | 推导 |\n' "$i" "$i"; done
    printf '\n【B 组 · 要操作着看】\n| # | 判据 | 来源 |\n|---|---|---|\n'
    for ((i=1;i<=nb;i++)); do printf '| %d | B 判据 %d（B-真机） | 推导 |\n' "$i" "$i"; done
    printf '\n## 演示脚本（B 组）\n1. 点哪里\n'
  } > "$d/docs/验收判据.md"
  # 造仓库：init + 提交骨架（把判据也一并提交进去——这样「还没 coding」的状态才真实：
  # 判据已经写好、已经交付过一次，但工作区里没有别的代码改动）
  ( cd "$d" && git init -q . && git config core.autocrlf false \
    && git config user.name t && git config user.email t@t \
    && git add -A && git commit -q -m "新增 建骨架（含判据）" -m "追溯：T-001" ) 2>/dev/null
}

run() {  # $1 目录 -> 打印退出码
  local rc
  ( cd "$1" && powershell -NoProfile -File "$GATE" ) >/dev/null 2>&1
  rc=$?
  echo "$rc"
}
out() { ( cd "$1" && powershell -NoProfile -File "$GATE" 2>&1 ); }

chkcode() {  # $1 名称 $2 期望 $3 实际
  if [ "$3" = "$2" ]; then printf '  [一致] %-50s 期望=%s 实际=%s\n' "$1" "$2" "$3"
  else MISMATCH=$((MISMATCH+1)); printf '  [不符] %-50s 期望=%s 实际=%s  <<<\n' "$1" "$2" "$3"; fi
}

echo "=== 第十二轮：票粒度（A / B 各 <= 10 条，只提示不拦）==="

# 1) A 单独超 10 → 提示，但不拦
mkproj "$BASE/g1" 12 3
o=$(out "$BASE/g1")
if echo "$o" | grep -aq '\[提示\].*票粒度'; then
  printf '  [一致] %-50s 出现 [提示] 票粒度\n' "A=12 B=3：显示为提示"
else
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-50s 未出现 [提示]\n' "A=12 B=3：显示为提示"
fi
if echo "$o" | grep -aq 'A 组 12 条'; then
  printf '  [一致] %-50s 报出 A 组 12 条\n' "A=12 B=3：点名 A 超标"
else
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-50s 未点名 A 超标\n' "A=12 B=3：点名 A 超标"
fi
chkcode "A=12 B=3：不拦提交（退出码 0）" 0 "$(run "$BASE/g1")"

# 2) B 单独超 10 → 提示
mkproj "$BASE/g2" 5 14
o=$(out "$BASE/g2")
if echo "$o" | grep -aq 'B 组 14 条'; then
  printf '  [一致] %-50s 报出 B 组 14 条\n' "A=5 B=14：点名 B 超标"
else
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-50s 未点名 B 超标\n' "A=5 B=14：点名 B 超标"
fi
chkcode "A=5 B=14：不拦提交（退出码 0）" 0 "$(run "$BASE/g2")"

# 3) 都没超 → 不出现 [提示]（显示为 OK）
mkproj "$BASE/g3" 8 6
o=$(out "$BASE/g3")
if echo "$o" | grep -aq '票粒度'; then
  if echo "$o" | grep -aq '\[提示\].*票粒度'; then
    MISMATCH=$((MISMATCH+1)); printf '  [不符] %-50s 不该提示\n' "A=8 B=6：不提示"
  else
    printf '  [一致] %-50s 显示 OK、不提示\n' "A=8 B=6：不提示"
  fi
  if echo "$o" | grep -aq 'T-001: A=8 B=6'; then
    printf '  [一致] %-50s 汇总显示 A=8 B=6\n' "A=8 B=6：汇总正确"
  else
    MISMATCH=$((MISMATCH+1)); printf '  [不符] %-50s 汇总不符\n' "A=8 B=6：汇总正确"
  fi
else
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-50s 未找到票粒度项\n' "A=8 B=6：不提示"
fi
chkcode "A=8 B=6：退出码 0" 0 "$(run "$BASE/g3")"

# 4) 边界：正好 10 条 → 不算超（阈值是 > 10）
mkproj "$BASE/g4" 10 10
o=$(out "$BASE/g4")
if echo "$o" | grep -aq '\[提示\].*票粒度'; then
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-50s 正好 10 条不该提示\n' "A=10 B=10：边界不提示"
else
  printf '  [一致] %-50s 正好 10 条不提示\n' "A=10 B=10：边界不提示"
fi
chkcode "A=10 B=10：退出码 0" 0 "$(run "$BASE/g4")"

# 5) 边界：11 条 → 算超
mkproj "$BASE/g5" 11 1
o=$(out "$BASE/g5")
if echo "$o" | grep -aq '\[提示\].*票粒度'; then
  printf '  [一致] %-50s 11 条触发提示\n' "A=11：边界触发"
else
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-50s 11 条该提示\n' "A=11：边界触发"
fi

# 6) ★ 关键回归：只有「票粒度」超标时，整份门禁仍须放行（不得拉红别的项）
#    这条防的是「哪天它被并进 $failed，提示悄悄变成堵提交」。
mkproj "$BASE/g6" 20 20
o=$(out "$BASE/g6")
if echo "$o" | grep -aq '全过' && echo "$o" | grep -aq '提示'; then
  printf '  [一致] %-50s 「全过（N 项，另有 M 项提示）」\n' "超标时总结仍为「全过」"
else
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-50s 总结未体现「全过+提示」\n' "超标时总结仍为「全过」"
  echo "$o" | tail -6 | sed 's/^/           /'
fi
chkcode "A=20 B=20：退出码仍 0" 0 "$(run "$BASE/g6")"

# 7) ★ 已交付的票不再提示（范围限定在飞票）
#    已交付 = 已从台账擦除 + 已进 git log（追溯：T-xxx）。这时还提示它是没意义的
#    ——它已经切出来了，你只能看它留在那里。
mkproj "$BASE/g7" 12 3
# mkproj 已经把骨架+判据 commit 了（T-001 已交付）。台账里**本来就没** T-001——
# 所以不用再提交。这里只需把台账补上 T-002 当在飞票，让第 4 项有东西可数。
sed -i '/T-001/d' "$BASE/g7/docs/STATUS.md"
printf '| T-002 | 推进 | 在干 | x |\n' >> "$BASE/g7/docs/STATUS.md"
# T-002 也得有判据小节（第 3 项会拦），但这**不构成交付**——没 commit 它，所以它不算已交付。
printf '\n# 验收判据：T-002 · 推进\n\n## 验收条件\n【A 组 · 能自动测】\n| # | 判据 | 来源 |\n|---|---|---|\n| 1 | 最小判据 | 推导 |\n' >> "$BASE/g7/docs/验收判据.md"
o=$(out "$BASE/g7")
rc7=$(run "$BASE/g7")
if [ "${DEBUG_G7:-0}" = "1" ]; then
  echo "--- g7 调试 ---"
  ( cd "$BASE/g7" && git status --short && echo "--- 验收判据里的 T-002 小节 ---" && grep -n "T-002" docs/验收判据.md && echo "--- STATUS ---" && cat docs/STATUS.md )
  echo "--- 门禁完整输出 ---"; echo "$o" | tail -30
fi
if echo "$o" | grep -aq 'T-001.*A 组 12 条'; then
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-50s 已交付的 T-001 不该再提示\n' "已交付 T-001：不该提示"
else
  printf '  [一致] %-50s 已交付的票不再提示\n' "已交付 T-001：不再提示"
fi
chkcode "已交付 T-001：退出码 0" 0 "$(run "$BASE/g7")"

# 8) ★ coding 已开始 → 不再提示（本条的另一半）
#    第 11 项只在「切票 → 判据落地 → coding 前」这个窗口提示；coding 一旦开始
#    （工作区里出现了骨架之外的代码改动），提示就没用了——你只能做完这张票。
mkproj "$BASE/g8" 12 3
mkdir -p "$BASE/g8/src"
printf 'console.log(1)\n' > "$BASE/g8/src/index.js"
o=$(out "$BASE/g8")
if echo "$o" | grep -aq '已开始 coding，跳过提示'; then
  printf '  [一致] %-50s coding 已开始，提示被跳过\n' "coding 已开始：不再提示"
else
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-50s coding 已开始却仍在提示\n' "coding 已开始：不再提示"
fi
chkcode "coding 已开始：退出码 0" 0 "$(run "$BASE/g8")"

echo
echo "=== 不符项：$MISMATCH / 11 ==="
rm -rf "$BASE"
[ "$MISMATCH" -eq 0 ]
