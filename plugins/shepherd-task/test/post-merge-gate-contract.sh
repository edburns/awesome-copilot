#!/usr/bin/env bash
# shepherd-task-version: 1.0.4

set -euo pipefail

test_root="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$test_root/../../.." && pwd)"
stage20="$repo_root/skills/shepherd-task-20-create-issues-from-plan/SKILL.md"
stage30="$repo_root/skills/shepherd-task-30-from-assignment-to-ready/SKILL.md"
stage40="$repo_root/skills/shepherd-task-40-from-ready-to-merged-to-base/SKILL.md"
readme="$repo_root/plugins/shepherd-task/README.md"
orchestrator="$repo_root/plugins/shepherd-task/scripts/shepherd-task.sh"

for required in \
    '## Post-merge completion gates' \
    'Never place a post-merge-only predicate under `## Completion gates`'; do
    grep -Fq -- "$required" "$stage20" || {
        echo "Stage 20 is missing post-merge issue-authoring guidance: $required" >&2
        exit 1
    }
done

for required in \
    'PASS/DEFERRED/FAIL' \
    'intrinsically impossible before merge' \
    'concrete Stage 40 post-merge verification plan' \
    'No implementation, current-head CI, review, or test criterion may be deferred'; do
    grep -Fq -- "$required" "$stage30" || {
        echo "Stage 30 is missing deferred-gate safeguards: $required" >&2
        exit 1
    }
done

for required in \
    '### Step 0.1: Reconstruct post-merge gates' \
    'The primary merge SHA is the immutable anchor' \
    '--commit "$MERGE_SHA"' \
    '--event push' \
    'separate evidence-only PR' \
    'gh issue reopen "$TASK_ISSUE" -R "$REPO"' \
    'No `DEFERRED`, `FAIL`, or `UNKNOWN` row may remain'; do
    grep -Fq -- "$required" "$stage40" || {
        echo "Stage 40 is missing post-merge enforcement: $required" >&2
        exit 1
    }
done

grep -Fq 'captures the primary merge SHA' "$readme" &&
    grep -Fq 'closes the task issue only after no deferred' "$readme" || {
    echo 'Plugin README does not describe post-merge completion.' >&2
    exit 1
}

grep -Fq 'resuming Phase 2 post-merge verification' "$orchestrator" &&
    grep -Fq 'PR_NUMBER=$(find_linked_pr MERGED)' "$orchestrator" || {
    echo 'Bash orchestrator cannot resume post-merge verification.' >&2
    exit 1
}
if grep -Fq 'skipping Phase 2' "$orchestrator"; then
    echo 'Bash orchestrator still skips Stage 40 for an open issue with a merged PR.' >&2
    exit 1
fi

echo 'Post-merge gate contract tests passed.'
