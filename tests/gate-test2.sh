#!/usr/bin/env bash
# 第二轮：路径 / 行尾 / 长票号 / 参数 —— 上一轮没覆盖的场景
set -u

# Isolate global git config: these tests cover gate.ps1 logic, not the hooks
# this machine happens to have installed (see gate-test.sh header).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
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

run_case() {  # $1 名称 $2 期望 $3 目录 $4 额外参数
  local name="$1" exp="$2" d="$3" extra="${4:-}"
  local out act
  if [ -n "$extra" ]; then
    out=$( cd "$d" && powershell -NoProfile -File "$GATE" $extra 2>&1 ); act=$?
  else
    out=$( cd "$d" && powershell -NoProfile -File "$GATE" 2>&1 ); act=$?
  fi
  if [ "$act" = "$exp" ]; then
    printf '  [一致] %-48s 期望=%s 实际=%s\n' "$name" "$exp" "$act"
  else
    MISMATCH=$((MISMATCH+1))
    printf '  [不符] %-48s 期望=%s 实际=%s  <<<\n' "$name" "$exp" "$act"
    echo "$out" | grep -a '\[FAIL\]' | sed 's/^/           /'
  fi
}

note_case() {  # 只记录实际行为，不判对错
  local name="$1" d="$2" extra="${3:-}"
  local act
  if [ -n "$extra" ]; then
    ( cd "$d" && powershell -NoProfile -File "$GATE" "$extra" >/dev/null 2>&1 ); act=$?
  else
    ( cd "$d" && powershell -NoProfile -File "$GATE" >/dev/null 2>&1 ); act=$?
  fi
  printf '  [记录] %-48s 实际退出码=%s\n' "$name" "$act"
}

echo "=== 第二轮（同样的 powershell 5.1，门禁已修）==="
echo "--- 路径 ---"
mkbase "$BASE/含 空格 的 项目 目录"
run_case "项目路径含空格" 0 "$BASE/含 空格 的 项目 目录"
mkbase "$BASE/中文项目目录"
run_case "项目路径含中文" 0 "$BASE/中文项目目录"

echo "--- 行尾：三个骨架文件全 CRLF ---"
mkbase "$BASE/c03"
for f in docs/STATUS.md docs/PLAN.md docs/验收判据.md; do sed -i 's/$/\r/' "$BASE/c03/$f"; done
b=$(wc -c < "$BASE/c03/docs/STATUS.md"); a=$(tr -d '\r' < "$BASE/c03/docs/STATUS.md" | wc -c)
echo "  （CRLF 生效检查：STATUS.md 现 ${b} 字节，剥掉 CR 后 ${a} 字节）"
run_case "三个骨架文件全 CRLF" 0 "$BASE/c03"

echo "--- 长票号：修复是否对 T-10/T-100 也成立 ---"
mkbase "$BASE/c04"
printf '| T-10 | 十号票 | 在干 | 复测 |\n' >> "$BASE/c04/docs/STATUS.md"
printf '\n# 验收判据：T-100 · 一百号票\n' >> "$BASE/c04/docs/验收判据.md"
run_case "在飞 T-10，判据只有 T-100（应报缺）" 1 "$BASE/c04"
mkbase "$BASE/c05"
printf '| T-10 | 十号票 | 在干 | 复测 |\n' >> "$BASE/c05/docs/STATUS.md"
printf '\n# 验收判据：T-10 · 十号票\n| 1 | 十号判据 | 推导 |\n' >> "$BASE/c05/docs/验收判据.md"
run_case "在飞 T-10，判据有 T-10 + T-12" 0 "$BASE/c05"

echo "--- 参数 ---"
mkbase "$BASE/n02"
printf '| T-1 | 甲票 | 在干 | x |\n| T-2 | 乙票 | 在干 | y |\n' >> "$BASE/n02/docs/STATUS.md"
printf '\n# 验收判据：T-1 · 甲票\n| 1 | 甲判据 | 推导 |\n\n# 验收判据：T-2 · 乙票\n| 1 | 乙判据 | 推导 |\n' >> "$BASE/n02/docs/验收判据.md"
run_case "2 张在飞 + -MaxInFlight 2（放行）" 0 "$BASE/n02" "-MaxInFlight 2"
note_case "2 张在飞，上限用默认 1" "$BASE/n02"

echo "--- 记录型：第 2 项到底能守到什么程度 ---"
mkbase "$BASE/n01"
printf '\n## 功能范围（本轮新增）\n- 临时加一条需求，但没在「变更记录」表追行\n' >> "$BASE/n01/docs/PLAN.md"
note_case "改了 PLAN 需求但没追变更记录行" "$BASE/n01"

echo
echo "=== 不符合项：$MISMATCH / 6 ==="
rm -rf "$BASE"
[ "$MISMATCH" -eq 0 ]
