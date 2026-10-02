#!/usr/bin/env bash
# gate.ps1 本机模拟测试：正例 / 反例 / 边界
# 期望值 = 按 SKILL.md 的描述，gate 应当给出的退出码
set -u

# ★ 隔离本机全局 git 配置。
# 本文件测的是 gate.ps1 的**判定逻辑**，不是「这台机器装了什么」。
# 装了全局 core.hooksPath（skill 的 githooks/pre-commit）之后，下面造数据用的
# git commit 会被那道 hook 拦下（测试的 mkfiles 故意先不铺 CHANGELOG.md，好让
# refresh 在提交后生成——这在 hook 眼里就是「骨架不全」），整套用例集体失真、
# 全变成「期望 0 实际 1」。屏蔽全局/系统配置后，造数据只受本文件控制。
# git hook 本身另有 gate-test10.sh 专门测（那里用 -c core.hooksPath= 显式指定，
# 命令行级优先级最高，不受这里影响）。
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

GATE="$APPDATA/reasonix/skills/solo-project-control/scripts/gate.ps1"
BASE=$(mktemp -d)
MISMATCHES=0

refresh() {  # 与 skill 文档给出的刷新命令一字不差
  { echo '# 变更记录'; echo; echo '> 由 git log 自动生成，勿手改。'; echo; git log --pretty=format:'- %ad  %s' --date=format:'%Y-%m-%d %H:%M'; } > docs/CHANGELOG.md
}

mkfiles() {  # 只铺 6 个骨架文件
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

mkbase() {  # 一个「应当全过」的基线仓库
  local d="$1"; mkfiles "$d"
  # ★ 分两条提交，别合成一条：
  #   第 1 条 = 起项目那次（骨架**首次**进仓库，不挂票号）——门禁对它整段放行；
  #   第 2 条 = 普通票提交，把 HEAD 推离「引入骨架」的那次。
  # 合成一条的话，HEAD 本身就是「引入骨架」的那次提交 → 下面每条用例都会被
  # 「起项目放行」豁免掉，整文件的检查全部失守（表现为大量「期望 1 实际 0」）。
  ( cd "$d" && git init -q . && git config core.autocrlf false && git config user.name t && git config user.email t@t \
    && git add -A && git commit -q -m "新增 建 git 仓库与骨架" \
    && refresh && git add docs/CHANGELOG.md && git commit -q --amend --no-edit )
  ( cd "$d" && printf '\n## 2026-10-01 基线\n' >> docs/DECISIONS.md && git add -A \
    && git commit -q -m "新增 基线票" -m "追溯：T-12" \
    && refresh && git add docs/CHANGELOG.md && git commit -q --amend --no-edit )
}

addcommit() {  # $1 dir $2 subject $3 body —— 新提交并同步刷 CHANGELOG
  local d="$1"
  ( cd "$d" && git commit -q --allow-empty -m "$2" -m "$3" \
    && refresh && git add docs/CHANGELOG.md && git commit -q --amend --no-edit )
}

run_case() {  # $1 名称 $2 期望退出码 $3 目录 $4 额外参数
  local name="$1" exp="$2" d="$3" extra="${4:-}"
  local out act
  if [ -n "$extra" ]; then
    out=$( cd "$d" && powershell -NoProfile -File "$GATE" "$extra" 2>&1 ); act=$?
  else
    out=$( cd "$d" && powershell -NoProfile -File "$GATE" 2>&1 ); act=$?
  fi
  if [ "$act" = "$exp" ]; then
    printf '  [一致] %-46s 期望=%s 实际=%s\n' "$name" "$exp" "$act"
  else
    MISMATCHES=$((MISMATCHES+1))
    printf '  [不符] %-46s 期望=%s 实际=%s  <<<\n' "$name" "$exp" "$act"
    echo "$out" | grep -a '\[FAIL\]' | sed 's/^/           /'
  fi
}

PSV=$(powershell -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null | tr -d '\r')
echo "=== gate.ps1 本机测试（powershell $PSV）==="
echo "--- 基线 ---"
mkbase "$BASE/c01"; run_case "基线：一切正确" 0 "$BASE/c01"

echo "--- 第 3 项：票号匹配 ---"
mkbase "$BASE/c02"; printf '| T-1 | 某票 | 在干 | 复测 |\n' >> "$BASE/c02/docs/STATUS.md"
run_case "在飞 T-1，判据只有 T-12（应报缺）" 1 "$BASE/c02"
mkbase "$BASE/c03"; printf '| T-1 | 某票 | 在干 | 复测 |\n' >> "$BASE/c03/docs/STATUS.md"
printf '\n# 验收判据：T-1 · 另一票\n| 1 | 另一条判据 | 推导 |\n' >> "$BASE/c03/docs/验收判据.md"
run_case "在飞 T-1，判据有 T-1 + T-12" 0 "$BASE/c03"
mkbase "$BASE/c04"; printf '| T-2 | 某票 | 在干 | 复测 |\n' >> "$BASE/c04/docs/STATUS.md"
printf '\n# 验收判据：T-20 · 二十号票\n' >> "$BASE/c04/docs/验收判据.md"
run_case "在飞 T-2，判据只有 T-20（应报缺）" 1 "$BASE/c04"

echo "--- 第 3 项：编码敏感 ---"
mkbase "$BASE/c05"
{ printf '\xEF\xBB\xBF'; cat "$BASE/c05/docs/验收判据.md"; } > /tmp/p.$$ && mv /tmp/p.$$ "$BASE/c05/docs/验收判据.md"
run_case "判据带 BOM（标题含「验收判据」）" 0 "$BASE/c05"
mkbase "$BASE/c23"
sed -i '1s/.*/## T-12 · 基线票（标题不含验收判据字样）/' "$BASE/c23/docs/验收判据.md"
run_case "标题不含「验收判据」字样，无 BOM" 0 "$BASE/c23"
mkbase "$BASE/c24"
sed -i '1s/.*/## T-12 · 基线票（标题不含验收判据字样）/' "$BASE/c24/docs/验收判据.md"
{ printf '\xEF\xBB\xBF'; cat "$BASE/c24/docs/验收判据.md"; } > /tmp/s.$$ && mv /tmp/s.$$ "$BASE/c24/docs/验收判据.md"
run_case "标题不含「验收判据」字样 + 带 BOM" 0 "$BASE/c24"

echo "--- 第 6 项：CHANGELOG ---"
mkbase "$BASE/c06"; sed -i 's/基线票/被改过的票/' "$BASE/c06/docs/CHANGELOG.md"
run_case "CHANGELOG 被手改一个字（应报）" 1 "$BASE/c06"
mkbase "$BASE/c07"; sed -i '$d' "$BASE/c07/docs/CHANGELOG.md"
run_case "CHANGELOG 刷漏一条（应报）" 1 "$BASE/c07"
mkbase "$BASE/c08"; printf '\n\n' >> "$BASE/c08/docs/CHANGELOG.md"
run_case "CHANGELOG 多出尾随空行" 0 "$BASE/c08"
mkbase "$BASE/c09"; printf '%s' "$(cat "$BASE/c09/docs/CHANGELOG.md")" > /tmp/q.$$ && mv /tmp/q.$$ "$BASE/c09/docs/CHANGELOG.md"
run_case "CHANGELOG 无尾随换行" 0 "$BASE/c09"
mkbase "$BASE/c10"; sed -i 's/$/\r/' "$BASE/c10/docs/CHANGELOG.md"
run_case "CHANGELOG 是 CRLF 行尾" 0 "$BASE/c10"
mkbase "$BASE/c11"
{ printf '\xEF\xBB\xBF'; cat "$BASE/c11/docs/CHANGELOG.md"; } > /tmp/r.$$ && mv /tmp/r.$$ "$BASE/c11/docs/CHANGELOG.md"
run_case "CHANGELOG 带 UTF-8 BOM" 0 "$BASE/c11"

echo "--- 第 2 / 4 项 ---"
mkbase "$BASE/c12"; sed -i '/| 2026-10-01 | 建项目 | 起手 |/d' "$BASE/c12/docs/PLAN.md"
run_case "PLAN 变更记录表为空（应报）" 1 "$BASE/c12"
mkbase "$BASE/c13"
printf '| T-003 | 单据页签切走再切回不丢内容 | 预跑过·待你复测 | 你人工复测后一次 commit |\n' >> "$BASE/c13/docs/STATUS.md"
printf '| T-12 | 真在飞的票 | 在干 | 写判据 |\n' >> "$BASE/c13/docs/STATUS.md"
printf '\n# 验收判据：T-003 · 示例票\n| 1 | 示例判据 | 推导 |\n' >> "$BASE/c13/docs/验收判据.md"
run_case "台账留模板示例行 + 1 张真票（在飞=2）" 1 "$BASE/c13"
mkbase "$BASE/c20"
printf '| T-003 | 单据页签切走再切回不丢内容 | 预跑过·待你复测 | 你人工复测后一次 commit |\n' >> "$BASE/c20/docs/STATUS.md"
run_case "台账只有模板示例行、无对应判据" 1 "$BASE/c20"
mkbase "$BASE/c21"
addcommit "$BASE/c21" "修复 某处问题" "追溯：T-21
顺带修掉 T-2 遗留的边界"
printf '\n# 验收判据：T-21 · 顺带提及票\n| 1 | 判据 | 推导 |\n' >> "$BASE/c21/docs/验收判据.md"
run_case "body 顺带提到别的票号 T-2（不算声明，不该牵连）" 0 "$BASE/c21"

echo "--- 第 5 项：票号 ---"
mkbase "$BASE/c14"; addcommit "$BASE/c14" "调整 流程维护类改动" "无票号提交"
run_case "最新 commit 无票号（应报）" 1 "$BASE/c14"
mkbase "$BASE/c15"; addcommit "$BASE/c15" "调整 流程维护类改动" "无票号提交"
run_case "最新 commit 无票号 + -AllowNoTicket" 0 "$BASE/c15" "-AllowNoTicket"
# 票号各自唯一：第 10 项（一票一条 commit）不允许同一票号出现在两条 commit 里
mkbase "$BASE/c16"; addcommit "$BASE/c16" "调整 半角冒号票号" "追溯:T-16"
printf '\n# 验收判据：T-16 · 半角冒号票\n| 1 | 判据 | 推导 |\n' >> "$BASE/c16/docs/验收判据.md"
run_case "票号用半角冒号 追溯:T-16" 0 "$BASE/c16"
mkbase "$BASE/c17"; addcommit "$BASE/c17" "调整 导出名改「标题-日期」含 | 与 100% 与 %s" "追溯：T-17"
printf '\n# 验收判据：T-17 · 特殊字符票\n| 1 | 判据 | 推导 |\n' >> "$BASE/c17/docs/验收判据.md"
run_case "subject 含 | % %s 等特殊字符" 0 "$BASE/c17"

echo "--- 流程维护提交 ---"
mkbase "$BASE/c22"
( cd "$BASE/c22" && git commit -q --allow-empty -m "调整 流程维护类改动" -m "无票号提交" )
run_case "无票号 + -AllowNoTicket 但没刷 CHANGELOG" 1 "$BASE/c22" "-AllowNoTicket"

echo "--- 全局 ---"
mkfiles "$BASE/c18"; ( cd "$BASE/c18" && git init -q . )
run_case "git 仓库但一条 commit 都没有" 1 "$BASE/c18"

# 空仓库除了退出码要对，还不能崩：应当打印完整检查列表，而不是一段 PowerShell 错误栈。
# （PS 5.1 会把 git 的 stderr 当终止性错误抛出——那正是这条用例守的东西。）
out18=$( cd "$BASE/c18" && powershell -NoProfile -File "$GATE" 2>&1 ); act18=$?
if echo "$out18" | grep -aq 'NativeCommandError'; then
  MISMATCHES=$((MISMATCHES+1)); printf '  [不符] %-46s 输出里有 NativeCommandError  <<<\n' "空仓库：不该抛 PowerShell 错误"
elif [ "$act18" = "1" ] && echo "$out18" | grep -aq '\[ OK \]' && echo "$out18" | grep -aq '\[FAIL\]' && echo "$out18" | grep -aq '=== '; then
  printf '  [一致] %-46s 退出码=%s 且打印了完整检查列表\n' "空仓库：优雅报错（不崩）" "$act18"
else
  MISMATCHES=$((MISMATCHES+1)); printf '  [不符] %-46s 期望=1 且含检查列表，实际=%s  <<<\n' "空仓库：优雅报错（不崩）" "$act18"
  echo "$out18" | head -6 | sed 's/^/           /'
fi

mkfiles "$BASE/c19"
run_case "根本不是 git 仓库（应直接退 1）" 1 "$BASE/c19"

echo
echo "=== 不符项：$MISMATCHES / 25 ==="
rm -rf "$BASE"
[ "$MISMATCHES" -eq 0 ]
