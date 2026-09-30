# shepherd-task-version: 1.0.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..' '..'))
$stage20 = [System.IO.File]::ReadAllText(
    (Join-Path $repoRoot 'skills\shepherd-task-20-create-issues-from-plan\SKILL.md')
)
$stage30 = [System.IO.File]::ReadAllText(
    (Join-Path $repoRoot 'skills\shepherd-task-30-from-assignment-to-ready\SKILL.md')
)
$stage40 = [System.IO.File]::ReadAllText(
    (Join-Path $repoRoot 'skills\shepherd-task-40-from-ready-to-merged-to-base\SKILL.md')
)
$readme = [System.IO.File]::ReadAllText(
    (Join-Path $repoRoot 'plugins\shepherd-task\README.md')
)
$orchestrator = [System.IO.File]::ReadAllText(
    (Join-Path $repoRoot 'plugins\shepherd-task\scripts\shepherd-task.ps1')
)

foreach ($required in @(
    '## Post-merge completion gates',
    'Never place a post-merge-only predicate under `## Completion gates`'
)) {
    if (-not $stage20.Contains($required)) {
        throw "Stage 20 is missing post-merge issue-authoring guidance: $required"
    }
}

foreach ($required in @(
    'PASS/DEFERRED/FAIL',
    'intrinsically impossible before merge',
    'concrete Stage 40 post-merge verification plan',
    'No implementation, current-head CI, review, or test criterion may be deferred'
)) {
    if (-not $stage30.Contains($required)) {
        throw "Stage 30 is missing deferred-gate safeguards: $required"
    }
}

foreach ($required in @(
    '### Step 0.1: Reconstruct post-merge gates',
    'The primary merge SHA is the immutable anchor',
    '--commit "$MERGE_SHA"',
    '--event push',
    'separate evidence-only PR',
    'gh issue reopen "$TASK_ISSUE" -R "$REPO"',
    'No `DEFERRED`, `FAIL`, or `UNKNOWN` row may remain'
)) {
    if (-not $stage40.Contains($required)) {
        throw "Stage 40 is missing post-merge enforcement: $required"
    }
}

if (-not $readme.Contains('captures the primary merge SHA') -or
    -not $readme.Contains('closes the task issue only after no deferred')) {
    throw 'Plugin README does not describe post-merge completion.'
}

if (-not $orchestrator.Contains('resuming Phase 2 post-merge verification') -or
    -not $orchestrator.Contains('Find-LinkedPR -State MERGED')) {
    throw 'PowerShell orchestrator cannot resume post-merge verification.'
}
if ($orchestrator.Contains('skipping Phase 2')) {
    throw 'PowerShell orchestrator still skips Stage 40 for an open issue with a merged PR.'
}

Write-Host 'Post-merge gate contract tests passed.' -ForegroundColor Green
