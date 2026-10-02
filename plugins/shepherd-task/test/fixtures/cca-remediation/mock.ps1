# shepherd-task-version: 1.0.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$statePath = Join-Path $env:REMEDIATION_FIXTURE 'state.json'
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
function Save-State { $state | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM }
function Emit($Value) { Save-State; ConvertTo-Json -InputObject $Value -Depth 30 -Compress; exit 0 }
function Fail($Message) { [Console]::Error.WriteLine("Unexpected mock request: $Message"); exit 90 }
switch ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) {
    'clock' { $state.time; exit 0 }
    'sleep' { $state.time += [long]$args[0] * 1000; Save-State; exit 0 }
    'gh' {}
    default { Fail $PSCommandPath }
}
if ($args[0] -ne 'api') { Fail ($args -join ' ') }
$scenario = $state.scenario
if ($scenario -eq 'api-error') { [Console]::Error.WriteLine('mock API failure'); exit 19 }
if ($scenario -eq 'malformed-json') { 'not json'; exit 0 }
$endpoint = ''
$method = ''
$inputPath = ''
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -match '^/?repos/') { $endpoint = '/' + $args[$i].TrimStart('/') }
    if ($args[$i] -eq '--method') { $method = $args[$i + 1] }
    if ($args[$i] -eq '--input') { $inputPath = $args[$i + 1] }
}
$sha = 'a' * 40
$boundary = '2026-10-02T12:00:00Z'
if ($method -eq 'POST' -and $endpoint.EndsWith('/reviews')) {
    $body = Get-Content -LiteralPath $inputPath -Raw | ConvertFrom-Json -AsHashtable
    if ($body.event -ne 'REQUEST_CHANGES' -or $body.commit_id -cne $sha) { Fail 'review' }
    $state.review = @{ id = 50; state = 'CHANGES_REQUESTED'; body = $body.body; commit_id = $sha; submitted_at = $boundary }
    $state.posts++
    if ($scenario -eq 'uncertain-review') { Save-State; [Console]::Error.WriteLine('mock connection lost after review mutation'); exit 19 }
    Emit $state.review
}
if ($endpoint.EndsWith('/reviews/50')) {
    $review = $state.review.Clone()
    if ($scenario -eq 'bad-readback') { $review.body = 'not published' }
    Emit $review
}
if ($method -eq 'POST' -and $endpoint.EndsWith('/assignees')) {
    $body = Get-Content -LiteralPath $inputPath -Raw | ConvertFrom-Json -AsHashtable
    if ($body.assignees.Count -ne 1 -or $body.assignees[0] -ne 'copilot-swe-agent[bot]' -or
        $body.agent_assignment.target_repo -ne 'owner/repo' -or $body.agent_assignment.base_branch -ne 'campaign-base') { Fail 'assignment' }
    $state.assigned++
    if ($scenario -eq 'uncertain-reassignment') { Save-State; [Console]::Error.WriteLine('mock connection lost after reassignment mutation'); exit 19 }
    Emit @{ assignees = @(@{ login = 'copilot-swe-agent[bot]' }) }
}
if ($args[1] -eq 'graphql' -or $endpoint.Contains('/timeline?')) {
    if ($args -notcontains '--paginate' -or $args -notcontains '--slurp') { Fail 'pagination' }
}
if ($args[1] -eq 'graphql') {
    $poll = $state.poll
    $state.poll++
    $changed = $poll -gt 0 -and $scenario -in @('changed','partial','stale','newer-start','failed-diff')
    $pr = @{
        number = 11; state = 'OPEN'; isDraft = $true; baseRefName = 'campaign-base'
        headRefOid = $(if ($changed) { 'b' * 40 } else { $sha })
        body = $(if ($poll -gt 0 -and $scenario -in @('evidence','pagination')) { "Concrete evidence on HEAD $sha" } else { 'Original body' })
        closingIssuesReferences = @{
            nodes = @(@{ number = 6; repository = @{ nameWithOwner = 'owner/repo' } })
            pageInfo = @{ hasNextPage = $false; endCursor = $null }
        }
    }
    if ($scenario -eq 'wrong-base' -and $poll -gt 0) { $pr.baseRefName = 'main' }
    if ($scenario -eq 'closed') { $pr.state = 'CLOSED' }
    if ($scenario -eq 'ready') { $pr.isDraft = $false }
    if ($scenario -eq 'head-before-request' -or ($scenario -eq 'head-drift' -and $poll -ge 3)) { $pr.headRefOid = 'b' * 40 }
    if ($scenario -eq 'wrong-issue') { $pr.closingIssuesReferences.nodes[0].number = 60 }
    if ($scenario -eq 'wrong-repo') { $pr.closingIssuesReferences.nodes[0].repository.nameWithOwner = 'other/repo' }
    if ($scenario -eq 'graphql-error') { Emit @(@{ errors = @(@{ message = 'unavailable' }) }) }
    if ($scenario -eq 'pagination') {
        $first = $pr.Clone()
        $first.closingIssuesReferences = @{ nodes = @(); pageInfo = @{ hasNextPage = $true; endCursor = 'next' } }
        Emit @(@{ data = @{ repository = @{ pullRequest = $first } } }, @{ data = @{ repository = @{ pullRequest = $pr } } })
    }
    Emit @(@{ data = @{ repository = @{ pullRequest = $pr } } })
}
function Event($Id, $Kind, $Time = $boundary) {
    @{ id = $Id; event = "copilot_work_$Kind"; created_at = $Time; performed_via_github_app = @{ slug = 'copilot-swe-agent' } }
}
if ($endpoint.Contains('/timeline?')) {
    $poll = $state.poll - 1
    $old = @((Event 1 'started' '2026-10-02T11:00:00Z'), (Event 2 'finished' '2026-10-02T11:01:00Z'))
    if ($scenario -eq 'active-before-request') { $old += Event 3 'started' '2026-10-02T11:59:59Z' }
    if ($scenario -eq 'same-second-baseline') { $old = @((Event 90 'started'), (Event 91 'finished')) }
    $fresh = @()
    if ($poll -gt 0) {
        $fresh = @((Event 100 'started'), (Event 101 'finished'))
        if ($scenario -in @('partial','stale')) { $fresh = @((Event 100 'started')) }
        if ($scenario -eq 'newer-start' -or ($scenario -eq 'head-drift' -and $poll -ge 3)) { $fresh += Event 102 'started' '2026-10-02T12:00:01Z' }
        if ($scenario -eq 'orphan-finish') { $fresh = @((Event 101 'finished')) }
        if ($scenario -eq 'reverse-same-second') { $fresh = @((Event 99 'finished'), (Event 100 'started')) }
        if ($scenario -in @('failed','failed-diff')) { $fresh = @((Event 100 'started'), (Event 101 'finished_failure')) }
        if ($scenario -eq 'missing-timestamp') { $fresh[0].Remove('created_at') }
        if ($scenario -eq 'invalid-date') { $fresh[0].created_at = '2026-99-02T12:00:00Z' }
        if ($scenario -eq 'conflicting-id') { $fresh += Event 101 'started' }
        if ($scenario -eq 'missing-app') { $fresh[0].Remove('performed_via_github_app') }
        if ($scenario -eq 'foreign-agent') { foreach ($e in $fresh) { $e.performed_via_github_app.slug = 'copilot-pull-request-reviewer' } }
        if ($scenario -in @('no-engagement','uncertain-reassignment','stale-only') -or ($scenario -eq 'reassign' -and $state.assigned -eq 0)) { $fresh = @() }
        if ($scenario -eq 'late-completion' -and $poll -ge 2) { $state.time += 600000 }
    }
    if ($scenario -eq 'pagination') {
        $comments = @(1..98 | ForEach-Object { @{ event = 'commented' } })
        Emit @(@($old + $comments), @($fresh))
    }
    Emit (, @($old + $fresh))
}
if ($endpoint -eq '/repos/owner/repo/issues/11') {
    Emit @{ body = $(if ($scenario -eq 'evidence') { "Concrete evidence on HEAD $sha" } else { 'Original body' }) }
}
Fail ($args -join ' ')
