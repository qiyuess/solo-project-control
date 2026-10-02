<#
  PreToolUse hook: block writes to the solo-project-control skill files
  from a project session.

  Contract
    stdin   - the hook event payload (JSON), treated as opaque text
    exit 0  - allow the tool call
    exit 2  - block it; stderr is returned to the model as the reason

  Why
    The skill files are the single source of the process rules. An agent
    working inside a project must not edit them from that project session.
    Maintenance is done in a session whose cwd is the Reasonix home or an
    explicitly allowed "maintenance" dir (passed via -SystemDir).

  Params
    -SystemDir <path>   An extra dir whose cwd is allowed to edit the skill
                        (e.g. the Reasonix Studio install dir). May be given
                        more than once. The Reasonix home is always allowed.

  Deliberately ASCII-only (like gate-hook.ps1): PS 5.1 decodes BOM-less
  files as ANSI, so non-ASCII bytes here would corrupt the script.
#>
[CmdletBinding()]
param(
    [string[]]$SystemDir = @()
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$payload = ''
try { $payload = [Console]::In.ReadToEnd() } catch { }
if ([string]::IsNullOrEmpty($payload)) { exit 0 }

# The skill root is this script's parent dir (<skill>/scripts -> <skill>).
$skillRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

function Get-JsonField {
    param([string]$Name)
    $m = [regex]::Match($payload, '"' + $Name + '"\s*:\s*"((?:[^"\\]|\\.)*)"')
    if (-not $m.Success) { return '' }
    return $m.Groups[1].Value.Replace('\\', '\')
}

# --- resolve the session cwd ---------------------------------------------
$cwd = Get-JsonField 'cwd'
if ([string]::IsNullOrWhiteSpace($cwd) -or -not (Test-Path -LiteralPath $cwd)) {
    $cwd = (Get-Location).Path
}
$cwd = [System.IO.Path]::GetFullPath($cwd)

# --- maintenance session? ------------------------------------------------
$homeRoot = [System.IO.Path]::GetFullPath((Join-Path $env:APPDATA 'reasonix'))
$allowed = $cwd.StartsWith($homeRoot, [System.StringComparison]::OrdinalIgnoreCase)
if (-not $allowed) {
    foreach ($d in $SystemDir) {
        if ([string]::IsNullOrWhiteSpace($d)) { continue }
        $full = [System.IO.Path]::GetFullPath($d)
        if ($cwd.StartsWith($full, [System.StringComparison]::OrdinalIgnoreCase)) { $allowed = $true; break }
    }
}
if ($allowed) { exit 0 }

# --- what would be written? ----------------------------------------------
$target = Get-JsonField 'path'
$command = Get-JsonField 'command'

$touches = $false
if ($target -ne '') {
    try {
        $full = [System.IO.Path]::GetFullPath($target)
        if ($full.StartsWith($skillRoot, [System.StringComparison]::OrdinalIgnoreCase)) { $touches = $true }
    } catch { }
} elseif ($command -ne '') {
    # bash heuristic: mentions the skill dir AND a write-like operation.
    if ($command -match 'solo-project-control') {
        if ($command -match '[>]' -or $command -match '(?i)\b(tee|cp|mv|rm|install|sed|dd|touch|truncate)\b') {
            $touches = $true
        }
    }
}

if (-not $touches) { exit 0 }

$reason = @(
    '',
    '已被 solo-project-control 写守卫拦下（PreToolUse 钩子）。',
    "当前会话工作区：$cwd",
    '',
    '从这个工作区改 solo-project-control 的 skill 文件是不允许的——',
    'skill 是流程规则的唯一出处。',
    '',
    '要维护它，请把工作区切到 Reasonix 安装目录或 Reasonix 主目录，再去改。'
) -join "`n"
[Console]::Error.WriteLine($reason)
exit 2
