#!/usr/bin/env bash
# shepherd-task-version: 1.0.4
set -euo pipefail
state="$REMEDIATION_FIXTURE/state.json"
action="$(basename "$0" .sh)"
update() {
    jq "$@" "$state" >"$state.tmp"
    mv "$state.tmp" "$state"
}
fail() { echo "Unexpected mock request: $*" >&2; exit 90; }
case "$action" in
    clock) jq -r '.time' "$state"; exit ;;
    sleep) update --argjson seconds "$1" '.time += $seconds * 1000'; exit ;;
    gh) ;;
    *) fail "$action" ;;
esac
[[ "$1" == api ]] || fail "$@"
scenario="$(jq -r '.scenario' "$state")"
case "$scenario" in
    api-error) echo 'mock API failure' >&2; exit 19 ;;
    malformed-json) echo 'not json'; exit ;;
esac
method="" endpoint="" input="" previous=""
for argument in "$@"; do
    case "$previous" in --method) method="$argument" ;; --input) input="$argument" ;; esac
    case "$argument" in /repos/*) endpoint="$argument" ;; repos/*) endpoint="/$argument" ;; esac
    previous="$argument"
done
sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
if [[ "$method" == POST && "$endpoint" == */reviews ]]; then
    jq -e --arg sha "$sha" '.event == "REQUEST_CHANGES" and .commit_id == $sha' "$input" >/dev/null || fail review
    update --slurpfile input "$input" '
      .posts += 1 | .review = {id:50,state:"CHANGES_REQUESTED",body:$input[0].body,
        commit_id:$input[0].commit_id,submitted_at:"2026-10-02T12:00:00Z"}'
    [[ "$scenario" != uncertain-review ]] || { echo 'mock connection lost after review mutation' >&2; exit 19; }
    jq '.review' "$state"; exit
fi
if [[ "$endpoint" == */reviews/50 ]]; then
    case "$scenario" in phase-a-readback-overrun|bad-readback-overrun) update '.time += 120000' ;; esac
    jq --arg scenario "$scenario" '.review |
      if ($scenario == "bad-readback" or $scenario == "bad-readback-overrun") then .body = "not published" else . end' "$state"
    exit
fi
if [[ "$method" == POST && "$endpoint" == */assignees ]]; then
    jq -e '. == {assignees:["copilot-swe-agent[bot]"],
      agent_assignment:{target_repo:"owner/repo",base_branch:"campaign-base"}}' "$input" >/dev/null || fail assignment
    update '.assigned += 1'
    [[ "$scenario" != uncertain-reassignment ]] || { echo 'mock connection lost after reassignment mutation' >&2; exit 19; }
    echo '{"assignees":[{"login":"copilot-swe-agent[bot]"}]}'; exit
fi
if [[ "$2" == graphql || "$endpoint" == */timeline?* ]]; then
    [[ " $* " == *" --paginate "* && " $* " == *" --slurp "* ]] || fail pagination
fi
if [[ "$2" == graphql ]]; then
    update '
      if (.scenario == "phase-a-query-overrun" and .poll == 1) then .time += 120000
      elif ((.scenario == "phase-c-query-overrun" and .poll == 2) or
            (.scenario == "final-query-overrun" and .poll == 3)) then .time += 600000 else . end
      | .poll += 1'
    jq --arg sha "$sha" '
      .scenario as $s | (.poll - 1) as $poll |
      {number:11,state:"OPEN",isDraft:true,baseRefName:"campaign-base",headRefOid:$sha,
       body:(if $poll > 0 and (["evidence","pagination"] | index($s)) then "Concrete evidence on HEAD " + $sha else "Original body" end),
       closingIssuesReferences:{nodes:[{number:6,repository:{nameWithOwner:"owner/repo"}}],
                                pageInfo:{hasNextPage:false,endCursor:null}}}
      | if (($poll > 0 and (["changed","partial","stale","newer-start","failed-diff"] | index($s))) or
            $s == "head-before-request" or ($s == "head-drift" and $poll >= 3))
        then .headRefOid = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" else . end
      | if $s == "wrong-base" and $poll > 0 then .baseRefName = "main" else . end
      | if $s == "closed" then .state = "CLOSED" else . end
      | if $s == "ready" then .isDraft = false else . end
      | if $s == "wrong-issue" then .closingIssuesReferences.nodes[0].number = 60 else . end
      | if $s == "wrong-repo" then .closingIssuesReferences.nodes[0].repository.nameWithOwner = "other/repo" else . end
      | if $s == "graphql-error" then [{errors:[{message:"unavailable"}]}]
        elif $s == "pagination" then . as $pr |
          [($pr | .closingIssuesReferences = {nodes:[],pageInfo:{hasNextPage:true,endCursor:"next"}}),$pr]
          | map({data:{repository:{pullRequest:.}}})
        else [{data:{repository:{pullRequest:.}}}] end' "$state"
    exit
fi
if [[ "$endpoint" == */timeline?* ]]; then
    update '
      if .scenario == "late-completion" and .poll >= 3 then .time += 600000
      elif .scenario == "phase-a-timeline-overrun" and .poll == 2 then .time += 120000
      elif .scenario == "final-timeline-overrun" and .poll == 4 then .time += 600000 else . end'
    jq '
      def event($id; $kind; $time):
        {id:$id,event:("copilot_work_" + $kind),created_at:$time,performed_via_github_app:{slug:"copilot-swe-agent"}};
      def fresh($id; $kind): event($id; $kind; "2026-10-02T12:00:00Z");
      .scenario as $s | .assigned as $assigned | (.poll - 1) as $poll |
      [event(1;"started";"2026-10-02T11:00:00Z"),event(2;"finished";"2026-10-02T11:01:00Z")]
      | if $s == "active-before-request" then . + [event(3;"started";"2026-10-02T11:59:59Z")]
        elif $s == "same-second-baseline" then [fresh(90;"started"),fresh(91;"finished")] else . end
      | . as $old |
      (if $poll == 0 then [] else
        [fresh(100;"started"),fresh(101;"finished")]
        | if (["partial","stale"] | index($s)) then [fresh(100;"started")] else . end
        | if $s == "newer-start" or ($s == "head-drift" and $poll >= 3)
          then . + [event(102;"started";"2026-10-02T12:00:01Z")] else . end
        | if $s == "orphan-finish" then [fresh(101;"finished")] else . end
        | if $s == "reverse-same-second" then [fresh(99;"finished"),fresh(100;"started")] else . end
        | if (["failed","failed-diff"] | index($s)) then [fresh(100;"started"),fresh(101;"finished_failure")] else . end
        | if $s == "missing-timestamp" then del(.[0].created_at) else . end
        | if $s == "invalid-date" then .[0].created_at = "2026-99-02T12:00:00Z" else . end
        | if $s == "conflicting-id" then . + [fresh(101;"started")] else . end
        | if $s == "missing-app" then del(.[0].performed_via_github_app) else . end
        | if $s == "foreign-agent" then map(.performed_via_github_app.slug = "copilot-pull-request-reviewer") else . end
        | if (["no-engagement","uncertain-reassignment","stale-only"] | index($s)) or
            ($s == "reassign" and $assigned == 0) then [] else . end
        end) as $new |
      if $s == "pagination" then [$old + [range(98) | {event:"commented"}],$new] else [$old + $new] end' "$state"
    exit
fi
if [[ "$endpoint" == /repos/owner/repo/issues/11 ]]; then
    jq -n --arg scenario "$scenario" --arg sha "$sha" \
      '{body:(if $scenario == "evidence" then "Concrete evidence on HEAD " + $sha else "Original body" end)}'
    exit
fi
fail "$@"
