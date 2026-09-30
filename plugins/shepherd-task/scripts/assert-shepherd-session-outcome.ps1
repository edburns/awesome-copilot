# shepherd-task-version: 1.0.4
<#
.SYNOPSIS
    Requires a successful semantic outcome from a shepherd stage session.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SharePath,

    [Parameter(Mandatory)]
    [ValidateSet(30, 40)]
    [int]$Stage,

    [Parameter(Mandatory)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$TaskIssue,

    [int]$PRNumber
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SharePath -PathType Leaf)) {
    throw "Stage $Stage did not write its required session transcript: $SharePath"
}

$terminalMarker = $null
$inCopilotResponse = $false
$sawCopilotResponse = $false
foreach ($line in [System.IO.File]::ReadLines($SharePath)) {
    if ($line -match '^###\s+Copilot\s*$') {
        $inCopilotResponse = $true
        $sawCopilotResponse = $true
        $terminalMarker = $null
        continue
    }
    if ($inCopilotResponse -and
        ($line -match '^###\s+User\s*$' -or $line -match '^###\s+`')) {
        $inCopilotResponse = $false
    }
    if (-not $inCopilotResponse) {
        continue
    }

    $normalized = ($line -replace '\*', '').Trim()
    while ($normalized.StartsWith('>')) {
        $normalized = $normalized.Substring(1).TrimStart()
    }
    if ($normalized -match '^SHEPHERD (?:COMPLETE|FAILED|BLOCKED):') {
        $terminalMarker = $normalized
    }
}

if (-not $sawCopilotResponse -or [string]::IsNullOrWhiteSpace($terminalMarker)) {
    throw "Stage $Stage did not report a terminal SHEPHERD COMPLETE, SHEPHERD FAILED, or SHEPHERD BLOCKED marker in its final Copilot response: $SharePath"
}

if ($terminalMarker.StartsWith('SHEPHERD FAILED:', [StringComparison]::Ordinal) -or
    $terminalMarker.StartsWith('SHEPHERD BLOCKED:', [StringComparison]::Ordinal)) {
    throw "Stage $Stage reported semantic failure: $terminalMarker"
}
if (-not $terminalMarker.StartsWith('SHEPHERD COMPLETE:', [StringComparison]::Ordinal)) {
    throw "Stage $Stage reported an unsupported terminal marker: $terminalMarker"
}
if ($PRNumber -le 0) {
    throw "Stage $Stage reported completion, but no linked PR was found for task #$TaskIssue."
}
$prPattern = 'PR #{0}(?![0-9])' -f
    [regex]::Escape([string]$PRNumber)
$taskPattern = 'task #{0}(?![0-9])' -f
    [regex]::Escape([string]$TaskIssue)
if (-not [regex]::IsMatch($terminalMarker, $prPattern) -or
    -not [regex]::IsMatch($terminalMarker, $taskPattern)) {
    throw "Stage $Stage terminal marker does not identify task #$TaskIssue and PR #$PRNumber`: $terminalMarker"
}

$requiredOutcome = if ($Stage -eq 30) { 'ready' } else { 'merged' }
if ($terminalMarker.IndexOf($requiredOutcome, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
    throw "Stage $Stage terminal marker does not report '$requiredOutcome': $terminalMarker"
}

[pscustomobject]@{
    Stage = $Stage
    TaskIssue = $TaskIssue
    PRNumber = $PRNumber
    Status = 'complete'
    Marker = $terminalMarker
}
