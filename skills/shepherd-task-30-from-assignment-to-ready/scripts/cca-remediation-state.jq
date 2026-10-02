# Shared data validation for the native Bash and PowerShell remediation drivers.
def require($condition; $message):
  if $condition then . else error($message) end;

def lifecycle:
  map(select(.event? | strings | startswith("copilot_work_")))
  | require(all(.[]; (.performed_via_github_app.slug? | type) == "string");
      "Lifecycle event has no app identity")
  | map(select(.performed_via_github_app.slug == "copilot-swe-agent"))
  | require(all(.[];
      (.id | type) == "number" and .id > 0 and .id < 9007199254740992 and
      .id == (.id | floor) and
      (.created_at | type) == "string" and
      (.created_at | test("^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ$")) and
      (.created_at | fromdateiso8601 | todateiso8601) == .created_at and
      (.event == "copilot_work_started" or .event == "copilot_work_finished" or
       .event == "copilot_work_finished_failure"));
      "Malformed or unsupported CCA lifecycle event")
  | require((group_by(.id) | all(.[]; (map({event, created_at}) | unique | length) == 1));
      "Conflicting duplicate lifecycle event IDs")
  | unique_by(.id) | sort_by(.created_at, .id)
  | map({id, event, created_at});

def pull_request:
  $pr[0]
  | require(type == "array" and length > 0; "Missing GraphQL pages")
  | require(all(.[];
      (.errors? == null) and
      (.data.repository.pullRequest | type) == "object");
      "GraphQL query failed or PR is missing")
  | map(.data.repository.pullRequest)
  | . as $pages
  | require(all(.[]; .number == ($number | tonumber) and .state == "OPEN" and
      .isDraft == true and .baseRefName == $base and
      (.headRefOid | type) == "string" and
      (.headRefOid | test("^[0-9a-f]{40}$")) and
      (.body | type) == "string" and
      (.closingIssuesReferences.nodes | type) == "array" and
      (.closingIssuesReferences.pageInfo.hasNextPage | type) == "boolean");
      "PR identity, state, draft, base, HEAD or linkage response is invalid")
  | require(all(.[]; .headRefOid == $pages[0].headRefOid and .body == $pages[0].body);
      "PR changed during paginated query; restart validation")
  | require(.[-1].closingIssuesReferences.pageInfo.hasNextPage == false;
      "Incomplete closing-issue pagination")
  | require(any(.[].closingIssuesReferences.nodes[];
      .number == ($issue | tonumber) and .repository.nameWithOwner == $repo);
      "PR does not authoritatively close the exact repository issue")
  | {head: .[0].headRefOid, body: .[0].body};

pull_request as $pull
| $timeline[0]
| require(type == "array" and all(.[]; type == "array"); "Invalid timeline pages")
| add // []
| lifecycle as $events
| (if $boundary == "" then $events else
    ($baseline[0].events | map(.id)) as $seen
    | $events | map(select(.created_at >= $boundary and
        (.id as $id | $seen | index($id) | not)))
  end) as $fresh
| ($fresh | map(select(.event == "copilot_work_started")) | last) as $start
| ($fresh | map(select(.event != "copilot_work_started")) | last) as $terminal
| ($start != null and $terminal != null and
    [$terminal.created_at, $terminal.id] > [$start.created_at, $start.id]) as $ended
| $pull + {
    events: $events,
    latestStart: $start,
    latestFinish: ($fresh | map(select(.event == "copilot_work_finished")) | last),
    latestFailure: ($fresh | map(select(.event == "copilot_work_finished_failure")) | last),
    completed: ($ended and $terminal.event == "copilot_work_finished"),
    failed: ($ended and $terminal.event == "copilot_work_finished_failure")
  }
