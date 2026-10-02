# shepherd-task-version: 1.0.4
[CmdletBinding()]
param([string]$ResultsPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$pluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$skillName = 'shepherd-task-30-from-assignment-to-ready'
$skillRoot = Join-Path $pluginRoot "../../skills/$skillName"
if (-not (Test-Path -LiteralPath $skillRoot)) { $skillRoot = Join-Path $pluginRoot "skills/$skillName" }
$fixtures = Join-Path $PSScriptRoot 'fixtures/cca-remediation'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "cca-contract-$([guid]::NewGuid())"
$pwsh = (Get-Process -Id $PID).Path
$savedEnvironment = @{}
foreach ($key in @('COPILOT_HOME','GH_COMMAND','REMEDIATION_FIXTURE','SHEPHERD_REMEDIATION_CLOCK_COMMAND','SHEPHERD_REMEDIATION_SLEEP_COMMAND')) {
    $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key)
}
$sha = 'a' * 40
$count = 0
function Assert($Condition, $Message) { if (-not $Condition) { throw "FAIL: $Message" } }
function Pass($Message) { $script:count++; Write-Host "PASS: $Message" }
function Reset-Fixture($Scenario) {
    @{ scenario = $Scenario; time = 1000000; poll = 0; posts = 0; assigned = 0 } |
        ConvertTo-Json | Set-Content -LiteralPath "$tempRoot/state.json" -Encoding utf8NoBOM
}
function Invoke-Helper($Scripts = (Join-Path $pluginRoot 'scripts')) {
    & $pwsh -NoProfile -File (Join-Path $Scripts 'request-cca-remediation.ps1') `
        -Repo owner/repo -Issue 6 -PullRequest 11 -BaseBranch campaign-base -ExpectedHead $sha `
        -ReviewBodyPath "$tempRoot/review.txt" >"$tempRoot/result.json" 2>"$tempRoot/error.txt"
    $script:actualCode = $LASTEXITCODE
    $script:result = Get-Content -LiteralPath "$tempRoot/result.json" -Raw | ConvertFrom-Json -AsHashtable
    Assert ($null -ne $result) 'Missing JSON result'
}
function Assert-Result($Scenario, [int]$Code, $Outcome) {
    $errorText = Get-Content -LiteralPath "$tempRoot/error.txt" -Raw
    Assert ($actualCode -eq $Code) "$Scenario expected exit $Code, got ${actualCode}: $errorText"
    Assert ($result.schemaVersion -eq 1 -and $result.outcome -eq $Outcome -and $result.acceptance -eq 'not-evaluated') "$Scenario result contract"
    Assert ($result.nextAction -eq $(if ($Code -eq 0) { 'revalidate' } else { 'stop' })) "$Scenario next action"
    Assert (-not ([IO.File]::ReadAllText("$tempRoot/result.json").Contains('SHEPHERD COMPLETE'))) "$Scenario readiness accepted"
    if ($Code -ne 0) { Assert ($errorText -match 'SHEPHERD FAILED') "$Scenario failure diagnostic" }
    if ($Code -eq 8) { Assert ($result.elapsedMs -ge 600000) "$Scenario deadline" }
    $state = Get-Content -LiteralPath "$tempRoot/state.json" -Raw | ConvertFrom-Json
    Assert ($state.posts -le 1 -and $state.assigned -le 1) "$Scenario duplicate mutation"
    switch ($Scenario) {
        evidence { Assert ($result.descriptionChanged -and -not $result.headChanged) 'Evidence-only result' }
        no-publication { Assert (-not $result.descriptionChanged -and -not $result.headChanged) 'No publication result' }
        changed { Assert $result.headChanged 'Changed HEAD' }
        active-before-request { Assert ($state.posts -eq 0) 'Overlapping review' }
        reassign { Assert ($state.assigned -eq 1) 'Reassignment missing' }
    }
    if ($Scenario.StartsWith('uncertain-')) {
        Assert ($state.posts -eq 1 -and $state.assigned -eq $(if ($Scenario -eq 'uncertain-reassignment') { 1 } else { 0 })) 'Uncertain mutation retried'
        Assert ($errorText -match 'request state may need reconciliation') 'Missing reconciliation diagnostic'
    }
}
try {
    [void][IO.Directory]::CreateDirectory($tempRoot)
    $env:REMEDIATION_FIXTURE = $tempRoot
    foreach ($command in @('gh','clock','sleep')) {
        Copy-Item -LiteralPath (Join-Path $fixtures 'mock.ps1') -Destination "$tempRoot/$command.ps1"
    }
    $env:GH_COMMAND = "$tempRoot/gh.ps1"
    $env:SHEPHERD_REMEDIATION_CLOCK_COMMAND = "$tempRoot/clock.ps1"
    $env:SHEPHERD_REMEDIATION_SLEEP_COMMAND = "$tempRoot/sleep.ps1"
    [IO.File]::WriteAllText("$tempRoot/review.txt", "@copilot Please publish concrete evidence.`n")
    if ($ResultsPath) { [IO.File]::WriteAllText($ResultsPath, '') }
    foreach ($line in Get-Content -LiteralPath (Join-Path $fixtures 'cases.tsv')) {
        $scenario, $code, $outcome, $scope = $line -split '\s+'
        if ($scope -ne 'both') { continue }
        Reset-Fixture $scenario
        Invoke-Helper
        Assert-Result $scenario ([int]$code) $outcome
        if ($ResultsPath) {
            $stable = $result.Clone()
            $stable.Remove('observedAt')
            $stable.Remove('message')
            $stable.scenario = $scenario
            $stable | ConvertTo-Json -Depth 20 -Compress | Add-Content -LiteralPath $ResultsPath -Encoding utf8NoBOM
        }
        Pass $scenario
    }
    [IO.File]::WriteAllText("$tempRoot/expected.md", "Concrete evidence on HEAD $sha")
    foreach ($scenario in @('evidence','no-publication')) {
        Reset-Fixture $scenario
        Invoke-Helper
        Assert-Result $scenario 0 'cycle-completed'
        & $pwsh -NoProfile -File (Join-Path $pluginRoot 'scripts/verify-github-issue-body.ps1') `
            -Repository owner/repo -IssueNumber 11 -ExpectedBodyPath "$tempRoot/expected.md" `
            -MaxAttempts 1 -DelaySeconds 0 -GitHubCli $env:GH_COMMAND >"$tempRoot/publication.out" 2>&1
        $publicationCode = $LASTEXITCODE
        Assert (($publicationCode -eq 0) -eq ($scenario -eq 'evidence')) "publication: $scenario"
        Pass "publication: $scenario"
    }
    [void][IO.Directory]::CreateDirectory("$tempRoot/published/skills")
    Copy-Item -LiteralPath (Join-Path $pluginRoot 'scripts') -Destination "$tempRoot/published/scripts" -Recurse
    Copy-Item -LiteralPath $skillRoot -Destination "$tempRoot/published/skills/$skillName" -Recurse
    Copy-Item -LiteralPath $skillRoot -Destination "$tempRoot/standalone" -Recurse
    foreach ($scripts in @("$skillRoot/scripts","$tempRoot/published/scripts","$tempRoot/standalone/scripts")) {
        Reset-Fixture evidence
        Invoke-Helper $scripts
        Assert-Result evidence 0 'cycle-completed'
        Pass "layout: $scripts"
    }
    $env:COPILOT_HOME = "$tempRoot/copilot-home"
    & $pwsh -NoProfile -File (Join-Path $pluginRoot 'scripts/install-task-shepherd.ps1') >"$tempRoot/install.out" 2>&1
    $installCode = $LASTEXITCODE
    Assert ($installCode -eq 0) "Isolated installation: $([IO.File]::ReadAllText("$tempRoot/install.out"))"
    foreach ($destination in @("$env:COPILOT_HOME/skills/$skillName","$env:COPILOT_HOME/plugins/shepherd-task/skills/$skillName")) {
        foreach ($asset in @('request-cca-remediation.sh','request-cca-remediation.ps1','cca-remediation-state.jq')) {
            Assert ((Get-FileHash -LiteralPath "$skillRoot/scripts/$asset").Hash -eq
                (Get-FileHash -LiteralPath "$destination/scripts/$asset").Hash) "Installed asset $asset"
        }
        Assert (-not (Test-Path -LiteralPath "$destination/scripts/cca-remediation-clock.pl")) 'Obsolete Perl asset installed'
    }
    foreach ($scripts in @("$env:COPILOT_HOME/plugins/shepherd-task/scripts","$env:COPILOT_HOME/skills/$skillName/scripts")) {
        Reset-Fixture evidence
        Invoke-Helper $scripts
        Assert-Result evidence 0 'cycle-completed'
        Pass "installed layout: $scripts"
    }
    foreach ($final in @(
        '{"outcome":"cycle-completed","acceptance":"not-evaluated","nextAction":"revalidate"}',
        '**SHEPHERD FAILED:** Ineffective remediation on PR #11 for task #6: implementation unchanged.'
    )) {
        [IO.File]::WriteAllText("$tempRoot/session.md", "# Copilot CLI Session`n`n### Copilot`n`n$final`n")
        & $pwsh -NoProfile -File (Join-Path $pluginRoot 'scripts/assert-shepherd-session-outcome.ps1') `
            -SharePath "$tempRoot/session.md" -Stage 30 -TaskIssue 6 -PRNumber 11 >"$tempRoot/outcome.out" 2>&1
        $outcomeCode = $LASTEXITCODE
        Assert ($outcomeCode -ne 0) 'Outer gate accepted lifecycle-only/ineffective result'
        Assert ([IO.File]::ReadAllText("$tempRoot/outcome.out") -match 'did not report a terminal|reported semantic failure') 'Outer gate failed for the wrong reason'
        Pass 'outer outcome rejection'
    }
    [IO.File]::WriteAllText("$tempRoot/session.md", "# Copilot CLI Session`n`n### Copilot`n`n**SHEPHERD COMPLETE:** PR #11 for task #6 is ready for marking as Ready for review.`n")
    & $pwsh -NoProfile -File (Join-Path $pluginRoot 'scripts/assert-shepherd-session-outcome.ps1') `
        -SharePath "$tempRoot/session.md" -Stage 30 -TaskIssue 6 -PRNumber 11 >"$tempRoot/outcome.out" 2>&1
    $outcomeCode = $LASTEXITCODE
    Assert ($outcomeCode -eq 0) 'Outer gate positive control'
    Pass 'outer outcome positive control'
    $instructions = [IO.File]::ReadAllText("$skillRoot/SKILL.md")
    $reference = [IO.File]::ReadAllText("$skillRoot/references/cca-remediation-loop.md")
    Assert ($instructions.Contains('Use the same committed remediation helper as Step 7')) 'Step 8 wiring'
    Assert ($reference.Contains('rerun all normal gates') -and $reference.Contains('ineffective') -and -not $reference.Contains('while [')) 'Acceptance boundary'
    foreach ($asset in @('request-cca-remediation.sh','request-cca-remediation.ps1','cca-remediation-state.jq')) {
        Assert ($instructions.Contains("scripts/$asset") -and (Test-Path -LiteralPath "$skillRoot/scripts/$asset")) "Skill asset $asset"
    }
    Pass 'skill wiring and acceptance boundary'
    Write-Host "PowerShell remediation contracts passed: $count checks."
} finally {
    foreach ($key in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key]) }
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
