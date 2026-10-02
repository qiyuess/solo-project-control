#!/usr/bin/env bash
# 第十轮：本轮新增的两项能力。
#
#  A. 第 9 项改成不变量之后的行为（原来只看「最新那条 commit」）
#     原来的洞：漏擦票在交付时会被抓到，但**再提交一条不带票号的提交**
#     （流程维护类）就把它挤出视野，从此没人查——而「票擦它不擦」正是靠这一项守的。
#     不变量 = 台账里的票号一旦出现在**任何**历史 commit 的追溯行里，就报。
#
#  B. githooks/pre-commit 端到端（绕不过的底层拦截）
#     Reasonix hook 只看命令文本，`GIT=git; $GIT commit` 就能绕；
#     git hook 由 git 自己调用，写法无关。这里锁住它的四个边界：
#     违规拦、合规放、非本项目不干扰、--no-verify 是逃生口。
set -u

# Isolate global git config. This file's hook cases pass core.hooksPath EXPLICITLY
# (-c core.hooksPath="$HOOKS"), which outranks every config file -- so the hook
# still gets exercised. Isolating only stops the ambient machine-wide hooksPath
# from interfering with the data-building commits below (test outcome must not
# depend on what this machine happens to have installed).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
GATE="$APPDATA/reasonix/skills/solo-project-control/scripts/gate.ps1"
HOOKS="$APPDATA/reasonix/skills/solo-project-control/githooks"
BASE=$(mktemp -d)
MISMATCH=0

# 铺 6 个骨架文件（判据文件非空：没有票号时第 3 项直接跳过）
mkfiles() {
  local d="$1"; mkdir -p "$d/docs"
  printf '# 项目\n## 代码 / 操作在哪\n- 跑代码门禁：echo ok\n' > "$d/AGENTS.md"
  printf '# PLAN\n## 变更记录\n| 日期 | 变更 | 原因 |\n|---|---|---|\n| 2026-10-01 | 建项目 | 起手 |\n' > "$d/docs/PLAN.md"
  printf '# STATUS\n| 票 | 一句话 | 状态 | 下一步 |\n|---|---|---|---|\n' > "$d/docs/STATUS.md"
  printf '# 验收判据\n（还没有票）\n' > "$d/docs/验收判据.md"
  printf '# DECISIONS\n## 2026-10-01 选 A\n- 选的：A\n' > "$d/docs/DECISIONS.md"
  printf '# 变更记录\n\n> 由 git log 自动生成，勿手改。\n' > "$d/docs/CHANGELOG.md"
}

gi() { ( cd "$1" && git init -q . && git config core.autocrlf false \
    && git config user.name t && git config user.email t@t ) 2>/dev/null; }

refresh() { ( cd "$1" && { echo '# 变更记录'; echo; echo '> 由 git log 自动生成，勿手改。'; echo; \
    git log --pretty=format:'- %ad  %s' --date=format:'%Y-%m-%d %H:%M'; } > docs/CHANGELOG.md ); }

# 建一个「已有一条基线提交」的仓库，之后所有提交都不是首次 commit，
# 免得撞上「首次 commit 自动放行」——那会让下面每条用例都失去意义。
mkbase() {
  local d="$1"; mkfiles "$d"; gi "$d"
  ( cd "$d" && git add -A && git commit -q -m "新增 建 git 仓库与骨架" ) 2>/dev/null
  refresh "$d"
  ( cd "$d" && git add docs/CHANGELOG.md \
    && SPC_GATE_ARGS=-AllowNoTicket git -c core.hooksPath="$HOOKS" commit -q --amend --no-edit ) 2>/dev/null
}

run_case() {  # $1 名称 $2 期望 $3 目录
  local name="$1" exp="$2" d="$3" act
  ( cd "$d" && powershell -NoProfile -File "$GATE" ) >/dev/null 2>&1; act=$?
  if [ "$act" = "$exp" ]; then
    printf '  [一致] %-54s 期望=%s 实际=%s\n' "$name" "$exp" "$act"
  else
    MISMATCH=$((MISMATCH+1))
    printf '  [不符] %-54s 期望=%s 实际=%s  <<<\n' "$name" "$exp" "$act"
  fi
}

echo "=== 第十轮：第 9 项不变量 + githooks 端到端 ==="

echo "--- A. 第 9 项：漏擦票不该被后续提交掩盖 ---"
# a1：交付了票但没擦，立刻跑 → 报
mkbase "$BASE/a1"
printf '| T-007 | 某票 | 在干 | x |\n' >> "$BASE/a1/docs/STATUS.md"
printf '\n# 验收判据：T-007 · 某票\n【A 组】\n| # | 判据 | 来源 |\n|---|---|---|\n| 1 | x | 推导 |\n' >> "$BASE/a1/docs/验收判据.md"
( cd "$BASE/a1" && git add -A && git commit -q -m "新增 某票交付" -m "追溯：T-007" ) 2>/dev/null
refresh "$BASE/a1"; ( cd "$BASE/a1" && git add docs/CHANGELOG.md \
  && SPC_GATE_ARGS=-AllowNoTicket git -c core.hooksPath="$HOOKS" commit -q --amend --no-edit ) 2>/dev/null
run_case "交付后未擦票 → 报" 1 "$BASE/a1"

# a2（★ 本轮修复的核心）：再提交一条不带票号的维护提交，仍应报
printf '## 2026-10-02 补一条\n' >> "$BASE/a1/docs/DECISIONS.md"
( cd "$BASE/a1" && git add -A && git commit -q -m "调整 补一条决策" ) 2>/dev/null
refresh "$BASE/a1"; ( cd "$BASE/a1" && git add docs/CHANGELOG.md \
  && SPC_GATE_ARGS=-AllowNoTicket git -c core.hooksPath="$HOOKS" commit -q --amend --no-edit ) 2>/dev/null
run_case "再提交一条维护提交后 → 仍报（原来会变绿）" 1 "$BASE/a1"

# a3：真去擦票了 → 第 9 项不再报
# ★ 擦票这次提交**不再挂 T-007**：票在交付那条 commit 里已经声明过，再声明一次
#   会被第 10 项（一票一条）抓成「同一张票提交了两次」。
#   而不挂票号 → 第 5 项会报 → 所以要带 -AllowNoTicket。
#   于是「漏擦票的补救」本身就是一次不带票号的提交，这属于 -AllowNoTicket 的适用范围
#   （语义 = 不属于任何票的提交，补救性擦票也算）。这里只断言**第 9 项**已恢复。
sed -i '/T-007/d' "$BASE/a1/docs/STATUS.md"
( cd "$BASE/a1" && git add -A && git commit -q -m "调整 擦掉已交付的 T-007" ) 2>/dev/null
refresh "$BASE/a1"; ( cd "$BASE/a1" && git add docs/CHANGELOG.md \
  && SPC_GATE_ARGS=-AllowNoTicket git -c core.hooksPath="$HOOKS" commit -q --amend --no-edit ) 2>/dev/null
out_a3=$( cd "$BASE/a1" && powershell -NoProfile -File "$GATE" 2>&1 )
if echo "$out_a3" | grep -aq '\[ OK \] 9\. 台账里的票没被交付过'; then
  printf '  [一致] %-54s 第 9 项已恢复 OK\n' "擦票后 → 第 9 项不再报"
else
  MISMATCH=$((MISMATCH+1))
  printf '  [不符] %-54s 期望第 9 项 OK  <<<\n' "擦票后 → 第 9 项不再报"
  echo "$out_a3" | grep -a '\[FAIL\]' | sed 's/^/           /'
fi

echo "--- B. githooks/pre-commit 端到端 ---"
# b1：违规仓库（台账两张在飞票）→ 提交必须被拒
mkbase "$BASE/b1"
printf '| T-1 | 甲 | 在干 | x |\n| T-2 | 乙 | 在干 | y |\n' >> "$BASE/b1/docs/STATUS.md"
( cd "$BASE/b1" && git add -A && git -c core.hooksPath="$HOOKS" commit -q -m "调整 加两张票" ) 2>/dev/null
rc=$?
if [ "$rc" -ne 0 ]; then
  printf '  [一致] %-54s git 退出码=%s（拒绝）\n' "违规仓库经 git hook → 拒绝" "$rc"
else
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-54s 期望非 0，实际=%s  <<<\n' "违规仓库经 git hook → 拒绝" "$rc"
fi

# b2：合规仓库首次提交 → 放行（hook 不误拦）
mkfiles "$BASE/b2"; gi "$BASE/b2"
( cd "$BASE/b2" && git add -A && git -c core.hooksPath="$HOOKS" commit -q -m "新增 建 git 仓库与骨架" ) 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  printf '  [一致] %-54s git 退出码=%s（放行）\n' "合规仓库首次提交 → 放行" "$rc"
else
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-54s 期望 0，实际=%s  <<<\n' "合规仓库首次提交 → 放行" "$rc"
fi

# b3：非本项目（没有 docs/PLAN.md）→ 放行，不干扰别的仓库
mkdir -p "$BASE/b3"; gi "$BASE/b3"; echo x > "$BASE/b3/f.txt"
( cd "$BASE/b3" && git add -A && git -c core.hooksPath="$HOOKS" commit -q -m "随便提交" ) 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  printf '  [一致] %-54s git 退出码=%s（放行）\n' "非本项目（无 docs/PLAN.md）→ 放行" "$rc"
else
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-54s 期望 0，实际=%s  <<<\n' "非本项目（无 docs/PLAN.md）→ 放行" "$rc"
fi

# b4：--no-verify 是逃生口（门禁自己坏了时的路）
mkbase "$BASE/b4"
printf '| T-1 | 甲 | 在干 | x |\n| T-2 | 乙 | 在干 | y |\n' >> "$BASE/b4/docs/STATUS.md"
( cd "$BASE/b4" && git add -A && git -c core.hooksPath="$HOOKS" commit -q --no-verify -m "绕过" ) 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  printf '  [一致] %-54s git 退出码=%s（放行）\n' "--no-verify 逃生口 → 放行" "$rc"
else
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-54s 期望 0，实际=%s  <<<\n' "--no-verify 逃生口 → 放行" "$rc"
fi

# b5：SPC_GATE_ARGS 透传 —— 流程维护类提交带 -AllowNoTicket
#     ★ 必须用「有 2 条以上 commit、且最新那条不挂票号」的仓库：mkbase 只建 1 条，
#       那是首次 commit 场景，第 5 项本来就放行，测不出透传有没有生效。
mkbase "$BASE/b5"
( cd "$BASE/b5" && echo y >> docs/DECISIONS.md && git add -A \
  && git commit -q -m "调整 补一条决策" ) 2>/dev/null
refresh "$BASE/b5"; ( cd "$BASE/b5" && git add docs/CHANGELOG.md \
  && SPC_GATE_ARGS=-AllowNoTicket git -c core.hooksPath="$HOOKS" commit -q --amend --no-edit ) 2>/dev/null
( cd "$BASE/b5" && echo z >> docs/DECISIONS.md && git add -A ) 2>/dev/null
( cd "$BASE/b5" && git -c core.hooksPath="$HOOKS" commit -q --amend --no-edit ) 2>/dev/null
rc=$?
if [ "$rc" -ne 0 ]; then
  printf '  [一致] %-54s git 退出码=%s（拒绝）\n' "维护提交不带 -AllowNoTicket → 拒绝" "$rc"
else
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-54s 期望非 0，实际=%s  <<<\n' "维护提交不带 -AllowNoTicket → 拒绝" "$rc"
fi
( cd "$BASE/b5" && SPC_GATE_ARGS=-AllowNoTicket git -c core.hooksPath="$HOOKS" commit -q --amend --no-edit ) 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  printf '  [一致] %-54s git 退出码=%s（放行）\n' "SPC_GATE_ARGS 透传 -AllowNoTicket → 放行" "$rc"
else
  MISMATCH=$((MISMATCH+1)); printf '  [不符] %-54s 期望 0，实际=%s  <<<\n' "SPC_GATE_ARGS 透传 -AllowNoTicket → 放行" "$rc"
fi

echo "--- C. 三种起手：骨架建好就能 commit 一次立起仓库 ---"
# 起项目那次判定 = 「骨架**首次**进这个仓库的那一次提交」，与仓库有没有历史无关。
# 三种起手都该被放行（新项目 / 从未做过 git 的接入 / **早就有 git 历史的接入**）。
# 门禁跑在 commit 前后各一次，两边都要判得准（-PreCommit 看暂存区，否则看 HEAD）。

# c1：新项目 —— git init 后第一次提交
mkfiles "$BASE/c1"; gi "$BASE/c1"; ( cd "$BASE/c1" && git add -A ) 2>/dev/null
rc=$( cd "$BASE/c1" && powershell -NoProfile -File "$GATE" -PreCommit >/dev/null 2>&1; echo $? )
if [ "$rc" = "0" ]; then printf '  [一致] %-54s 期望=0 实际=%s\n' "新项目：init 后首提 → hook 放行" "$rc"
else MISMATCH=$((MISMATCH+1)); printf '  [不符] %-54s 期望=0 实际=%s  <<<\n' "新项目：init 后首提 → hook 放行" "$rc"; fi

# c2：半路接入，早已有 git 历史 —— 把骨架补进去的那一次提交
#   先让老项目**只有业务代码**（不带骨架）提交一次，再把骨架补进来。
mkdir -p "$BASE/c2"; gi "$BASE/c2"
( cd "$BASE/c2" && echo x > 老文件.txt && git add -A && git commit -q -m "老项目早先的提交" ) 2>/dev/null
mkfiles "$BASE/c2"; ( cd "$BASE/c2" && git add -A ) 2>/dev/null
rc=$( cd "$BASE/c2" && powershell -NoProfile -File "$GATE" -PreCommit >/dev/null 2>&1; echo $? )
if [ "$rc" = "0" ]; then printf '  [一致] %-54s 期望=0 实际=%s\n' "老项目接入：骨架入库 → hook 放行" "$rc"
else MISMATCH=$((MISMATCH+1)); printf '  [不符] %-54s 期望=0 实际=%s  <<<\n' "老项目接入：骨架入库 → hook 放行" "$rc"; fi
( cd "$BASE/c2" && git commit -q -m "新增 接入个人项目管控流程：建骨架" ) 2>/dev/null
rc=$( cd "$BASE/c2" && powershell -NoProfile -File "$GATE" >/dev/null 2>&1; echo $? )
if [ "$rc" = "0" ]; then printf '  [一致] %-54s 期望=0 实际=%s\n' "老项目接入：提交后人工跑 → 放行" "$rc"
else MISMATCH=$((MISMATCH+1)); printf '  [不符] %-54s 期望=0 实际=%s  <<<\n' "老项目接入：提交后人工跑 → 放行" "$rc"; fi

# c3（★ 反例，最关键）：接入完成后，**下一条正常提交**不该被误放行
printf '## 2026-10-02 补一条\n' >> "$BASE/c2/docs/DECISIONS.md"
( cd "$BASE/c2" && git add -A ) 2>/dev/null
rc=$( cd "$BASE/c2" && powershell -NoProfile -File "$GATE" -PreCommit >/dev/null 2>&1; echo $? )
if [ "$rc" = "1" ]; then printf '  [一致] %-54s 期望=1 实际=%s\n' "接入后再提交（无票号）→ 拦下" "$rc"
else MISMATCH=$((MISMATCH+1)); printf '  [不符] %-54s 期望=1 实际=%s  <<<\n' "接入后再提交（无票号）→ 拦下" "$rc"; fi

# c4（反例）：老项目普通改动、没引入骨架 → 不该放行
mkfiles "$BASE/c4"; gi "$BASE/c4"
( cd "$BASE/c4" && echo x > 老文件.txt && git add -A && git commit -q -m "老项目早先的提交" ) 2>/dev/null
( cd "$BASE/c4" && echo y > 新文件.txt && git add -A ) 2>/dev/null
rc=$( cd "$BASE/c4" && powershell -NoProfile -File "$GATE" -PreCommit >/dev/null 2>&1; echo $? )
if [ "$rc" = "1" ]; then printf '  [一致] %-54s 期望=1 实际=%s\n' "老项目普通改动（无骨架）→ 拦下" "$rc"
else MISMATCH=$((MISMATCH+1)); printf '  [不符] %-54s 期望=1 实际=%s  <<<\n' "老项目普通改动（无骨架）→ 拦下" "$rc"; fi

echo
echo "=== 不符项：$MISMATCH / 13 ==="
rm -rf "$BASE"
[ "$MISMATCH" -eq 0 ]
