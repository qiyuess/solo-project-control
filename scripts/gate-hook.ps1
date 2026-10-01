<#
  PreToolUse hook for the solo-project-control skill.

  What it does
    When a bash tool call is about to run `git commit`, this runs the project's
    gate.ps1 first -- the same process gate the skill mandates. If the gate
    reports violations, the commit is BLOCKED (exit 2) and the gate's output is
    handed back to the model as the reason.

  Why a hook
    gate.ps1 used to be "run it yourself": an agent could simply forget, and
    nothing enforced it. Of the hook events, only PreToolUse and UserPromptSubmit
    can gate the loop, so a hard rule like this belongs in PreToolUse.

  Contract
    stdin   - the hook event payload (JSON). The exact shape is treated as opaque
              text on purpose, so this keeps working if field names change.
    exit 0  - allow the tool call
    exit 2  - block it; stderr is returned to the model as the reason

  Matching (the fiddly part)
    We only get the command TEXT, so the regex decides both false negatives and
    false positives. Two things had to be gotten right, and both were wrong in
    the first cut -- see the two comments inline below.

    The rule is "git sits at a command position, and mentions commit later":

        (?m)(^|[;&|\n])\s*git\b[^;&|\n]*\bcommit\b

    Known remaining gap: a wrapped commit such as `bash -c "git commit -m x"` is
    not at a command position, so it passes. That one is deliberate -- it is an
    act of evasion rather than an accident, and it is visible to a human reading
    the call.

  Deliberately ASCII-only: PS 5.1 decodes BOM-less files as ANSI, so any non-ASCII
  byte here would corrupt the script. The human-facing Chinese comes from gate.ps1's
  own output, which does carry a BOM.
#>
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$payload = ''
try { $payload = [Console]::In.ReadToEnd() } catch { }
if ([string]::IsNullOrEmpty($payload)) { exit 0 }

# The payload is JSON, so a newline inside the command arrives as the two characters
# backslash-n, not as a real newline. Restore them before matching: otherwise the
# second line of a multi-line command never looks like a command position, and a
# multi-line commit slips straight through. (.Replace is literal, not regex.)
#
# Keep this on the COMMAND value only. Run over the whole payload it also rewrites
# the cwd: a Windows path is a run of "\\" pairs in JSON, so the "\r" inside
# "...\\reasonix\\..." and the "\t" inside "...\\test-project\\..." are stripped as
# if they were escape sequences. The mangled path then fails Test-Path below, $root
# silently falls back to this process's directory, and the gate judges the WRONG
# project -- which is how a clean repo got blocked with "Project root: <elsewhere>".
$command = ''
if ($payload -match '"command"\s*:\s*"((?:[^"\\]|\\.)*)"') { $command = $Matches[1] }

# Canonical case: match the command text on its own -- it starts at the beginning, so
# the plain command-position alternatives suffice. Fallback: the field was not found
# (payload shape changed), so match the whole payload as before, where the
# `"\s*:\s*"` alternative stands in for the key/value seam. Over-matching is the safe
# direction here; this text is used for matching ONLY, never to locate $root.
$matchText = $(if ($command -ne '') { $command } else { $payload })
$matchText = $matchText.Replace('\n', "`n").Replace('\r', '').Replace('\t', ' ')

# Cheap filter first: only commits are gated, everything else passes immediately --
# so the hook costs one short process spawn per bash call, not a gate run.
#
# Do NOT "simplify" this back to `git\s+commit`: that version misses real commits
# written as `git -C <dir> commit` / `git -c k=v commit` (a miss is not "safe", it
# is a way to commit with the gate skipped), and it fires on mere mentions like
# `echo "git commit"` (and the workaround an agent would invent for that -- writing
# the words differently -- is exactly the same hole).
# `"\s*:\s*"` is the JSON key/value seam: in a real payload the command sits after
# `"command":"`, so the value does not start at the start of the payload. Without
# this alternative, a plain `git commit -m x` payload never matches -- only
# multi-line commands do (their second line does start a line). That is exactly
# what the first end-to-end run showed: the multi-line probe was blocked, the
# single-line one sailed through.
$commitPattern = '(?m)(^|[;&|\n]|"\s*:\s*")\s*git\b[^;&|\n]*\bcommit\b'
if ($matchText -notmatch $commitPattern) { exit 0 }

# gate.ps1 lives next to this script (both in the skill's scripts/ directory),
# so the pair travels together when the skill is moved or updated.
$gate = Join-Path $PSScriptRoot 'gate.ps1'
if (-not (Test-Path -LiteralPath $gate)) { exit 0 }   # skill not installed -> nothing to enforce

# Work out the project root: prefer the payload's cwd, fall back to this process's cwd.
# Read the cwd from the RAW payload -- it is a JSON string escape, not something to be
# unescaped with the command's backslash handling above. Only "\\" needs undoing.
$root = $null
if ($payload -match '"cwd"\s*:\s*"([^"]+)"') { $root = ($Matches[1] -replace '\\\\', '\') }
if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) {
    $root = (Get-Location).Path
}
Set-Location -LiteralPath $root

# Run the process gate exactly the way AGENTS.md tells a human to run it.
$out  = & powershell -NoProfile -File $gate 2>&1
$code = $LASTEXITCODE

if ($code -eq 0) { exit 0 }

$reason = @(
    '',
    'BLOCKED by solo-project-control gate (PreToolUse hook).',
    "Project root: $root",
    '',
    'The process gate reported violations, so this commit was not run.',
    'Fix the items below, then commit again.'
) + @($out) + @(
    '',
    'A process-maintenance commit (no ticket) can self-check with -AllowNoTicket.'
) -join "`n"

[Console]::Error.WriteLine($reason)
exit 2
