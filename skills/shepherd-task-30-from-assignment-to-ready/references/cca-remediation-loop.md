# Stage 30 CCA remediation and re-engagement

## Step 7: Request targeted changes (shared maximum: 20 attempts)

Steps 4, 6, 7, and 8 use this same attempt budget. Gather the actual failed
current-HEAD CI logs, unresolved review threads, or missing issue deliverables.
Compose a targeted review beginning `@copilot Please fix the following issues:`.
Include relevant excerpts and the specific correction required. For evidence
requests, name the required publication destination and exact tested HEAD.
Do not request unrelated code changes or a dummy commit.

Persist the review body in a UTF-8 file in the run artifact directory. Invoke
the committed helper below **instead of submitting the review separately**.
It captures the pre-request state before the triggering mutation, submits the
review pinned to the expected HEAD, reads it back, and waits for a fresh CCA
cycle. Do not synthesize or copy a polling loop into the session.

`SKILL_DIR` means the absolute directory containing the SKILL.md loaded for
this invocation, not the campaign working directory. All helper assets are
bundled with that skill, including in standalone and marketplace installs.

Bash:

```bash
bash "$SKILL_DIR/scripts/request-cca-remediation.sh" \
  "$REPO" "$TASK_ISSUE" "$PR_NUMBER" "$BASE_BRANCH" "$HEAD_SHA" \
  "$REVIEW_BODY_PATH" > "$REMEDIATION_RESULT_PATH"
```

PowerShell:

```powershell
& (Join-Path $SKILL_DIR 'scripts/request-cca-remediation.ps1') `
  -Repo $REPO -Issue $TASK_ISSUE -PullRequest $PR_NUMBER `
  -BaseBranch $BASE_BRANCH -ExpectedHead $HEAD_SHA `
  -ReviewBodyPath $REVIEW_BODY_PATH > $REMEDIATION_RESULT_PATH
$remediationExit = $LASTEXITCODE
if ($remediationExit -ne 0) {
    throw "SHEPHERD FAILED: remediation helper exited $remediationExit; inspect $REMEDIATION_RESULT_PATH"
}
```

Use a distinct result path for each attempt and a blocking tool invocation.
Inspect the native exit status and JSON result before taking any next action.
Missing/invalid JSON, nonzero exit, or any outcome other than `cycle-completed`
is a failure, never permission to proceed. The result does not constitute a
successful Stage 30 outcome.

## Maintained helper contract

The native Bash and PowerShell drivers use `scripts/cca-remediation-state.jq`
for shared JSON validation. Bash uses `date +%s` wall-clock time and ordinary
`gh` execution; PowerShell 7 retains its monotonic .NET clock and bounded
subprocess waits.
Both require `gh` and `jq`. No Node.js or npm packages are required at runtime.

The helper preserves the existing 120-second organic re-engagement window
(15-second polling), one explicit reassignment if needed, and a 600-second
completion window (30-second polling). Bash checks these soft deadlines before
and after polling API calls, and before accepting completion. It cannot
interrupt a hung `gh` command: an in-flight call can exceed the nominal window,
and wall-clock adjustments can shorten or lengthen the wait. There is no hard
Bash request or overall runtime limit. An overdue Phase A response does not
establish engagement; the existing one-time reassignment policy applies before
the completion window. Review readback must still be verified even if it
consumes the organic engagement window. An overdue Phase C response cannot
establish completion.

PowerShell API calls retain their 60-second upper bound, also capped by the
remaining polling deadline. Logical outcomes are shared, not identical real-time
cancellation behavior. A failed/uncertain mutation
requires reconciliation, not an automatic duplicate review or reassignment.
It does not introduce grace periods, progress leases, or extra attempts.

It checks authoritative exact repository/issue linkage, open/draft state, base,
and HEAD, with paginated closing references and timeline. A pre-existing active
CCA cycle is rejected before a review is submitted. Fresh CCA events must be
absent from the pre-request snapshot and no earlier than the server's review
submission timestamp. Only `copilot-swe-agent` events count, not similarly
named review-agent events. Event IDs order equal-second events, and the latest
fresh start must have a subsequent successful terminal event. These are
observable correlation boundaries, not a claim that the API exposes a causal
review-to-agent-session identifier. Ambiguous or malformed evidence fails closed.

| Outcome | Exit | Meaning / next action |
|---|---|---|
| `cycle-completed` | 0 | Fresh cycle completed, with or without a changed HEAD. Revalidate the correction. |
| `invalid-input` | 2 | Invocation or prerequisite is invalid. Stop. |
| `api-error` | 3 | Request failed (or exceeded PowerShell's per-request bound). Reconcile any uncertain mutation, then stop. |
| `invalid-state` | 4 | Response malformed, review readback failed, or an authoritative invariant changed. Stop. |
| `unchanged-head-timeout` | 8 | No completed fresh cycle within the deadline; HEAD unchanged. Stop. |
| `changed-head-incomplete-cycle` | 8 | Partial push without verified completion by the deadline. Stop; no extra Step 3 wait. |
| `agent-failed` | 9 | Fresh cycle explicitly failed. Stop; a substantive diff does not make it a successful cycle. |

The version-1 JSON result records repository/issue/PR/base, request identity and
server timestamp, original/current HEAD and `headChanged`, event IDs/timestamps,
elapsed milliseconds, window budgets, reassignment status, and whether
the PR description changed. `acceptance` is always `not-evaluated`;
`nextAction: revalidate` is returned only for `cycle-completed`.
For Bash, `elapsedMs` is the wall-clock difference at second resolution
multiplied by 1000; clock adjustments affect it and may make it negative.
PowerShell elapsed time remains monotonic. The result schema is unchanged.

## Completion is not acceptance

After `cycle-completed`, return to **Step 3** and rerun all normal gates,
including effective diff, issue deliverables, commands, CI, reviews, and the
atomic final HEAD check. A changed HEAD invalidates evidence for the old
revision. An unchanged HEAD permits evidence-only remediation; it does not
prove that either code or evidence was corrected.

For evidence requests, re-fetch and read the actual required PR description,
comment, or artifact. Verify the exact tested HEAD, command results, and
human-versus-agent provenance. Compare the published content with the request,
not with an agent's assertion that it published something. A changed description
alone cannot prove adequate evidence. If the agent claims a description update
but `descriptionChanged` is false, report the contradiction and inspect the
authoritative body. A "done" comment cannot replace evidence required in the
description.

When this session writes a PR description, first inspect and preserve the
repository's PR template, existing implementation summary, and closing-issue
reference. Read back the persisted text before claiming publication succeeded.
The plugin's `verify-github-issue-body.sh` / `.ps1` accepts a PR number as its
issue number (the issue REST resource holds the PR body); use it to compare an
expected persisted body when available. Text equality proves publication only,
not substantive acceptance.

If the requested correction is absent or inadequate, label it **ineffective
remediation** and spend another attempt from the same 20-attempt budget, or stop
when exhausted. Do not restart the budget, submit empty commits, invent evidence,
dismiss reviews automatically, or mark ready merely because the helper exited 0.
Keep requirement assessment and browser/code correctness judgments in the skill.

On exhaustion:

```text
SHEPHERD FAILED: Exhausted 20 iterations on PR #PR_NUMBER for task #TASK_ISSUE.
Manual intervention required.
```

## Policy coordination

This focused implementation covers the remediation slice of
`edburns/awesome-copilot#1`, not its full discovery/initial-lifecycle campaign.
It also fixes `edburns/awesome-copilot#15`'s partial-push timeout fall-through.
It intentionally supersedes #15's old requirement that a finished cycle without
a new HEAD must fail: replace that row/test with "completed unchanged-HEAD cycle
returns to full validation; missing or ineffective evidence still fails
acceptance." No claim is made that the original failed campaign passed.

Progress-aware deadline policy (`edburns/awesome-copilot#3`) and redaction
optimization (`edburns/awesome-copilot#16`) are unchanged and out of scope.
