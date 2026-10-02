#!/usr/bin/env bash
# 第九轮：起项目那次 commit（骨架首次进仓库）。
# 前八轮锁的都是「仓库已有历史」时的行为；这一轮锁**一条 commit 都没有**时：
#   仓库里还没有任何 commit（git rev-list -n 1 --all 无输出）
#     → 第 2 / 5 / 6 / 8 / 10 项自动放行 —— hook 在 commit 之前跑门禁，
#       「上一条 commit」此刻不存在，这几项无从上查，是技术必然、不是违规。
#     → 第 1 项（骨架齐全）**不放行** —— 骨架建好正是首次提交的前提。
#     → 第 3 / 4 / 7 / 9 项照常（本来就不依赖上一条 commit）。
#   一旦仓库里有了 commit，同样内容立刻按正常规则拦下 —— 放行只认「真空仓库」。
# 期望值 = SKILL.md「门禁」节「起项目那次 commit 自动放行」那段承诺。
set -u

# Isolate global git config: these tests cover gate.ps1 logic, not the hooks
# this machine happens to have installed (see gate-test.sh header).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
GATE="$APPDATA/reasonix/skills/solo-project-control/scripts/gate.ps1"
HOOK="$APPDATA/reasonix/skills/solo-project-control/scripts/gate-hook.ps1"
BASE=$(mktemp -d)
MISMATCH=0

mkfiles() {  # $1 目录 —— 6 个骨架文件（含 CHANGELOG.md，缺一不可）
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
  cat > "$d/docs/CHANGELOG.md" <<'EOF'
# 变更记录

> 由 git log 自动生成，勿手改。
EOF
}

gitinit() {  # $1 目录 —— git init 且配好身份，供后续提交用
  ( cd "$1" && git init -q . && git config core.autocrlf false \
    && git config user.name t && git config user.email t@t )
}

run_case() {  # $1 名称 $2 期望退出码 $3 目录 $4 额外参数
  local name="$1" exp="$2" d="$3" extra="${4:-}" act
  if [ -n "$extra" ]; then
    ( cd "$d" && powershell -NoProfile -File "$GATE" "$extra" ) >/dev/null 2>&1; act=$?
  else
    ( cd "$d" && powershell -NoProfile -File "$GATE" ) >/dev/null 2>&1; act=$?
  fi
  if [ "$act" = "$exp" ]; then
    printf '  [一致] %-52s 期望=%s 实际=%s\n' "$name" "$exp" "$act"
  else
    MISMATCH=$((MISMATCH+1))
    printf '  [不符] %-52s 期望=%s 实际=%s  <<<\n' "$name" "$exp" "$act"
  fi
}

echo "=== 第九轮：起项目那次 commit（骨架首次进仓库 · 三种起手）==="

echo "--- 放行 ---"
mkfiles "$BASE/i01"; gitinit "$BASE/i01"
run_case "空仓库 + 骨架齐全 → 放行" 0 "$BASE/i01"

# 放行不能只是「静悄悄退 0」：人得能从输出里看出为什么放行。
# 否则下次门禁报红时，没人分得清「首次放行」和「检查被漏掉」。
out=$( cd "$BASE/i01" && powershell -NoProfile -File "$GATE" 2>&1 ); act=$?
if [ "$act" = "0" ] && echo "$out" | grep -aq '起项目那次'; then
  printf '  [一致] %-52s 输出写明了放行理由\n' "起项目那次：理由可见"
else
  MISMATCH=$((MISMATCH+1))
  printf '  [不符] %-52s 期望=0 且输出含「起项目那次」\n' "起项目那次：理由可见"
fi

mkfiles "$BASE/i02"; gitinit "$BASE/i02"
run_case "空仓库 + -AllowNoTicket → 仍放行（不冲突）" 0 "$BASE/i02" "-AllowNoTicket"

echo "--- 不放行 ---"
mkfiles "$BASE/i03"; rm -f "$BASE/i03/docs/STATUS.md"; gitinit "$BASE/i03"
run_case "空仓库 + 缺 STATUS.md → 拦（第 1 项不放行）" 1 "$BASE/i03"

mkfiles "$BASE/i04"; rm -f "$BASE/i04/docs/CHANGELOG.md"; gitinit "$BASE/i04"
run_case "空仓库 + 缺 CHANGELOG.md → 拦" 1 "$BASE/i04"

# 放行不是长期免检牌：起项目那次之后，$firstCommit 变为 false，
# 第 6 项照常逐行比对 CHANGELOG —— 未刷新就拦下。
# （第一条 commit 是「骨架首次进仓库」，走完整流程刷好 CHANGELOG；再提交第二条时不刷。）
mkfiles "$BASE/i05"; gitinit "$BASE/i05"
( cd "$BASE/i05" && git add -A && git commit -q -m "新增 建 git 仓库与骨架" \
  && { echo '# 变更记录'; echo; echo '> 由 git log 自动生成，勿手改。'; echo; \
       git log --pretty=format:'- %ad  %s' --date=format:'%Y-%m-%d %H:%M'; } > docs/CHANGELOG.md \
  && git add docs/CHANGELOG.md && git commit -q --amend --no-edit ) 2>/dev/null
( cd "$BASE/i05" && echo y >> docs/DECISIONS.md && git add -A && git commit -q -m "调整 补一条决策" ) 2>/dev/null
run_case "起项目那次之后 + 未刷 CHANGELOG → 第 6 项拦下" 1 "$BASE/i05" "-AllowNoTicket"

# 半路接入、早就有 git 历史：**骨架首次进仓库后的下一条提交不该再被放行**。
# 构造：老项目先提交业务代码（不含骨架）→ 骨架入库（起项目那次，放行）→ 再提交一条。
# 第三条若还被放行，说明判定没落对（第 5 项本该报「没带票号」）。
mkdir -p "$BASE/i06"; gitinit "$BASE/i06"
( cd "$BASE/i06" && echo x > README.md && git add -A && git commit -q -m "老项目先立仓库" ) 2>/dev/null
mkfiles "$BASE/i06"
( cd "$BASE/i06" && git add -A && git commit -q -m "新增 接入个人项目管控流程：建骨架" \
  && { echo '# 变更记录'; echo; echo '> 由 git log 自动生成，勿手改。'; echo; \
       git log --pretty=format:'- %ad  %s' --date=format:'%Y-%m-%d %H:%M'; } > docs/CHANGELOG.md \
  && git add docs/CHANGELOG.md && git commit -q --amend --no-edit ) 2>/dev/null
run_case "老项目接入那次（骨架入库）→ 放行" 0 "$BASE/i06"
( cd "$BASE/i06" && echo y >> docs/DECISIONS.md && git add -A && git commit -q -m "调整 补一条决策" \
  && { echo '# 变更记录'; echo; echo '> 由 git log 自动生成，勿手改。'; echo; \
       git log --pretty=format:'- %ad  %s' --date=format:'%Y-%m-%d %H:%M'; } > docs/CHANGELOG.md \
  && git add docs/CHANGELOG.md && git commit -q --amend --no-edit ) 2>/dev/null
run_case "接入之后的提交（无票号）→ 拦下" 1 "$BASE/i06"

echo "--- 起项目那次不挂票号 ---"
# 起项目那次的定位是「跳过切票 / 判据 / 验收整条流程」——它无票可挂。
# 挂了票号，等于凭空多出一张「已交付」的票，第 9 项（票擦它不擦）随后就会报红。
# 这两条锁的正是「提交之后」人工跑门禁时看到的结果（$initialCommit 已为 false）。
mkfiles "$BASE/i08"; gitinit "$BASE/i08"
( cd "$BASE/i08" && git add -A && git commit -q -m "新增 建 git 仓库、骨架文件与门禁" ) 2>/dev/null
run_case "起项目那次不挂票号 → 放行（第 5 / 9 项）" 0 "$BASE/i08"

mkfiles "$BASE/i08b"; gitinit "$BASE/i08b"
( cd "$BASE/i08b" && git add -A \
  && git commit -q -m "新增 建 git 仓库、骨架文件与门禁" -m "追溯：T-001" ) 2>/dev/null
# 挂票号 → 那个票号进了「已交付」集合 → 第 3 项要求它有判据小节，而它没有 → 拦下。
# 这正是「不挂」的落地：起项目那次无票可挂，挂了就是凭空造一张没闭环的票。
run_case "起项目那次挂了票号 → 拦下" 1 "$BASE/i08b"
out8b=$( cd "$BASE/i08b" && powershell -NoProfile -File "$GATE" 2>&1 )
# 两处输出分工：第 5 项点明「起项目那次不该挂票号」，第 3 项点明后果
# （那个票号被算成已交付，却没有判据小节）。
if echo "$out8b" | grep -aq '起项目那次不挂票号' && echo "$out8b" | grep -aq '找不到判据小节'; then
  printf '  [一致] %-52s 第 5 项点原因、第 3 项点后果\n' "挂票号的起项目那次：报错可定位"
else
  MISMATCH=$((MISMATCH+1))
  printf '  [不符] %-52s 期望同时含「起项目那次不挂票号」与「找不到判据小节」\n' "挂票号的起项目那次：报错可定位"
fi

echo "--- hook 端到端 ---"
run_hook() {  # $1 目录 $2 命令文本
  local d="$1" cmd="$2" w
  w=$(cygpath -w "$d" | sed 's/\\/\\\\/g')     # payload 里的路径必须是双反斜杠
  printf '{"hook_event_name":"PreToolUse","tool_name":"bash","tool_input":{"command":"%s","cwd":"%s"}}' \
    "$cmd" "$w" | powershell -NoProfile -File "$HOOK" >/dev/null 2>&1
}
mkfiles "$BASE/i07"; gitinit "$BASE/i07"
run_hook "$BASE/i07" 'git commit -m "初始化仓库"'; act=$?
if [ "$act" = "0" ]; then
  printf '  [一致] %-52s 期望=0 实际=%s\n' "首次提交经 hook → 放行" "$act"
else
  MISMATCH=$((MISMATCH+1))
  printf '  [不符] %-52s 期望=0 实际=%s  <<<\n' "首次提交经 hook → 放行" "$act"
fi

echo
echo "=== 不符项：$MISMATCH / 10 ==="
rm -rf "$BASE"
[ "$MISMATCH" -eq 0 ]
