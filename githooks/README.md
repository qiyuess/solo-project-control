# githooks · 绕不过的 commit 拦截

## 为什么有这一层

skill 里原本只有 **Reasonix 的 PreToolUse hook**（`scripts/gate-hook.ps1`）。它只能看到
「即将执行的命令**文本**」，靠正则判断这是不是一次 `git commit`——因此可以被绕过：

```bash
git commit -m x          # 拦得住
git -c a=b commit -m x   # 拦得住
GIT=git; $GIT commit -m x    # 拦不住（文本里没有连续的 git+commit）
bash -c "git commit -m x"    # 拦不住
```

**git hook 由 git 自己调用**，不管这次提交是 agent、终端、GUI 还是脚本发起的，写法如何
都绕不过。所以这一层是**兜底**，Reasonix hook 那一层是**给 agent 的即时反馈**。

两层分工：

| 层 | 谁触发 | 管什么 | 能不能绕 |
|---|---|---|---|
| Reasonix PreToolUse hook | Reasonix 工具调用前 | agent 侧的提交 | 能（文本匹配） |
| **git hook（本目录）** | **git 提交时** | **任何来源的提交** | **只有 `--no-verify`** |

## 安装（一次，全局）

```bash
git config --global core.hooksPath "$APPDATA/reasonix/skills/solo-project-control/githooks"
```

Windows / PowerShell：

```powershell
git config --global core.hooksPath "$env:APPDATA\reasonix\skills\solo-project-control\githooks"
```

- **只写一处**：`core.hooksPath` 指向 skill，不是把脚本复制到每个项目的 `.git/hooks/`
  ——复制就会各自过期（红线③）。
- **全局生效**：这台机器上**所有**仓库都会跑它。所以脚本自己判断「有没有 `docs/PLAN.md`」：
  不是本流程的项目**直接放行**，不干扰别的仓库。
- 卸载：`git config --global --unset core.hooksPath`。

## 用法

装了之后，提交时自动跑 `scripts/gate.ps1`，违规就**拒绝这次提交**（退出码 1）。

**流程维护类提交**（改约定 / 改门禁，不属任何票）要带 `-AllowNoTicket`，经环境变量透传：

```bash
SPC_GATE_ARGS=-AllowNoTicket git commit -m "调整 改门禁"
```

**逃生口**：`git commit --no-verify` 跳过所有 hook。这是**有意留的**——门禁自己坏了
的时候得有路可走，而不是被逼着去改脚本。

## 它拦不住什么

`--no-verify` 是明面上的口子。此外**它只守「形」**：门禁查的是判据有没有留档、PLAN
有没有回写、票擦没擦——**查不动「这件事做没做对」**。做没做对，仍然只有你人工复测算数。
