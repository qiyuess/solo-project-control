# solo-project-control

个人项目管控流程（一人版）——给「一个人 + AI 写代码」的中长期项目用的轻量项目管控 **skill**。

> 核心思想：**能交给机器的，绝不写成要人手动维护的文档** ——
> 承诺变成测试、状态变成 git 的事实、上下文放进 AI 自动加载的 `AGENTS.md`。

## 解决什么问题

一人 + AI 长期写代码，最容易丢三样东西：**上下文丢失、决策漂移、没人催**。
常见对策是「多写文档」，结果文档越多越没人看、还互相矛盾。这套流程反着来。

## 仓库结构

| 路径 | 是什么 |
|---|---|
| `SKILL.md` | 规矩的唯一出处（给 agent 读；含六个骨架文件模板、subagent 预跑开场白） |
| `scripts/gate.ps1` | 流程门禁：**十项**确定性检查，只答「流程有没有被跳步」 |
| `scripts/gate-hook.ps1` | PreToolUse hook：把「记得跑门禁」硬化成「跑不过就 commit 不了」 |
| `tests/` | 8 套回归用例，锁住门禁行为（防门禁自己出 bug 给假绿灯） |

## 十项门禁（gate.ps1）

1. 骨架文件齐全（AGENTS / PLAN / STATUS / 验收判据 / DECISIONS / CHANGELOG）
2. PLAN「变更记录」已回写（表非空；改了 PLAN 就必追一行）
3. 每张票都有判据留档（在飞 + 已交付；空小节不算；不得重复留两份）
4. 在飞票数 ≤ 1（串行，一次只推进一张）
5. 最新 commit 带「追溯：T-票号」
6. CHANGELOG 与 git log 逐行一致
7. 判据标注的测试文件真实存在
8. 最新 commit 前缀合规（新增 / 修复 / 调整 / 验证 / 验收）
9. 最新 commit 的票已擦出台账
10. 一票一条 commit

## 用法

**跑流程门禁**（在项目根目录）：

```bash
powershell -NoProfile -File "$APPDATA/reasonix/skills/solo-project-control/scripts/gate.ps1"
```

**门禁自测**（改过门禁 / hook 之后跑，防假绿灯）：

```bash
bash "$APPDATA/reasonix/skills/solo-project-control/tests/run-all.sh"
```

**挂 hook**（把「记得跑」变成「跑不过就跑不了」）：在 Reasonix 的 `settings.json`
（全局，或项目 `.reasonix/settings.json`）加：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "match": "bash",
        "command": "powershell -NoProfile -File \"C:/Users/<你>/AppData/Roaming/reasonix/skills/solo-project-control/scripts/gate-hook.ps1\"",
        "timeoutMillis": 60000
      }
    ]
  }
}
```

## 每张票的闭环

```
判据先写 → coding
  → ① 开发侧自检（A 组测试 + 两道门禁）
  → ② subagent 干净上下文预跑（B 组）
  → ③ 你人工复测定案
  → ④ 一次 commit（沉淀测试 + 擦票 + 刷 CHANGELOG）
一次只推进一张，闭环了才切下一张。
```

## 四条红线

1. 判据先写，不动摇
2. 验收 = 自检 → subagent 预跑 → 你复测定案才 commit
3. 唯一出处：一件事只写一处
4. 需求新增 / 变动必回写 PLAN

---

规矩的唯一出处是 `SKILL.md`。本 README 是导读，冲突以 `SKILL.md` 为准。
