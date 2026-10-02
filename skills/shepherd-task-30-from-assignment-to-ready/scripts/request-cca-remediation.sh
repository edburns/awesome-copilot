#!/usr/bin/env bash
# shepherd-task-version: 1.0.4
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GH_COMMAND="${GH_COMMAND:-gh}"
CLOCK_COMMAND="${SHEPHERD_REMEDIATION_CLOCK_COMMAND:-}"
SLEEP_COMMAND="${SHEPHERD_REMEDIATION_SLEEP_COMMAND:-sleep}"
PHASE_A_MS=120000
PHASE_C_MS=600000
REQUEST_MS=60000
started=0 deadline=0 phase_start=0 reassigned=false
request_id=null boundary="" original="" current=""
snapshot='{}' baseline='{}'
repo="${1:-}" issue="${2:-}" number="${3:-}" base="${4:-}"
expected="${5:-}" review_file="${6:-}"

fail() {
    finish "$1" "$2" "$3"
}

now() {
    local value
    if [[ -n "$CLOCK_COMMAND" ]]; then
        value="$("$CLOCK_COMMAND")"
    else
        value="$(perl "$SCRIPT_DIR/cca-remediation-clock.pl" now)"
    fi
    [[ "$value" =~ ^[0-9]+$ ]] || { echo "Invalid monotonic clock output" >&2; return 1; }
    printf '%s\n' "$value"
}

finish() {
    local outcome="$1" code="$2" message="$3" ended elapsed
    ended="$(now)"
    elapsed=$((ended - started))
    ((started > 0)) || elapsed=0
    printf '%s\n%s\n' "$snapshot" "$baseline" | jq -s --arg outcome "$outcome" --arg message "$message" \
        --arg repo "$repo" --arg issue "$issue" --arg pr "$number" \
        --arg base "$base" --arg original "$original" --arg current "$current" \
        --arg boundary "$boundary" --arg observedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson requestId "$request_id" --argjson reassigned "$reassigned" \
        --argjson elapsed "$elapsed" '
      .[0] as $snapshot | .[1] as $baseline |
      {schemaVersion:1, outcome:$outcome, message:$message,
       repository:$repo, issueNumber:$issue, prNumber:$pr, expectedBase:$base,
       requestId:$requestId, requestSubmittedAt:$boundary, observedAt:$observedAt,
       originalHead:$original, currentHead:$current, headChanged:($original != $current),
       reassignmentAttempted:$reassigned, elapsedMs:$elapsed,
       phaseABudgetMs:120000, phaseCBudgetMs:600000,
       latestStart:($snapshot.latestStart // null),
       latestFinish:($snapshot.latestFinish // null),
       latestFailure:($snapshot.latestFailure // null),
       descriptionChanged:(if ($snapshot.body | type) == "string" and
           ($baseline.body | type) == "string" then $snapshot.body != $baseline.body else null end),
       acceptance:"not-evaluated",
       nextAction:(if $outcome == "cycle-completed" then "revalidate" else "stop" end)}'
    if ((code != 0)); then
        printf 'SHEPHERD FAILED: %s: %s\n' "$outcome" "$message" >&2
    fi
    exit "$code"
}

for tool in jq perl "$GH_COMMAND" "$SLEEP_COMMAND"; do
    command -v "$tool" >/dev/null || { echo "Required command not found: $tool" >&2; exit 2; }
done
started="$(now)"
[[ $# == 6 && "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ &&
   "$issue" =~ ^[1-9][0-9]*$ && "$number" =~ ^[1-9][0-9]*$ &&
   -n "$base" && "$expected" =~ ^[0-9a-f]{40}$ && -s "$review_file" ]] ||
    fail invalid-input 2 "Usage: $0 OWNER/REPO ISSUE PR BASE EXPECTED_HEAD REVIEW_BODY_FILE"

temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
printf '{}\n' >"$temp/baseline.json"
query='query($owner:String!,$name:String!,$number:Int!,$endCursor:String){repository(owner:$owner,name:$name){pullRequest(number:$number){number state isDraft baseRefName headRefOid body closingIssuesReferences(first:100,after:$endCursor){nodes{number repository{nameWithOwner}}pageInfo{hasNextPage endCursor}}}}}'

gh_call() {
    local output="$1" remaining status
    shift
    remaining=$REQUEST_MS
    if ((deadline > 0)); then
        remaining=$((deadline - $(now)))
        ((remaining > 0)) || timeout_result
        ((remaining <= REQUEST_MS)) || remaining=$REQUEST_MS
    fi
    if perl "$SCRIPT_DIR/cca-remediation-clock.pl" run "$remaining" \
        "$GH_COMMAND" "$@" >"$output" 2>"$temp/gh-error"; then
        :
    else
        status=$?
        cat "$temp/gh-error" >&2
        if ((status == 124 && deadline > 0 && $(now) >= deadline)); then timeout_result; fi
        fail api-error 3 "GitHub command failed (exit $status); request state may need reconciliation"
    fi
}

read_snapshot() {
    local observed
    gh_call "$temp/pr.json" api graphql --paginate --slurp \
        -f query="$query" -f owner="${repo%%/*}" -f name="${repo#*/}" -F number="$number"
    gh_call "$temp/timeline.json" api "/repos/$repo/issues/$number/timeline?per_page=100" \
        --paginate --slurp -H "Accept: application/vnd.github+json"
    if observed="$(jq -n --slurpfile pr "$temp/pr.json" --slurpfile timeline "$temp/timeline.json" \
        --slurpfile baseline "$temp/baseline.json" \
        --arg repo "$repo" --arg issue "$issue" --arg number "$number" --arg base "$base" \
        --arg boundary "$boundary" -f "$SCRIPT_DIR/cca-remediation-state.jq")"; then
        snapshot="$observed"
        current="$(jq -r '.head' <<<"$snapshot")"
    else
        fail invalid-state 4 "Malformed response or authoritative PR/lifecycle invariant violation"
    fi
}

timeout_result() {
    if [[ "$current" != "$original" ]]; then
        fail changed-head-incomplete-cycle 8 "HEAD changed but no completed fresh CCA cycle was verified before the deadline"
    fi
    fail unchanged-head-timeout 8 "No completed fresh CCA cycle was verified before the deadline"
}

pause() {
    local seconds="$1" remaining
    remaining=$((deadline - $(now)))
    ((remaining > 0)) || return 0
    ((seconds * 1000 <= remaining)) || seconds=$(((remaining + 999) / 1000))
    "$SLEEP_COMMAND" "$seconds"
}

read_snapshot
original="$current"
[[ "$original" == "$expected" ]] || fail invalid-state 4 "HEAD changed before the remediation request"
if jq -e '.latestStart != null and (.completed or .failed | not)' <<<"$snapshot" >/dev/null; then
    fail invalid-state 4 "A CCA cycle is already active; do not submit an overlapping request"
fi
baseline="$snapshot"
printf '%s\n' "$baseline" >"$temp/baseline.json"
jq -n --rawfile body "$review_file" --arg commit "$original" \
    '{body:$body,event:"REQUEST_CHANGES",commit_id:$commit}' >"$temp/review-input.json"
# Snapshot before the mutation; use the server's submission time, not local wall-clock time.
gh_call "$temp/review.json" api --method POST "/repos/$repo/pulls/$number/reviews" \
    --input "$temp/review-input.json"
if ! jq -e --rawfile body "$review_file" --arg commit "$original" '
    (.id | type) == "number" and .id > 0 and .state == "CHANGES_REQUESTED" and
    .body == $body and .commit_id == $commit and
    (.submitted_at | type) == "string" and
    (.submitted_at | test("^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ$"))
  ' "$temp/review.json" >/dev/null; then
    fail invalid-state 4 "Review submission response did not confirm the requested body and HEAD"
fi
request_id="$(jq -r '.id' "$temp/review.json")"
boundary="$(jq -r '.submitted_at' "$temp/review.json")"
phase_start="$(now)"
deadline=$((phase_start + PHASE_A_MS))
gh_call "$temp/readback.json" api "/repos/$repo/pulls/$number/reviews/$request_id"
if ! jq -e --slurpfile sent "$temp/review.json" '
    .id == $sent[0].id and .body == $sent[0].body and
    .commit_id == $sent[0].commit_id and .state == "CHANGES_REQUESTED" and
    .submitted_at == $sent[0].submitted_at' "$temp/readback.json" >/dev/null; then
    fail invalid-state 4 "Remediation review failed read-after-write verification"
fi

engaged=false
while (($(now) < deadline)); do
    read_snapshot
    (($(now) < deadline)) || break
    if jq -e '.latestStart != null' <<<"$snapshot" >/dev/null || [[ "$current" != "$original" ]]; then
        engaged=true
        break
    fi
    pause 15
done
if [[ "$engaged" != true ]]; then
    deadline=0
    reassigned=true
    jq -n --arg repo "$repo" --arg base "$base" '
      {assignees:["copilot-swe-agent[bot]"],agent_assignment:{target_repo:$repo,base_branch:$base}}' \
        >"$temp/assignment.json"
    gh_call "$temp/assigned.json" api --method POST "/repos/$repo/issues/$issue/assignees" \
        -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
        --input "$temp/assignment.json"
    if ! jq -e '(.assignees | type) == "array" and
        any(.assignees[]; .login == "copilot-swe-agent[bot]")' "$temp/assigned.json" >/dev/null; then
        fail invalid-state 4 "Reassignment was not confirmed"
    fi
fi
phase_start="$(now)"
deadline=$((phase_start + PHASE_C_MS))
while (($(now) < deadline)); do
    read_snapshot
    (($(now) < deadline)) || break
    if jq -e '.failed' <<<"$snapshot" >/dev/null; then
        fail agent-failed 9 "Fresh CCA cycle explicitly failed; substantive changes still require validation"
    fi
    if jq -e '.completed' <<<"$snapshot" >/dev/null; then
        candidate="$current"
        read_snapshot
        (($(now) < deadline)) || break
        if [[ "$candidate" == "$current" ]] && jq -e '.completed and (.failed | not)' <<<"$snapshot" >/dev/null; then
            finish cycle-completed 0 "Fresh CCA cycle completed; correction and readiness have NOT been accepted"
        fi
    fi
    pause 30
done
timeout_result
