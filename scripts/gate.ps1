<#
.SYNOPSIS
    一人项目管控流程的确定性门禁（solo-project-control 配套母版）。

.DESCRIPTION
    只做确定性检查，不判断需求对错。回答一个问题：
    「这套流程现在有没有被跳步、有没有开始漂移？」

    十项检查（全部可「是 / 否」判定，不含主观评价）：
      1. 骨架文件是否齐（AGENTS.md / PLAN / STATUS / 验收判据 / DECISIONS / CHANGELOG）
      2. PLAN 的「变更记录」是否已回写（表非空；且本次 commit 改了 PLAN 就必须追一行）
      3. 每张票（在飞的 + git log 里已交付的）都有判据小节，且小节里有判据内容
         （只有标题的空小节不算留档；同一票号也不得在主文件与归档各留一份）
         ——判据可分散在主文件与 docs/判据归档/*.md
      4. 在飞票数是否 <= 上限（默认 1 = 一次只推进一张）
      5. 最近一次 commit 是否带「追溯：T-票号」
      6. docs/CHANGELOG.md 是否与 git log 逐行一致（同时抓「刷漏了」和「手改了」）
      7. 判据里标注的测试文件是否存在（判据小节里写了「测试：<路径>」才查）
      8. 最新 commit 的 subject 是否以规定前缀开头（新增 / 修复 / 调整 / 验证 / 验收）
      9. 台账里的票没被交付过（不变量）：STATUS.md 里的票号一旦出现在**任何** commit
         的「追溯：」里，就该已擦出台账——还在就是漏擦票。查全部历史而非只看最新一条，
         否则漏擦会被后面一条不带票号的提交挤出视野、从此没人查
     10. 一票一条 commit（同一票号最多出现在 1 条 commit；一条 commit 最多声明 1 个票号）

    第 3 项为什么算上「已交付的票」：票一擦，承诺有没有留档就再没人查了——
    而那恰恰是最需要保证的时刻。

    第 4 项默认 1（只串行、不开并行）：工作区只有一个，两票同时改就没法按票分开提交。

    「首次 commit」自动放行：hook 在 commit 执行之前跑门禁，所以门禁看到的
    「最新 commit」永远是上一条；仓库里一条 commit 都还没有时（git rev-list
    -n 1 --all 无输出），第 2 / 5 / 6 / 8 / 10 项无从上查，自动放行并在输出里
    写明理由。第 1 项（骨架齐全）不放行——骨架建好正是首次提交的前提。
    新项目（git init 后）与半路接入、此前从未做过 git 的项目走同一条判定：
    骨架建好后允许直接 commit 一次，把仓库立起来。

    退出码：0 = 全过；1 = 有违规（清单已打印）。

.PARAMETER AllowNoTicket
    流程维护类提交（改约定 / 改门禁，不属于任何票）专用：放行第 5 项。

.PARAMETER MaxInFlight
    允许同时在飞的票数上限，默认 1（串行）。放宽它等于允许并行——
    而工作区只有一个，两票同时改就没法按票分开提交。

.EXAMPLE
    powershell -NoProfile -File scripts/gate.ps1

.EXAMPLE
    powershell -NoProfile -File scripts/gate.ps1 -AllowNoTicket

.NOTES
    在项目根目录运行。终端请用 UTF-8（Windows Terminal / VS Code / git bash 默认即是）。
    本脚本保存为 UTF-8 with BOM —— Windows PowerShell 5.1 只有见到 BOM 才会按 UTF-8 读中文；
    复制到项目里时请保持 BOM，或改用 pwsh 7（它默认就是 UTF-8）。
#>
[CmdletBinding()]
param(
    [switch]$AllowNoTicket,
    [int]$MaxInFlight = 1
)

$ErrorActionPreference = 'Stop'

# 让 git 的中文输出按 UTF-8 解码（否则 Windows PowerShell 5.1 会用 GBK 解，比对必然失败）
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$root = (Get-Location).Path
$checks = New-Object 'System.Collections.Generic.List[object]'

function Add-Check {
    param([string]$Name, [bool]$Ok, [string[]]$Detail = @())
    $checks.Add([pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = @($Detail) })
}

function Read-ProjectLines {
    param([string]$Rel)
    $p = Join-Path $root $Rel
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    return @(Get-Content -LiteralPath $p -Encoding UTF8)
}

# 归一化票号文本：把常见「写法变体」拉平到唯一形态，再交给统一正则识别。
#   契约是「票号写成 T-<数字>」（见 SKILL.md 模板 3 的书写规定）；这里是兜底——
#   Unicode 连字符 / Markdown 强调符 / 大小写 / 全角数字 / 零宽字符，
#   都不该让一张票在门禁眼里隐身。
function Normalize-TicketText {
    param([object]$Line)
    if ($null -eq $Line) { return '' }
    $s = [string]$Line
    $s = $s -replace '[\u2010-\u2015\u2212\uFF0D]', '-'          # 各种 Unicode 连字符 → ASCII 减号
    for ($i = 0; $i -lt 10; $i++) {                              # 全角数字 → 半角
        $s = $s -replace ([string][char](0xFF10 + $i)), ([string][char](0x30 + $i))
    }
    $s = $s -replace '[*_`]', ''                                 # Markdown 强调 / 行内代码符
    $s = $s -replace '[\u200B-\u200D\uFEFF]', ''                 # 零宽字符
    return $s
}

# 从一行里抽出所有票号（归一化后）：整体匹配、后面不接数字（挡 T-1 命中 T-12）。
# 调用处请用 @( ) 包住以固定为数组。
function Get-TicketIds {
    param([object]$Line)
    $s = Normalize-TicketText $Line
    $out = @()
    foreach ($m in [regex]::Matches($s, '(?i)T-(\d+)(?!\d)')) { $out += ('T-' + $m.Groups[1].Value) }
    return $out
}

# 归一化：逐行去尾部空白，再砍掉首尾空行。用于把「文件」和「重算结果」拉平后比对。
function Get-Signature {
    param([object]$Lines)
    $arr = @()
    if ($null -ne $Lines) { $arr = @(@($Lines) | ForEach-Object { ([string]$_).TrimEnd() }) }
    if ($arr.Count -eq 0) { return @() }
    $s = 0
    $e = $arr.Count - 1
    while ($s -le $e -and $arr[$s] -eq '') { $s++ }
    while ($e -ge $s -and $arr[$e] -eq '') { $e-- }
    if ($e -lt $s) { return @() }
    return @($arr[$s..$e])
}

# 取「变更记录」小节里的数据行（去掉表头 / 分隔行 / 空行），归一化后返回。
# 第 2 项靠它把 HEAD 版与 HEAD~1 版各取一遍再比对——比「diff 里出现过 | 行」准：
# 在 PLAN 别处加一张表格，糊弄不过去。
function Get-ChangeRows {
    param([object]$Lines)
    $out = @()
    if ($null -eq $Lines) { return $out }
    $arr = @($Lines)
    if ($arr.Count -eq 1 -and [string]::IsNullOrEmpty([string]$arr[0])) { return $out }
    $inSection = $false
    foreach ($l in $arr) {
        if ($l -match '^\s*#{1,6}\s*变更记录') { $inSection = $true; continue }
        if ($inSection -and $l -match '^\s*#{1,6}\s') { break }
        if (-not $inSection) { continue }
        $t = ([string]$l).Trim()
        if ($t -notlike '|*') { continue }
        if ($t -match '^\|[\s:|-]+\|$') { continue }
        if ($t -match '^\|\s*日期\s*\|') { continue }
        $out += $t
    }
    return $out
}

# 调用 git 的统一入口：原生命令写 stderr 时（空仓库、缺对象、路径不在工作区），
# PS 5.1 会把 stderr 包成 ErrorRecord，在上面那个 $ErrorActionPreference='Stop' 下
# 直接抛 NativeCommandError、把门禁整个打断（那次之后一项检查都不跑）。
# 所以一律从这里走：临时放宽 EAP、丢掉 stderr，拿回按行的输出（空仓库就是空数组）。
# 调用后 $LASTEXITCODE 仍是 git 的退出码，照常用来判断成败。
function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = @(& git @GitArgs 2>$null) } finally { $ErrorActionPreference = $eap }
    # 直接输出即可，别写 `return , $out`：调用处的 @() 会把它收成「元素是数组」的
    # 嵌套数组，于是 [string]$lastSubject 会变成字面量 "System.Object[]"。
    return $out
}

# --- 0. 必须在 git 仓库里 ---------------------------------------------------
$null = Invoke-Git 'rev-parse' '--is-inside-work-tree'
if ($LASTEXITCODE -ne 0) {
    Write-Host '不是 git 仓库 —— 整套流程悬空（凭据 / 唯一出处 / 追溯全靠它）。先 git init。' -ForegroundColor Red
    exit 1
}

# --- 0b. 是不是「首次 commit」 ----------------------------------------------
# hook 在 commit **执行之前**跑门禁，所以门禁眼里的「最新 commit」永远是上一条。
# 首次提交时 git log 为空，第 5（票号）/ 8（前缀）/ 10（一票一条）项查的都是
# 「上一条 commit」，此刻无从上查 —— 那是技术必然，不是违规。
# 第 6 项（CHANGELOG 与 git log 逐行一致）也一并放行：起项目时骨架里的 CHANGELOG
# 还是模板，要它当场等于 git log 就得「先提交 → 再刷 → 再 --amend」，与
# 「一次 commit 把仓库立起来」相冲。首次提交只求仓库立起来，CHANGELOG 留待
# 下次提交自然对齐。第 2 项同样跳过「比上一版多一行」的比对。
# ★ 第 1 项（骨架齐全）**不放行** —— 骨架建好正是首次提交的前提。
# 判定信号：git rev-list -n 1 --all 无输出 = 仓库里一条 commit 都没有。
# 新项目（git init 后）与半路接入、此前从未做过 git 的项目，走的是同一条判定。
$initialCommit = [string]::IsNullOrWhiteSpace((@(Invoke-Git 'rev-list' '-n' '1' '--all') -join ''))

# 「最新 commit 是不是首次 commit」——人工在**提交之后**跑门禁时看这个。
#
# 光看「仓库只有 1 条 commit」不够：一个只提交过一次的普通仓库（比如测试基线）
# 也是 1 条 commit，那样会被误当成首次 commit 放行，第 2 / 5 / 6 / 9 项当场失守。
# 首次 commit 的定义性特征是**不挂票号**（见 SKILL.md：它跳过切票 / 判据 / 验收
# 整条流程，无票可挂）——所以再收一道：最新 commit 必须没声明「追溯：T-号」。
# 于是：
#   · 挂票号的单 commit 仓库 → 不是首次 commit，一切照常查（第 9 项该报就报）；
#   · 不挂票号的单 commit 仓库 → 首次 commit，第 2 / 5 / 6 / 9 项放行。
# 普通的多 commit 仓库里，一条不挂票号的提交不会因此获得豁免——还要求只有 1 条 commit。
$commitCount = 0
$countRaw = @(Invoke-Git 'rev-list' '--count' 'HEAD')
if ($countRaw.Count -gt 0) {
    $parsed = 0
    if ([int]::TryParse(([string]$countRaw[0]).Trim(), [ref]$parsed)) { $commitCount = $parsed }
}
$lastDeclaresTicket = ((@(Invoke-Git 'log' '-1' '--pretty=format:%B') -join "`n") -match '追溯[:：]\s*T-\d+')
$isFirstCommit = ($commitCount -eq 1 -and -not $lastDeclaresTicket)
$firstCommit = ($initialCommit -or $isFirstCommit)

# --- 1. 骨架文件齐不齐 ------------------------------------------------------
$required = @(
    'AGENTS.md',
    'docs/PLAN.md',
    'docs/STATUS.md',
    'docs/验收判据.md',
    'docs/DECISIONS.md',
    'docs/CHANGELOG.md'
)
$missing = @()
foreach ($f in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $f))) { $missing += $f }
}
if ($missing.Count -eq 0) {
    Add-Check '骨架文件齐全' $true @("$($required.Count) 个都在")
} else {
    Add-Check '骨架文件齐全' $false (@($missing | ForEach-Object { "缺 $_" }))
}

# --- 2. PLAN 的「变更记录」是否已回写 --------------------------------------
# 两个判定：(a) 表非空；(b) 本次 commit 若改了 PLAN，就必须在「变更记录」表里
# 追一行——否则红线④「需求变动必回写 PLAN」只能靠自觉，机器什么都没守。
$plan = Read-ProjectLines 'docs/PLAN.md'
if ($firstCommit) {
    Add-Check 'PLAN 变更记录已回写' $true @('首次 commit：起项目时 PLAN 与骨架一次落地，跳过「比上一版多一行」的比对 —— 自动放行')
} elseif ($null -eq $plan) {
    Add-Check 'PLAN 变更记录已回写' $false @('读不到 docs/PLAN.md')
} else {
    $rows = @(Get-ChangeRows $plan)
    if ($rows.Count -lt 1) {
        Add-Check 'PLAN 变更记录已回写' $false @('「变更记录」小节缺失或表为空 —— 需求变了没回写 PLAN')
    } else {
        $planTouched = @(Invoke-Git 'show' '--name-only' '--pretty=format:' 'HEAD') |
            Where-Object { ([string]$_).Trim() -eq 'docs/PLAN.md' }
        if (-not $planTouched) {
            Add-Check 'PLAN 变更记录已回写' $true @("表内有 $($rows.Count) 行；本次 commit 没动 PLAN")
        } else {
            # 取两版 PLAN 各数一遍（任一方缺失时 git 会写 stderr，Invoke-Git 已吞掉）
            $headPlan = @(Invoke-Git 'show' 'HEAD:docs/PLAN.md')
            $headOk = ($LASTEXITCODE -eq 0)
            $prevPlan = @(Invoke-Git 'show' 'HEAD~1:docs/PLAN.md')
            $prevOk = ($LASTEXITCODE -eq 0)
            if (-not $headOk) {
                Add-Check 'PLAN 变更记录已回写' $true @("表内有 $($rows.Count) 行；读不到 HEAD 版 PLAN，回落为「表非空」判定")
            } elseif (-not $prevOk) {
                Add-Check 'PLAN 变更记录已回写' $true @("表内有 $($rows.Count) 行；上一版还没有 docs/PLAN.md（首个 commit）")
            } else {
                # 逐版对比「变更记录」小节：HEAD 版里出现了上一版没有的数据行，才算追了行。
                $headRows = @(Get-ChangeRows $headPlan)
                $prevRows = @(Get-ChangeRows $prevPlan)
                $added = @($headRows | Where-Object { $prevRows -notcontains $_ })
                if ($added.Count -ge 1) {
                    Add-Check 'PLAN 变更记录已回写' $true @("本次 commit 改了 PLAN：变更记录 $($prevRows.Count) 行 → $($headRows.Count) 行（新增 $($added.Count) 行）")
                } else {
                    Add-Check 'PLAN 变更记录已回写' $false @(
                        "本次 commit 改了 docs/PLAN.md，但「变更记录」小节没多一行（$($prevRows.Count) 行 → $($headRows.Count) 行）—— 红线④：需求变动必回写 PLAN",
                        '（改 PLAN 就追一行：| 日期 | 本次改了什么 | 为什么 |）',
                        '注意：在 PLAN 别处加表格行不算回写变更记录'
                    )
                }
            }
        }
    }
}

# --- STATUS 里的票（第 3、4 项要用）-----------------------------------------
$status = Read-ProjectLines 'docs/STATUS.md'
$tickets = @()
if ($null -ne $status) {
    # 契约：票号写成 T-<数字>（见 SKILL.md 模板 3）。这里不再要求「必须是表格首列」——
    # 归一化后行内出现票号即算在飞；否则一个粗体、一个从 Word 粘来的连字符、
    # 一个括号后缀，就能让两张票同时从台账上隐身（第 4 项与第 3 项一起失守）。
    foreach ($l in $status) {
        foreach ($t in @(Get-TicketIds $l)) { $tickets += $t }
    }
    $tickets = @($tickets | Select-Object -Unique)
}
$ticketLabel = $(if ($tickets.Count -gt 0) { $tickets -join ' / ' } else { '无' })

# --- 3. 每张票都有判据小节（在飞的 + git log 里已交付的）--------------------
# 票号来源 = STATUS ∪ git log 里的「追溯：T-号」。
# 只扫在飞票的话，「票擦它不擦」会在票被擦掉的那一刻失去检查。
$shipped = @()
$logAll = @(Invoke-Git 'log' '--pretty=format:%s%n%b')
foreach ($l in $logAll) {
    $n = Normalize-TicketText $l
    if ($n -match '追溯[：:]') {
        foreach ($t in @(Get-TicketIds $n)) { $shipped += $t }
    }
}
$shipped = @($shipped | Select-Object -Unique)
$allTickets = @(@($tickets) + @($shipped) | Select-Object -Unique)

# 判据的来源 = 主文件 + 归档目录下的所有 .md（满了会搬到 docs/判据归档/）
$crit = Read-ProjectLines 'docs/验收判据.md'
$critSources = @()
if ($null -ne $crit) { $critSources += , $crit }
$critDir = Join-Path $root 'docs/判据归档'
if (Test-Path -LiteralPath $critDir) {
    foreach ($f in @(Get-ChildItem -LiteralPath $critDir -Filter '*.md' -File | Sort-Object Name)) {
        $critSources += , @(Get-Content -LiteralPath $f.FullName -Encoding UTF8)
    }
}
$critFiles = $(if ($critSources.Count -gt 1) { "主文件 + 归档 $($critSources.Count - 1) 个" } else { '主文件' })
if ($critSources.Count -eq 0) {
    Add-Check '每张票都有判据留档' $false @('读不到 docs/验收判据.md（docs/判据归档/ 里也没有）')
} elseif ($allTickets.Count -eq 0) {
    Add-Check '每张票都有判据留档' $true @('还没有任何票号')
} else {
    $notFound = @()
    $emptySection = @()
    $dupSource = @()
    foreach ($t in $allTickets) {
        # 票号必须整体匹配：(?!\d) 挡住 T-1 被 T-12 / T-2 被 T-20 的前缀命中
        $pat = [regex]::Escape($t) + '(?!\d)'
        $located = $false
        $hasBody = $false
        $hitSources = @()
        for ($si = 0; $si -lt $critSources.Count; $si++) {
            $src = $critSources[$si]
            for ($i = 0; $i -lt $src.Count; $i++) {
                $head = Normalize-TicketText $src[$i]
                if ($head -match ('^\s*#+.*' + $pat) -or $head -match ('验收判据[:：]?\s*' + $pat)) {
                    $located = $true
                    if ($hitSources -notcontains $si) { $hitSources += $si }
                    # 从小节标题往下扫到下一个标题，看里面到底有没有判据内容
                    for ($j = $i + 1; $j -lt $src.Count; $j++) {
                        $line = ([string]$src[$j]).Trim()
                        if ($line -match '^#{1,6}\s') { break }
                        if ($line -eq '') { continue }
                        if ($line -match '^[\s:\|-]+$') { continue }     # 表格分隔行
                        if ($line -match '^【') { continue }              # 【A 组】这类分组标记
                        if ($line -match '^\|.*判据.*来源') { continue }  # 表头行
                        $hasBody = $true
                        break
                    }
                }
            }
        }
        if (-not $located) { $notFound += $t }
        elseif (-not $hasBody) { $emptySection += $t }
        elseif ($hitSources.Count -gt 1) { $dupSource += $t }
    }
    if ($notFound.Count -eq 0 -and $emptySection.Count -eq 0 -and $dupSource.Count -eq 0) {
        Add-Check '每张票都有判据留档' $true @("$($allTickets.Count) 张票（在飞 $(@($tickets).Count) + 已交付 $(@($shipped).Count)）都有判据小节，且小节里有内容", "搜索范围：$critFiles")
    } else {
        $detail = @()
        $detail += @($notFound | ForEach-Object { "$_ 在 docs/验收判据.md 里找不到判据小节（票擦它不擦）" })
        $detail += @($emptySection | ForEach-Object { "$_ 的判据小节是空的（只有标题、没有判据）—— 空小节等于没留档" })
        $detail += @($dupSource | ForEach-Object { "$_ 的判据小节重复留了两份（主文件与归档、或归档内两个文件都有）—— 归档是「原样移走」，不留副本" })
        Add-Check '每张票都有判据留档' $false $detail
    }
}

# --- 4. 在飞票数 -----------------------------------------------------------
if ($null -eq $status) {
    Add-Check "在飞票数 <= $MaxInFlight" $false @('读不到 docs/STATUS.md')
} elseif ($tickets.Count -le $MaxInFlight) {
    Add-Check "在飞票数 <= $MaxInFlight" $true @("$($tickets.Count) 张：$ticketLabel")
} else {
    Add-Check "在飞票数 <= $MaxInFlight" $false @("$($tickets.Count) 张在飞（$ticketLabel）—— 超上限，先闭环再切票")
}

# --- 5. 最新 commit 带「追溯：T-票号」 --------------------------------------
$lastSubject = (@(Invoke-Git 'log' '-1' '--pretty=format:%s') -join "`n")
$lastBody = (@(Invoke-Git 'log' '-1' '--pretty=format:%b') -join "`n")
$lastAll = ($lastSubject + "`n" + $lastBody).Trim()
if ($firstCommit) {
    Add-Check '最新 commit 带 追溯：T-票号' $true @('首次 commit：不挂票号 —— 自动放行（第 2 / 6 / 9 项同理）')
} elseif ([string]::IsNullOrWhiteSpace($lastAll)) {
    Add-Check '最新 commit 带 追溯：T-票号' $false @('还没有任何 commit')
} elseif ($lastAll -match '追溯[:：]\s*T-\d+') {
    if ($commitCount -eq 1) {
        # 仓库只有这一条 commit，却挂了票号 —— 多半是首次 commit 多写了一行。
        # 带了票号就不再享受首次放行（那个票号会被算成「已交付」，第 3 项随后就查它）。
        Add-Check '最新 commit 带 追溯：T-票号' $true @(
            $lastSubject.Trim(),
            '★ 这是仓库里唯一一条 commit，却带了票号 —— 首次 commit 不挂票号（它跳过切票 / 判据 / 验收，无票可挂）；',
            '  挂了等于凭空造一张没闭环的票，第 3 项会要求它有判据小节。建议去掉这一行。'
        )
    } else {
        Add-Check '最新 commit 带 追溯：T-票号' $true @($lastSubject.Trim())
    }
} elseif ($AllowNoTicket) {
    Add-Check '最新 commit 带 追溯：T-票号' $true @("已放行（-AllowNoTicket，视为流程维护类提交）：$($lastSubject.Trim())")
} else {
    Add-Check '最新 commit 带 追溯：T-票号' $false @(
        "最新 commit 没带票号：$($lastSubject.Trim())",
        '流程维护类提交（改约定 / 改门禁）请加 -AllowNoTicket'
    )
}

# --- 6. CHANGELOG 与 git log 逐行一致 ---------------------------------------
$logRaw = @(Invoke-Git 'log' '--pretty=format:- %ad  %s' '--date=format:%Y-%m-%d %H:%M')
if ($logRaw.Count -eq 1 -and [string]::IsNullOrEmpty([string]$logRaw[0])) { $logRaw = @() }

$expected = @('# 变更记录', '', '> 由 git log 自动生成，勿手改。', '')
foreach ($l in $logRaw) { $expected += [string]$l }

$actualChan = Read-ProjectLines 'docs/CHANGELOG.md'
if ($firstCommit) {
    Add-Check 'CHANGELOG 与 git log 一致' $true @('首次 commit：此刻 git log 只有这一条，要求 CHANGELOG 当场一致就得「先提交 → 再刷 → 再 --amend」——自动放行，CHANGELOG 留待下次提交自然对齐')
} elseif ($null -eq $actualChan) {
    Add-Check 'CHANGELOG 与 git log 一致' $false @('读不到 docs/CHANGELOG.md')
} else {
    $a = Get-Signature $actualChan
    $b = Get-Signature $expected
    if ($a.Count -eq $b.Count) {
        $firstDiff = -1
        $nDiff = 0
        for ($i = 0; $i -lt $a.Count; $i++) {
            if ($a[$i] -ne $b[$i]) {
                if ($firstDiff -lt 0) { $firstDiff = $i }
                $nDiff++
            }
        }
        if ($nDiff -eq 0) {
            Add-Check 'CHANGELOG 与 git log 一致' $true @("$($b.Count) 行全部对上")
        } else {
            Add-Check 'CHANGELOG 与 git log 一致' $false @(
                "第 $($firstDiff + 1) 行起对不上（共 $nDiff 行不同）",
                "文件：$($a[$firstDiff])",
                "应为：$($b[$firstDiff])",
                '→ 重跑刷新命令（先 commit → 再刷 → 再 git commit --amend --no-edit）'
            )
        }
    } else {
        Add-Check 'CHANGELOG 与 git log 一致' $false @(
            "行数不一致：文件 $($a.Count) 行，应为 $($b.Count) 行",
            '→ 要么刷漏了，要么手改了；重跑刷新命令覆盖它'
        )
    }
}

# --- 7. 判据里标注的测试文件是否存在 ----------------------------------------
# 「能交给机器的，绝不写成要人手动维护的文档」——A 组判据沉淀成测试之后，
# 在判据小节里追一行「测试：<相对路径>」，这里复查文件真的在。
# 契约：一行一个（见 SKILL.md 模板 4）。这里是容错解析，两种写法都兜住：
#   · 一行写了多个（逗号 / 分号 / 空格分隔）→ 逐个复查，不再只查第一个；
#   · 路径含空格 → 整段先当一条路径试，试不通再按空白拆。
# 一张票都没标 = 没有可自动测的判据，跳过（不强制；但没标就等于 A 组没人守）。
# 判据可能已被归档，所以同样扫主文件 + docs/判据归档/。
$testRefs = @()
foreach ($src in $critSources) {
    foreach ($l in $src) {
        foreach ($m in [regex]::Matches([string]$l, '测试[：:]\s*(.+)$')) {
            $seg = $m.Groups[1].Value.Trim()
            foreach ($grp in @($seg -split '[,;、，；]')) {
                $g = $grp.Trim().TrimEnd('。', '.')
                if ($g -eq '') { continue }
                if ($g -match '[<>]') { continue }                     # 模板占位符 <相对路径>
                if ($g -match '^`([^`]+)`$') { $testRefs += $Matches[1].Trim(); continue }   # 反引号界定 → 原样取
                $toks = @($g -split '\s+' |
                    ForEach-Object { (($_ -split '[（(【\[{。：:]')[0]).Trim('`').Trim() } |
                    Where-Object { $_ -ne '' -and ($_ -match '[/\\]' -or $_ -match '\.') })
                if ($toks.Count -eq 0) { continue }
                $testRefs += , $toks                                   # 一组：整体优先，退而逐个
            }
        }
    }
}
# 去重（按组内容），并统一成「组的数组」
$seen = @{}
$groups = @()
foreach ($r in $testRefs) {
    $one = @($r)
    $key = $one -join ' '
    if ($key -eq '') { continue }
    if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $groups += , $one }
}
if ($groups.Count -eq 0) {
    Add-Check '判据标注的测试文件存在' $true @('没有任何票标注测试文件（未标注则跳过；标了就会查）')
} else {
    $testMissing = @()
    foreach ($grp in $groups) {
        $g = @($grp)
        if ($g.Count -eq 1) {
            if (-not (Test-Path -LiteralPath (Join-Path $root ($g[0] -replace '\\', '/')))) { $testMissing += $g[0] }
        } else {
            # 整段先当一条路径（路径可能含空格）；试不通再要求组内每个都在
            $whole = $g -join ' '
            if (-not (Test-Path -LiteralPath (Join-Path $root ($whole -replace '\\', '/')))) {
                foreach ($r in $g) {
                    if (-not (Test-Path -LiteralPath (Join-Path $root ($r -replace '\\', '/')))) { $testMissing += $r }
                }
            }
        }
    }
    if ($testMissing.Count -eq 0) {
        Add-Check '判据标注的测试文件存在' $true @("$($groups.Count) 处标注的测试文件都在")
    } else {
        Add-Check '判据标注的测试文件存在' $false (@($testMissing | ForEach-Object { "找不到测试文件 $_ —— 判据里标了，文件却不在（承诺没变成测试）" }))
    }
}

# --- 8. 最新 commit 的 subject 前缀 -----------------------------------------
# 契约：subject = `<前缀> <业务描述>`，前缀 ∈ {新增, 修复, 调整, 验证, 验收}
# （SKILL.md 提交纪律）。三个月后翻 git log 能不能看出业务，先看前缀在不在。
$prefixes = @('新增', '修复', '调整', '验证', '验收')
if ($initialCommit) {
    Add-Check '最新 commit 前缀合规' $true @('首次 commit：仓库里还没有任何 commit，本条 commit 门禁看不到 —— 自动放行')
} elseif ([string]::IsNullOrWhiteSpace($lastSubject)) {
    Add-Check '最新 commit 前缀合规' $false @('还没有任何 commit')
} else {
    $hit = $null
    foreach ($p in $prefixes) {
        if ($lastSubject -match ('^' + $p + '(\s|$)')) { $hit = $p; break }
    }
    if ($null -ne $hit) {
        Add-Check '最新 commit 前缀合规' $true @("前缀「$hit」：$($lastSubject.Trim())")
    } else {
        Add-Check '最新 commit 前缀合规' $false @(
            "subject 没以规定前缀开头：$($lastSubject.Trim())",
            '应以 新增 / 修复 / 调整 / 验证 / 验收 之一开头，例：调整 导出文件名改为「标题-日期」'
        )
    }
}

# --- 9. 台账里的票没被交付过（不变量）---------------------------------------
# 一票一条 commit：擦票与代码 / 沉淀测试 / CHANGELOG 同进那一次提交。
# 所以一张票**一旦出现在任何 commit 的「追溯：」里，它就该已擦出台账**。
#
# ★ 为什么查「任何历史 commit」而不是「最新那一条」：
#   只看最新那条时，漏擦票会被后面任意一条不带票号的提交（流程维护类）挤出
#   视野，从此再没人查——而「票擦它不擦」正是靠这一项守的。实测过：交付后
#   立刻跑会报红，再提交一条维护提交就变绿了，票却还挂在台账里。
#   改成不变量之后，漏擦在**每次**跑门禁时都报，直到真去复测并擦票。
#   $shipped = 全部历史 commit 声明过的票号（第 3 项已算好，这里直接复用）。
if ($firstCommit) {
    Add-Check '台账里的票没被交付过' $true @('首次 commit：不挂票号，无所谓擦没擦')
} elseif ($tickets.Count -eq 0) {
    Add-Check '台账里的票没被交付过' $true @('台账是空的（没有在飞票）')
} else {
    $stillOpen = @($tickets | Where-Object { $shipped -contains $_ })
    if ($stillOpen.Count -eq 0) {
        Add-Check '台账里的票没被交付过' $true @("$($tickets.Count) 张在飞票：$ticketLabel —— 都没有交付记录")
    } else {
        Add-Check '台账里的票没被交付过' $false @(
            "$($stillOpen -join ' / ') 既在台账里、又已被某条 commit 声明过 —— 漏擦票（票已交付，台账却还挂着它）",
            '（一票一条：擦票要和代码 / 沉淀测试 / CHANGELOG 一起进那次提交）',
            '★ 这条会一直报，直到你人工复测通过后擦票 —— 别为了刷绿自己擦：擦票的语义是「验过了」'
        )
    }
}

# --- 10. 一票一条 commit -----------------------------------------------------
# 契约：一张票 = 一条 commit（多票在飞时分票提交；流程维护类走 -AllowNoTicket）。
# 只认「追溯：T-x」这种**声明式**票号——body 里顺带提到别的票号不算数（那正是它的用途）。
#   (a) 同一个票号最多出现在 1 条 commit —— 抓「交付后又拿旧票号打补丁」「借已交付票号」；
#   (b) 一条 commit 最多声明 1 个票号 —— 抓「多票塞进同一条 commit」。
# ★ --amend（刷 CHANGELOG）是**改写**那条提交、不新增条目，所以刷 CHANGELOG 不会被误判。
$logRaw10 = @(Invoke-Git 'log' '--pretty=format:%H%x01%B')

$commitTickets = @()
$curHash = $null
$curIds = @()
foreach ($line in $logRaw10) {
    $s = [string]$line
    if ($s -match '^([0-9a-fA-F]{7,40})\x01(.*)$') {
        if ($null -ne $curHash) { $commitTickets += , [pscustomobject]@{ Hash = $curHash; Ids = @($curIds) } }
        $curHash = $Matches[1]
        $curIds = @()
        $s = $Matches[2]
    }
    if ($null -ne $curHash) {
        foreach ($m in [regex]::Matches((Normalize-TicketText $s), '追溯[：:]\s*(T-\d+)(?!\d)')) {
            $curIds += $m.Groups[1].Value
        }
    }
}
if ($null -ne $curHash) { $commitTickets += , [pscustomobject]@{ Hash = $curHash; Ids = @($curIds) } }

$holderCount = @{}
$multiDeclare = @()
foreach ($c in $commitTickets) {
    $u = @(@($c.Ids) | Select-Object -Unique)
    if ($u.Count -gt 1) { $multiDeclare += ($c.Hash.Substring(0, 7) + ' 声明了 ' + ($u -join ' / ')) }
    foreach ($id in $u) {
        if ($holderCount.ContainsKey($id)) { $holderCount[$id]++ } else { $holderCount[$id] = 1 }
    }
}
$repeatTicket = @($holderCount.Keys | Where-Object { $holderCount[$_] -gt 1 } | Sort-Object)
if ($initialCommit) {
    Add-Check '一票一条 commit' $true @('首次 commit：仓库里还没有任何 commit，本条 commit 门禁看不到 —— 自动放行')
} elseif ($commitTickets.Count -eq 0) {
    Add-Check '一票一条 commit' $false @('还没有任何 commit')
} elseif ($repeatTicket.Count -eq 0 -and $multiDeclare.Count -eq 0) {
    Add-Check '一票一条 commit' $true @("$($commitTickets.Count) 条 commit，$(@($holderCount.Keys).Count) 个票号各声明一次")
} else {
    $detail = @()
    $detail += @($repeatTicket | ForEach-Object { "$_ 在 $($holderCount[$_]) 条 commit 里声明过 —— 一票一条：这张票提交了多次（已验收的东西要变就开新票；别拿旧票号打补丁，也别借已交付的票号）" })
    $detail += @($multiDeclare | ForEach-Object { "一条 commit 声明了多个票号：$_ —— 多票在飞时用 git add <该票文件> 分票提交" })
    Add-Check '一票一条 commit' $false $detail
}

# --- 打印 -------------------------------------------------------------------
Write-Host ''
Write-Host '=== solo-project-control 门禁 ===' -ForegroundColor Cyan
Write-Host "项目根：$root"
Write-Host ''

$i = 0
foreach ($c in $checks) {
    $i++
    if ($c.Ok) {
        Write-Host ('  [ OK ] ' + $i + '. ' + $c.Name) -ForegroundColor Green
        foreach ($d in $c.Detail) { if ("$d" -ne '') { Write-Host "         $d" -ForegroundColor DarkGray } }
    } else {
        Write-Host ('  [FAIL] ' + $i + '. ' + $c.Name) -ForegroundColor Red
        foreach ($d in $c.Detail) { if ("$d" -ne '') { Write-Host "         $d" -ForegroundColor Yellow } }
    }
}

$failed = @($checks | Where-Object { -not $_.Ok })
Write-Host ''
if ($failed.Count -eq 0) {
    Write-Host "=== 全过（$($checks.Count) 项） ===" -ForegroundColor Green
    exit 0
} else {
    Write-Host "=== $($failed.Count) 项违规（共 $($checks.Count) 项检查） ===" -ForegroundColor Red
    foreach ($c in $failed) { Write-Host "  - $($c.Name)" -ForegroundColor Red }
    exit 1
}
