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
$ghCommand = if ($env:GH_COMMAND) { $env:GH_COMMAND } else { 'gh' }
$phaseABudget = 120000L
$phaseCBudget = 600000L
$requestBudget = 60000L
$started = 0L
$deadline = 0L
$reassigned = $false
$requestId = $null
$boundary = ''
$original = ''
$current = ''
$snapshot = @{ body = $null; latestStart = $null; latestFinish = $null; latestFailure = $null }
$baseline = @{ body = $null }
$temp = $null

function Get-MonotonicMilliseconds {
    if ($env:SHEPHERD_REMEDIATION_CLOCK_COMMAND) {
        $output = & $env:SHEPHERD_REMEDIATION_CLOCK_COMMAND
        $code = $LASTEXITCODE
        $value = 0L
        if ($code -ne 0 -or -not [long]::TryParse(($output -join ''), [ref]$value) -or $value -lt 0) {
            throw 'Invalid monotonic clock output'
        }
        return $value
    }
    return [long]([Diagnostics.Stopwatch]::GetTimestamp() * 1000.0 / [Diagnostics.Stopwatch]::Frequency)
}

function Stop-Remediation([string]$Outcome, [int]$Code, [string]$Message) {
    $elapsed = if ($started -gt 0) { (Get-MonotonicMilliseconds) - $started } else { 0 }
    $descriptionChanged = if ($snapshot.body -is [string] -and $baseline.body -is [string]) {
        $snapshot.body -cne $baseline.body
    } else { $null }
    [ordered]@{
        schemaVersion = 1
        outcome = $Outcome
        message = $Message
        repository = $Repo
        issueNumber = $Issue
        prNumber = $PullRequest
        expectedBase = $BaseBranch
        requestId = $requestId
        requestSubmittedAt = $boundary
        observedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        originalHead = $original
        currentHead = $current
        headChanged = $original -cne $current
        reassignmentAttempted = $reassigned
        elapsedMs = $elapsed
        phaseABudgetMs = $phaseABudget
        phaseCBudgetMs = $phaseCBudget
        latestStart = $snapshot.latestStart
        latestFinish = $snapshot.latestFinish
        latestFailure = $snapshot.latestFailure
        descriptionChanged = $descriptionChanged
        acceptance = 'not-evaluated'
        nextAction = $(if ($Outcome -eq 'cycle-completed') { 'revalidate' } else { 'stop' })
    } | ConvertTo-Json -Depth 20
    if ($Code -ne 0) {
        [Console]::Error.WriteLine("SHEPHERD FAILED: ${Outcome}: $Message")
    }
    exit $Code
}

function Stop-Timeout {
    if ($current -cne $original) {
        Stop-Remediation 'changed-head-incomplete-cycle' 8 'HEAD changed but no completed fresh CCA cycle was verified before the deadline'
    }
    Stop-Remediation 'unchanged-head-timeout' 8 'No completed fresh CCA cycle was verified before the deadline'
}

function Invoke-GitHub([string]$OutputPath, [string[]]$Arguments) {
    $remaining = $requestBudget
    if ($deadline -gt 0) {
        $remaining = $deadline - (Get-MonotonicMilliseconds)
        if ($remaining -le 0) { Stop-Timeout }
        $remaining = [Math]::Min($remaining, $requestBudget)
    }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $ghCommand
    if ([IO.Path]::GetExtension($ghCommand) -eq '.ps1') {
        $info.FileName = (Get-Process -Id $PID).Path
        foreach ($argument in @('-NoProfile', '-File', $ghCommand)) {
            $info.ArgumentList.Add($argument)
        }
    }
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit([int]$remaining)) {
            $process.Kill($true)
            $process.WaitForExit()
            if ($deadline -gt 0 -and (Get-MonotonicMilliseconds) -ge $deadline) { Stop-Timeout }
            Stop-Remediation 'api-error' 3 'GitHub command exceeded its request budget; request state may need reconciliation'
        }
        $code = $process.ExitCode
        $output = $stdout.GetAwaiter().GetResult()
        $errorOutput = $stderr.GetAwaiter().GetResult()
        if ($code -ne 0) {
            [Console]::Error.WriteLine($errorOutput)
            Stop-Remediation 'api-error' 3 "GitHub command failed (exit $code); request state may need reconciliation"
        }
        [IO.File]::WriteAllText($OutputPath, $output, [Text.UTF8Encoding]::new($false))
    } catch {
        Stop-Remediation 'api-error' 3 "Unable to execute GitHub command: $_"
    } finally {
        $process.Dispose()
    }
}

function Invoke-Jq([string[]]$Arguments) {
    $output = & jq @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Stop-Remediation 'invalid-state' 4 'Malformed response or authoritative PR/lifecycle invariant violation'
    }
    return $output -join "`n"
}

function Read-Snapshot {
    Invoke-GitHub "$temp/pr.json" @('api', 'graphql', '--paginate', '--slurp',
        '-f', "query=$query", '-f', "owner=$($Repo.Split('/')[0])",
        '-f', "name=$($Repo.Split('/')[1])", '-F', "number=$PullRequest")
    Invoke-GitHub "$temp/timeline.json" @('api', "/repos/$Repo/issues/$PullRequest/timeline?per_page=100",
        '--paginate', '--slurp', '-H', 'Accept: application/vnd.github+json')
    $json = Invoke-Jq @('-n', '--slurpfile', 'pr', "$temp/pr.json",
        '--slurpfile', 'timeline', "$temp/timeline.json", '--slurpfile', 'baseline', "$temp/baseline.json",
        '--arg', 'repo', $Repo, '--arg', 'issue', $Issue, '--arg', 'number', $PullRequest,
        '--arg', 'base', $BaseBranch, '--arg', 'boundary', $boundary,
        '-f', (Join-Path $PSScriptRoot 'cca-remediation-state.jq'))
    $script:snapshot = ConvertFrom-Json -AsHashtable $json
    $script:current = $snapshot.head
}

function Wait-Poll([int]$Seconds) {
    $remaining = $deadline - (Get-MonotonicMilliseconds)
    if ($remaining -le 0) { return }
    $Seconds = [Math]::Min($Seconds, [Math]::Ceiling($remaining / 1000.0))
    if ($env:SHEPHERD_REMEDIATION_SLEEP_COMMAND) {
        & $env:SHEPHERD_REMEDIATION_SLEEP_COMMAND $Seconds
        $code = $LASTEXITCODE
        if ($code -ne 0) { throw "Poll wait failed (exit $code)" }
    } else {
        Start-Sleep -Seconds $Seconds
    }
}

try {
    foreach ($command in @('jq', $ghCommand)) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            Stop-Remediation 'invalid-input' 2 "Required command not found: $command"
        }
    }
    $started = Get-MonotonicMilliseconds
    if ($Repo -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or
        $Issue -notmatch '^[1-9][0-9]*$' -or $PullRequest -notmatch '^[1-9][0-9]*$' -or
        $ExpectedHead -cnotmatch '^[0-9a-f]{40}$' -or -not $BaseBranch -or
        -not (Test-Path -LiteralPath $ReviewBodyPath -PathType Leaf) -or
        (Get-Item -LiteralPath $ReviewBodyPath).Length -eq 0) {
        Stop-Remediation 'invalid-input' 2 'Expected repository, positive issue/PR numbers, base, SHA and nonempty review file'
    }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("cca-remediation-" + [guid]::NewGuid())
    [void][IO.Directory]::CreateDirectory($temp)
    [IO.File]::WriteAllText("$temp/baseline.json", '{}')
    $query = 'query($owner:String!,$name:String!,$number:Int!,$endCursor:String){repository(owner:$owner,name:$name){pullRequest(number:$number){number state isDraft baseRefName headRefOid body closingIssuesReferences(first:100,after:$endCursor){nodes{number repository{nameWithOwner}}pageInfo{hasNextPage endCursor}}}}}'
    Read-Snapshot
    $original = $current
    if ($original -cne $ExpectedHead) { Stop-Remediation 'invalid-state' 4 'HEAD changed before the remediation request' }
    if ($null -ne $snapshot.latestStart -and -not ($snapshot.completed -or $snapshot.failed)) {
        Stop-Remediation 'invalid-state' 4 'A CCA cycle is already active; do not submit an overlapping request'
    }
    $baseline = $snapshot
    $baseline | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath "$temp/baseline.json" -Encoding utf8NoBOM
    $body = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $ReviewBodyPath))
    @{ body = $body; event = 'REQUEST_CHANGES'; commit_id = $original } |
        ConvertTo-Json | Set-Content -LiteralPath "$temp/review-input.json" -Encoding utf8NoBOM
    Invoke-GitHub "$temp/review.json" @('api', '--method', 'POST',
        "/repos/$Repo/pulls/$PullRequest/reviews", '--input', "$temp/review-input.json")
    $checkReview = '(.id | type) == "number" and .id > 0 and .state == "CHANGES_REQUESTED" and .body == $body and .commit_id == $commit and (.submitted_at | type) == "string" and (.submitted_at | test("^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ$"))'
    $null = Invoke-Jq @('-e', '--rawfile', 'body', $ReviewBodyPath, '--arg', 'commit', $original, $checkReview, "$temp/review.json")
    $review = Get-Content -LiteralPath "$temp/review.json" -Raw | ConvertFrom-Json -AsHashtable
    $requestId = $review.id
    $boundary = $review.submitted_at
    $deadline = (Get-MonotonicMilliseconds) + $phaseABudget
    Invoke-GitHub "$temp/readback.json" @('api', "/repos/$Repo/pulls/$PullRequest/reviews/$requestId")
    $checkReadback = '.id == $sent[0].id and .body == $sent[0].body and .commit_id == $sent[0].commit_id and .state == "CHANGES_REQUESTED" and .submitted_at == $sent[0].submitted_at'
    $null = Invoke-Jq @('-e', '--slurpfile', 'sent', "$temp/review.json", $checkReadback, "$temp/readback.json")

    $engaged = $false
    while ((Get-MonotonicMilliseconds) -lt $deadline) {
        Read-Snapshot
        if ((Get-MonotonicMilliseconds) -ge $deadline) { break }
        if ($null -ne $snapshot.latestStart -or $current -cne $original) {
            $engaged = $true
            break
        }
        Wait-Poll 15
    }
    if (-not $engaged) {
        $deadline = 0
        $reassigned = $true
        @{ assignees = @('copilot-swe-agent[bot]'); agent_assignment = @{ target_repo = $Repo; base_branch = $BaseBranch } } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$temp/assignment.json" -Encoding utf8NoBOM
        Invoke-GitHub "$temp/assigned.json" @('api', '--method', 'POST',
            "/repos/$Repo/issues/$Issue/assignees", '-H', 'Accept: application/vnd.github+json',
            '-H', 'X-GitHub-Api-Version: 2022-11-28', '--input', "$temp/assignment.json")
        $null = Invoke-Jq @('-e', '(.assignees | type) == "array" and any(.assignees[]; .login == "copilot-swe-agent[bot]")', "$temp/assigned.json")
    }
    $deadline = (Get-MonotonicMilliseconds) + $phaseCBudget
    while ((Get-MonotonicMilliseconds) -lt $deadline) {
        Read-Snapshot
        if ((Get-MonotonicMilliseconds) -ge $deadline) { break }
        if ($snapshot.failed) {
            Stop-Remediation 'agent-failed' 9 'Fresh CCA cycle explicitly failed; substantive changes still require validation'
        }
        if ($snapshot.completed) {
            $candidate = $current
            Read-Snapshot
            if ((Get-MonotonicMilliseconds) -ge $deadline) { break }
            if ($candidate -ceq $current -and $snapshot.completed -and -not $snapshot.failed) {
                Stop-Remediation 'cycle-completed' 0 'Fresh CCA cycle completed; correction and readiness have NOT been accepted'
            }
        }
        Wait-Poll 30
    }
    Stop-Timeout
} catch {
    Stop-Remediation 'invalid-state' 4 "Remediation could not be verified: $_"
} finally {
    if ($temp -and (Test-Path -LiteralPath $temp)) {
        Remove-Item -LiteralPath $temp -Recurse -Force
    }
}
