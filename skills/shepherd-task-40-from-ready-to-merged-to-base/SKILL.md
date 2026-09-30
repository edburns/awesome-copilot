---
# shepherd-task-version: 1.0.4
name: shepherd-task-40-from-ready-to-merged-to-base
description: 'Stage 40 of the shepherd-task campaign lifecycle (each issue from Ready for review through merge and post-merge verification on the campaign base branch). Use this skill to shepherd a task PR through Copilot review, merge, exact-SHA base CI, and deferred evidence gates.'
---

# Skill: Shepherd Task from Ready for Review to Merged (shepherd-task stage 40 — Ready for review through merge)

## Purpose

This is stage 40 of the ordered shepherd-task campaign lifecycle (00 → 10 → 15 → 20 → 25 → 30 → 40 → 50): each issue from Ready for review through merge to the campaign base branch. Automate the lifecycle of a task PR from marking as **Ready for review** through Copilot code review comment resolution, merge to the specified base branch, and verification of any requirements that Stage 30 correctly deferred because they can exist only after merge. This is a follow-up skill intended to be run after `shepherd-task-30-from-assignment-to-ready`.

## Inputs

- `TASK_ISSUE`: The issue number (e.g., `1850`) or URL of the child task.
- `BASE_BRANCH`: The base branch the task PR should target (e.g., `edburns/1810-java-tool-ergonomics-tool-as-lambda`).
- `REPO`: Repository in `OWNER/REPO` format (default: `github/copilot-sdk`).
- `REMOTE`: Optional Git remote for `REPO`. When omitted, resolve the unique
  configured remote whose normalized GitHub URL matches `REPO`; do not assume a
  remote name such as `origin` or `upstream`.
- `CAMPAIGN_ID`: Canonical campaign UUID.
- `CAMPAIGN_METADATA_DIRECTORY`: Repository-root-relative campaign metadata directory.
- `LESSON_PROPAGATION`: Immutable mode, exactly `off` or `campaign`.

## Prerequisites

- The `shepherd-task-30-from-assignment-to-ready` skill has completed successfully for this task.
- `PR_NUMBER` is known (the PR created by Copilot for this task). For discussion: `jtbdtask-pr`.
- `gh` CLI authenticated with sufficient permissions.
- The PR is in draft state with all CI checks passing, or is already ready
  because a prior resumable stage-40 attempt completed that transition.
- The PR may already be merged when resuming a prior Stage 40 attempt that
  reopened the issue because post-merge verification did not finish.
- Any Stage 30 `DEFERRED` requirement is intrinsically post-merge-only and has
  a concrete verification plan. Stage 40 must not accept deferred
  implementation, PR-head CI, test, artifact, or review work.

## PowerShell native-command safety

When translating the Bash examples in this skill to PowerShell, capture native
command output and `$LASTEXITCODE` before applying PowerShell transformations
such as `Select-Object`, `Select-String`, or `ConvertFrom-Json`. Never pipe a
native producer directly into those commands. A pipeline whose final command
is native is allowed when `$LASTEXITCODE` is captured immediately afterward.

---

## ⚠️ CRITICAL: Never go idle while waiting

The `copilot --yolo` runtime **terminates the session shortly after the agent goes idle** (i.e., when there are no pending tool calls). If you launch a long-running polling command with a short `initial_wait` and then say "I'll check back when it completes," the runtime will kill the session before the command finishes.

**Rules for all polling and waiting steps:**

1. ✅✅✅ **ALWAYS use `initial_wait` ≥ 600 seconds** (10 minutes) on any polling/waiting command. This keeps the agent blocked on the tool call rather than going idle. ✅✅✅
2. ❌❌❌ **NEVER background a polling command and then end your turn with no tool calls.** If a command exceeds `initial_wait`, immediately issue another tool call (e.g., `read_powershell`) to stay active. ❌❌❌
3. ❌❌❌ **NEVER say "I'll check back when it completes" or "Waiting for notification."** These phrases mean you are going idle, which KILLS THE SESSION. ❌❌❌
4. ✅✅✅ **ALWAYS prefer a single blocking poll** over launching a background command and waiting for a notification. ✅✅✅

---

## Procedure

### Step 0: Find the PR

Before finding the PR, resolve the repository remote:

1. If `REMOTE` was supplied, verify that it exists and that its normalized
   GitHub URL matches `REPO`.
2. Otherwise, inspect every configured Git remote and select the unique remote
   whose normalized GitHub URL matches `REPO`. Support SSH, HTTPS, and
   `ssh://git@github.com/` URLs, with an optional `.git` suffix.
3. If zero or multiple remotes match, fail with the expected repository and
   match count. Never choose a remote based only on the names `origin` or
   `upstream`.

Use the same multi-strategy approach as the assignment skill:

1. **Issue timeline** — query `gh api "/repos/$REPO/issues/$TASK_ISSUE/timeline"` for cross-referenced open PRs.
2. **PR body search** — search open PR bodies for `#$TASK_ISSUE`.
3. **Title/branch match** — regex match on title or headRefName.

First search for an open linked PR. If none exists and the task issue is open,
search for a linked merged PR targeting `BASE_BRANCH`. A merged match means
this is a post-merge resume: preserve `PR_NUMBER`, skip Steps 1–18, and continue
at Step 19. If neither state yields exactly one authoritative linked PR, fail
the skill and report the error.

### Step 0.1: Reconstruct post-merge gates

Read the complete task issue and reconstruct the evidence table produced by
Stage 30. Identify requirements that were deferred solely because their facts
cannot exist before merge. Typical examples are:

- a successful base-branch `push` workflow for the exact primary merge SHA;
- workflow run, job, or artifact identifiers produced only by that run;
- a repository evidence file that must record those identifiers and itself be
  merged.

For every deferred gate, record:

1. the exact issue requirement;
2. why it is impossible before merge;
3. the exact post-merge query or command;
4. the expected evidence;
5. any repository path that must be updated and merged.

If any deferred item is actually unfinished implementation, current-head CI,
testing, artifact production available on the PR, or review work, report
`SHEPHERD FAILED` and stop. Do not use Stage 40 to bypass Stage 30.

### Steps 1–2: Mark ready, request Copilot review, and await completion

Read and follow
[`references/copilot-review-request-and-polling.md`](references/copilot-review-request-and-polling.md)
in full. It is the mandatory capability preflight, draft-state transition,
review-request acknowledgement, completion polling, and too-many-files refusal
gate. Continue only after it produces `COPILOT_REVIEW_ID` for the current
`REVIEW_TARGET_HEAD`.

### Step 3: Determine N (number of comments)

❌❌❌ DO NOT TAKE ANY ACTION ON COMMENTS ALREADY MARKED **Resolved**. ❌❌❌

Count top-level comments associated with the completed review. Do not parse the review body's **Comments generated:** line; that presentation syntax is not an API contract.

```bash
N=$(gh api "/repos/$REPO/pulls/$PR_NUMBER/comments" \
  | jq --argjson review_id "$COPILOT_REVIEW_ID" '
    [.[]
      | select(.pull_request_review_id == $review_id)
      | select(.in_reply_to_id == null)
    ] | length')
```

There will be exactly N individual review comments in this batch to address.

### Step 4: Fetch the repository remote and set up local worktree

❌❌❌ This part of the work does not use the remote agent. All comment resolution is done locally. ❌❌❌

```bash
# Fetch the matching repository remote to get the topic branch
git fetch "$REMOTE"

# Get the currently logged in username
GH_CURRENT_USER=$(gh api /user --jq '.login')

# Get the topic branch name for the PR
JTBDTASK_BRANCH=$(gh pr view $PR_NUMBER -R $REPO --json headRefName --jq '.headRefName')

# Create a worktree for local review work — as a SIBLING of the current repo clone, not inside it.
# Use an absolute path derived from the git toplevel to avoid CWD-relative resolution errors.
REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKTREE_PATH="$(dirname "$REPO_ROOT")/review-copilot-pr-$PR_NUMBER"
git worktree add "$WORKTREE_PATH" "$REMOTE/$JTBDTASK_BRANCH"
```

For discussion, this worktree is the `jtbdtask-pr-comments-comment-worktree`.

### Step 5: Approve workflows and wait for completion

Invoke the installed **`shepherd-task-approve-workflows-and-wait-for-completion`** skill by name with:

- `REPO` = `$REPO`
- `JTBDTASK_BRANCH` = the PR's topic branch
- `PR_NUMBER` = `$PR_NUMBER`

This ensures any pending workflow runs triggered by prior pushes are approved and complete before gathering review comments.

### Step 6: Gather all review comments

```bash
# Get all review comments from the Copilot code review batch.
# The reviewer may appear as "copilot-pull-request-reviewer[bot]" or "Copilot" depending on the repo.
gh api "/repos/$REPO/pulls/$PR_NUMBER/comments" \
  | jq --argjson review_id "$COPILOT_REVIEW_ID" '.[]
    | select(.pull_request_review_id == $review_id)
    | select(.in_reply_to_id == null)
    | {id: .id, path: .path, line: .line, body: .body}'
```

Identify each individual comment. Each has a unique `id` (e.g., `discussion_r3456155645`-style reference). For discussion, each is a `jtbdtask-pr-comments-comment`.

### Step 7: Address each review comment locally

For each review comment (`jtbdtask-pr-comments-comment`), working in the `jtbdtask-pr-comments-comment-worktree`:

#### 7.1: Evaluate the comment

- Carefully consider the comment and judge its merit.
- **If there is no merit:** mark the comment as resolved with an explanatory note (defer the resolution reply until Step 9).
- **If there is merit:** evaluate the suggested remedy.
  - If you agree with the suggested remedy, proceed with it.
  - If you disagree with the suggested remedy, devise a better remedy and proceed with that.

#### 7.2: Implement the fix

- Implement the remedy in the `jtbdtask-pr-comments-comment-worktree`.
- Use the appropriate language coding skill in `skills/` to know how to run tests.
- If there are a large number of tests:
   - ❌❌❌ DO NOT RUN THE FULL TEST SUITE at this stage. ❌❌❌ .
   - ✅✅✅ Only run the tests directly related to the fix, in isolation. ✅✅✅ .
- Otherwise, if there is not a large number of tests:
   - Run all the tests.
- **If the commit touches any Java code, YOU MUST ALWAYS RUN `mvn spotless:apply` in the java directory before each commit.**

#### 7.3: Commit locally (do not push)

- Once the relevant tests pass, commit the fix.
- ❌❌❌ Do NOT push yet. ❌❌❌
- Keep track of the commit hash — you will need it when replying to the review comment.

### Step 8: Push all fixes to `$REMOTE`

Once **all** N review comments have been addressed locally:

```bash
# Push from the worktree to the configured remote (sibling directory)
cd "$WORKTREE_PATH"
git push "$REMOTE" HEAD:$JTBDTASK_BRANCH
```

### Step 9: Reply to each review comment and resolve the thread

For each `jtbdtask-pr-comments-comment`:

1. State what you did to address the comment. If the action corresponds to a commit, include the hash: "Fixed in `<hash>`".
2. Reply to the comment.
3. Resolve the review thread.

To reply to the comment:

```bash
# Reply to a specific review comment
gh api --method POST "/repos/$REPO/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies" \
  -f "body=Fixed in $COMMIT_HASH. [explanation of the fix]"
```

To resolve the thread, use the GraphQL API (the REST API does not support thread resolution):

```bash
# 1. Get the GraphQL thread node ID for the comment
REPO_OWNER=${REPO%%/*}
REPO_NAME=${REPO#*/}
THREAD_ID=$(gh api graphql \
  -F owner="$REPO_OWNER" \
  -F name="$REPO_NAME" \
  -F number="$PR_NUMBER" \
  -f query='
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 1) { nodes { databaseId } }
        }
      }
    }
  }
}' --jq ".data.repository.pullRequest.reviewThreads.nodes[] | select(.comments.nodes[0].databaseId == $COMMENT_ID) | .id")

# 2. Resolve the thread
gh api graphql -f query="
mutation {
  resolveReviewThread(input: {threadId: \"$THREAD_ID\"}) {
    thread { id isResolved }
  }
}"
```

### Step 10: Wait for CI to run

The push triggers CI/CD. Use the same approach as `shepherd-task-30-from-assignment-to-ready` to:

1. Wait for workflow runs to complete (`gh pr checks $PR_NUMBER -R $REPO --watch`).
2. Evaluate results (excluding the expected "Block remove-before-merge paths" / "No remove-before-merge directories" failure).
3. If there are real CI failures, gather logs and fix locally, commit, and push again. Repeat until CI passes.

**Note:** Ignore failures from the "Block remove-before-merge paths" / "No remove-before-merge directories" workflow. This failure is expected on feature branches and is not a real problem.

### Step 11: Approve workflows and wait for completion

Invoke the installed **`shepherd-task-approve-workflows-and-wait-for-completion`** skill by name with:

- `REPO` = `$REPO`
- `JTBDTASK_BRANCH` = the PR's topic branch
- `PR_NUMBER` = `$PR_NUMBER`

This ensures any pending workflow runs triggered by the push in Step 8 are approved and complete before re-requesting review.

### Step 12: Re-request Copilot review

Repeat the review-target capture and acknowledged request procedure from Step 1. The new `REVIEW_TARGET_HEAD` must be the pushed fix commit, and `PREVIOUS_COPILOT_REVIEW_ID` must include the review just addressed.

Do not continue to Step 13 unless the new request is positively acknowledged.

### Step 13: Loop back

Go back to **Step 2**. Wait for the Copilot code review agent to post new findings.

**Max iterations: 8.** If exhausted, report failure and stop:

```
SHEPHERD FAILED: Exhausted 8 iterations on PR #$PR_NUMBER for task #$TASK_ISSUE.
Manual intervention required.
```

### Step 14: Approve workflows and wait for completion

Before this final approval step, perform lesson publication when
`LESSON_PROPAGATION=campaign`:

1. First inspect the current PR HEAD. If it already contains a validated
   section for this issue and no candidate section, treat publication as
   complete and do not create another lesson commit. Otherwise, in the PR
   worktree, read the candidate section for `TASK_ISSUE` from
   `CAMPAIGN_METADATA_DIRECTORY/campaign-lessons.md`.
2. Synthesize it with observed CI failures, CCRA findings, corrective commits,
   validated commands, and the final implementation. Reject inaccurate,
   speculative, issue-local, secret-bearing, or non-reusable content.
3. Replace the candidate section with:

   ```markdown
   ## Validated lessons from issue #TASK_ISSUE (PR #PR_NUMBER)

   - **Applies to:** paths, subsystem, language, or acceptance-criterion class
   - **Lesson:** concise actionable guidance
   - **Evidence:** test, CI, review finding, or final PR-head reference
   - **Source:** CCA observation, stage-40 observation, or both
   - **Confidence:** high, medium, or low
   ```

   If no reusable lesson survives validation, publish an explicit
   `No reusable lessons identified` entry with brief evidence. Preserve all
   prior validated entries. Remove the initial
   `No validated lessons have been recorded yet` placeholder when publishing
   the first validated issue section. No `Candidate lessons` section may remain.
4. Commit only the lessons-file change with a descriptive message and push it
   to the PR branch. Never add local run directories or logs.
5. Because this changes PR HEAD, go to Step 10, then execute Steps 11–13 to
   approve workflows, re-request Copilot review for the publication commit,
   and resolve any findings. When that loop returns here, the validated-section
   check in item 1 makes publication idempotent. Do not merge based on evidence
   from the pre-publication HEAD.

When `LESSON_PROPAGATION=off`, do not read or modify the campaign lessons file.

Invoke the installed **`shepherd-task-approve-workflows-and-wait-for-completion`** skill by name with:

- `REPO` = `$REPO`
- `JTBDTASK_BRANCH` = the PR's topic branch
- `PR_NUMBER` = `$PR_NUMBER`

This ensures any pending workflow runs are approved and complete before performing final checks.

### Step 15: Final checks before merge

Verify:

- Re-run the Step 2.1 too-many-files refusal query. If it matches, stop immediately; the PR must not be merged.
- The only failed check is "Block remove-before-merge paths" / "No remove-before-merge directories".
- All other checks pass.
- In `campaign` mode, the current PR HEAD contains exactly one validated lesson section for this issue, contains no candidate section for it, and prior validated entries remain intact.
- The Copilot review request for the current post-publication HEAD was
  positively acknowledged, and the authoritative Step 9 GraphQL query reports
  no unresolved review threads or pending actionable findings.

### Step 16: Verify base branch

❌❌❌ Ensure the base branch is NEVER `main` ❌❌❌ and always the `BASE_BRANCH` from this invocation.

```bash
if [ "$BASE_BRANCH" = "main" ]; then
  echo "ERROR: BASE_BRANCH must never be 'main'."
  exit 1
fi

ACTUAL_BASE=$(gh pr view "$PR_NUMBER" -R "$REPO" --json baseRefName --jq '.baseRefName')
if [ "$ACTUAL_BASE" != "$BASE_BRANCH" ]; then
  echo "PR base is '$ACTUAL_BASE'; fixing it to '$BASE_BRANCH'..."
  gh pr edit "$PR_NUMBER" -R "$REPO" --base "$BASE_BRANCH"

  ACTUAL_BASE=$(gh pr view "$PR_NUMBER" -R "$REPO" --json baseRefName --jq '.baseRefName')
  if [ "$ACTUAL_BASE" != "$BASE_BRANCH" ]; then
    echo "ERROR: Could not set PR base to '$BASE_BRANCH'."
    exit 1
  fi
fi
```

### Step 17: Handle merge conflicts

If there are conflicts between the PR branch and `BASE_BRANCH`:

```bash
# Check for merge conflicts
MERGEABLE=$(gh pr view $PR_NUMBER -R $REPO --json mergeable --jq '.mergeable')
if [ "$MERGEABLE" = "CONFLICTING" ]; then
  # Resolve conflicts locally in the worktree (sibling directory)
  cd "$WORKTREE_PATH"
  git fetch "$REMOTE"
  git rebase "$REMOTE/$BASE_BRANCH"
  # Resolve conflicts, then:
  git rebase --continue
  git push "$REMOTE" HEAD:$JTBDTASK_BRANCH --force-with-lease

  # STOP this merge attempt. The rebase changed PR HEAD.
  # Return to Step 10 and repeat Steps 10–17 for the new HEAD.
fi
```

Never continue directly to merge after pushing a conflict resolution. Return to
Step 10, approve and await workflows, repeat Copilot review and thread
resolution, republish lessons if required, and repeat the Step 15 final gate.
Then verify the base and mergeability again through Steps 16–17. Only a HEAD
that has completed that full post-rebase loop may proceed.

### Step 18: Merge the PR

```bash
gh pr merge $PR_NUMBER -R $REPO --merge --delete-branch
```

This merges the work to `BASE_BRANCH`.

### Step 19: Capture the primary merge SHA

The primary merge SHA is the immutable anchor for every deferred gate. Do not
substitute the PR head, the PR synthetic merge SHA, or a later evidence commit.

```bash
MERGE_SHA=$(gh pr view "$PR_NUMBER" -R "$REPO" \
  --json state,mergeCommit \
  --jq 'select(.state == "MERGED") | .mergeCommit.oid // empty')
if [ -z "$MERGE_SHA" ]; then
  echo "SHEPHERD FAILED: PR #$PR_NUMBER merged without an observable merge commit."
  gh issue reopen "$TASK_ISSUE" -R "$REPO" >/dev/null 2>&1 || true
  exit 1
fi
```

GitHub may automatically close the linked issue when the primary PR merges.
That is not task completion while deferred gates remain. If any post-merge gate
fails, reopen the issue before reporting failure.

When deferred gates exist, reopen the issue immediately after capturing
`MERGE_SHA`, before starting any long-running workflow wait. This makes an
interrupted Stage 40 attempt durably resumable. Leave it open until Step 24.

### Step 20: Verify exact-SHA base-branch workflows

When a deferred gate requires base-branch workflow evidence, wait for `push`
runs whose `headSha` is exactly `MERGE_SHA` and whose `headBranch` is exactly
`BASE_BRANCH`. Do not accept PR checks, synthetic merge refs, another commit,
or merely the newest branch run.

```bash
TIMEOUT=3600
INTERVAL=30
ELAPSED=0
POST_MERGE_RUNS='[]'

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  POST_MERGE_RUNS=$(gh run list -R "$REPO" \
    --branch "$BASE_BRANCH" \
    --commit "$MERGE_SHA" \
    --event push \
    --limit 100 \
    --json databaseId,workflowName,status,conclusion,headBranch,headSha,url)
  RUN_COUNT=$(jq 'length' <<<"$POST_MERGE_RUNS")
  PENDING_COUNT=$(jq '[.[] | select(.status != "completed")] | length' \
    <<<"$POST_MERGE_RUNS")
  if [ "$RUN_COUNT" -gt 0 ] && [ "$PENDING_COUNT" -eq 0 ]; then
    break
  fi
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

RUN_COUNT=$(jq 'length' <<<"$POST_MERGE_RUNS")
PENDING_COUNT=$(jq '[.[] | select(.status != "completed")] | length' \
  <<<"$POST_MERGE_RUNS")
FAILING_COUNT=$(jq \
  '[.[] | select(.status == "completed") |
    select(.conclusion != "success" and .conclusion != "neutral" and
           .conclusion != "skipped")] | length' \
  <<<"$POST_MERGE_RUNS")
if [ "$RUN_COUNT" -eq 0 ] || [ "$PENDING_COUNT" -ne 0 ] ||
   [ "$FAILING_COUNT" -ne 0 ]; then
  gh issue reopen "$TASK_ISSUE" -R "$REPO" >/dev/null 2>&1 || true
  echo "SHEPHERD FAILED: exact-SHA post-merge workflows did not pass for $MERGE_SHA."
  exit 1
fi
```

Evaluate workflow relevance, not only conclusions. Require the substantive
workflow and stable jobs named by the issue. Capture exact run, job, artifact,
digest, and URL evidence required by each deferred row.

If no deferred gate requires a base-branch workflow, do not invent one. Continue
with the remaining deferred gates.

### Step 21: Merge required post-merge evidence

If a deferred gate requires a repository file to record post-merge evidence,
update it in a separate evidence-only PR:

1. Fetch `REMOTE` and create a sibling worktree from the current
   `REMOTE/BASE_BRANCH`.
2. Create a uniquely named evidence branch containing `TASK_ISSUE` and the
   abbreviated `MERGE_SHA`.
3. Update only the evidence/documentation paths required by the deferred gate.
   Bind all recorded workflow facts to the primary `MERGE_SHA`.
4. Run applicable formatting, generated-file, and documentation checks.
5. Commit and push the evidence branch, open a PR targeting `BASE_BRANCH`, and
   record its number.
6. Require current-head CI and an acknowledged Copilot review using the same
   fail-closed review protocol as the primary PR. Resolve every finding.
7. Merge the evidence PR with branch deletion.
8. Wait for required CI on the evidence PR's exact merge SHA before continuing,
   so the campaign base remains green before the next serial task.

Use a deterministic branch name derived from `TASK_ISSUE` and the abbreviated
primary `MERGE_SHA`. Before creating it, search for an existing open or merged
evidence PR with that branch marker and resume it. Never create duplicate
evidence PRs after a timeout or interrupted session.

The evidence PR must not contain implementation changes or broaden task scope.
If it cannot be merged cleanly, reopen `TASK_ISSUE`, report
`SHEPHERD FAILED`, and stop. Do not close the task based on an unmerged evidence
branch or a comment containing the evidence.

If no deferred gate requires a repository update, skip the evidence PR.

### Step 22: Re-evaluate every deferred gate

Re-read the issue and produce a final evidence table. Every deferred row must
now be `PASS`, backed by the primary `MERGE_SHA`, exact workflow/API output,
and the merged evidence path when required. No `DEFERRED`, `FAIL`, or `UNKNOWN` row may remain.

If a row does not pass, reopen the issue if necessary and report:

```
SHEPHERD FAILED: Post-merge completion gates did not pass for PR #$PR_NUMBER and task #$TASK_ISSUE.
Manual intervention required.
```

### Step 23: Clean up worktrees

```bash
# Remove each sibling worktree created by this invocation.
if [ -n "${WORKTREE_PATH:-}" ] && [ -d "$WORKTREE_PATH" ]; then
  git worktree remove "$WORKTREE_PATH"
fi

# Remove the local branch tracking the PR topic branch (if created)
git branch -D "$JTBDTASK_BRANCH" 2>/dev/null || true
```

Also remove the post-merge evidence worktree and local evidence branch, when
created. Never remove a worktree that predates this invocation.

### Step 24: Close the corresponding issue

```bash
gh issue close $TASK_ISSUE -R $REPO
```

### Step 25: Final status report

```
SHEPHERD COMPLETE: PR #$PR_NUMBER for task #$TASK_ISSUE has been merged to $BASE_BRANCH and all post-merge completion gates passed.
```

---

## Error handling

- **Copilot review request is not acknowledged**: Report the PR and target head, restore draft state only if this invocation made the ready transition and no review was acknowledged, preserve the resumable state, and stop. Do not retry deterministic reviewer-resolution or unsupported-capability errors.
- **An acknowledged Copilot review does not complete within `COPILOT_REVIEW_TIMEOUT_SECONDS` (default 30 minutes)**: Report the PR and target head, preserve the resumable state, and stop.
- **Copilot refuses review because the PR exceeds the maximum number of files**: Report, require manual intervention, and stop without merging.
- **8 iterations exhausted**: Report and stop.
- **Merge conflicts that cannot be auto-resolved**: Report and stop.
- **Exact-SHA base-branch workflow missing, pending, irrelevant, or failing**:
  Reopen the task issue if GitHub auto-closed it, report the primary merge SHA,
  and stop.
- **Post-merge evidence cannot be updated and merged**: Reopen the task issue,
  preserve the primary merge and run evidence, report the evidence path and
  failure, and stop.
- **API errors**: Retry up to 3 times with 10-second backoff, then report and stop.

## Notes

- This skill runs in a `copilot --yolo` session on a Dev Box, executing as the authenticated user.
- All review comment resolution is done **locally** — not via the remote Copilot coding agent.
- **Do NOT edit any plan/checklist files** (e.g., `1810-ignorance-reduction-for-implementation-plan.md`) to mark tasks as complete. Marking checklist items is outside the scope of this skill.
