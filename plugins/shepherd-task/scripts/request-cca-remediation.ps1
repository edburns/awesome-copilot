# shepherd-task-version: 1.0.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Issue,
    [Parameter(Mandatory)][string]$PullRequest,
    [Parameter(Mandatory)][string]$BaseBranch,
    [Parameter(Mandatory)][string]$ExpectedHead,
    [Parameter(Mandatory)][string]$ReviewBodyPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$skill = 'shepherd-task-30-from-assignment-to-ready'
foreach ($candidate in @(
    (Join-Path $PSScriptRoot "../skills/$skill/scripts/request-cca-remediation.ps1"),
    (Join-Path $PSScriptRoot "../../../skills/$skill/scripts/request-cca-remediation.ps1")
)) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        & $candidate @PSBoundParameters
        $code = $LASTEXITCODE
        exit $code
    }
}
throw 'SHEPHERD FAILED: Bundled Stage 30 remediation helper is missing.'
