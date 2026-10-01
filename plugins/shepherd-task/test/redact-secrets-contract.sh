#!/usr/bin/env bash
# shepherd-task-version: 1.0.4

set -euo pipefail

test_root="$(cd "$(dirname "$0")" && pwd)"
redactor="$test_root/../scripts/redact-secrets.sh"
temp_root="$(mktemp -d)"
trap 'rm -rf "$temp_root"' EXIT

fake_stream_secret='ghp_stream_secret_must_not_survive'
second_stream_secret='sk-stream-secret-must-not-survive'
stream_output="$temp_root/stream.jsonl"
stream_stderr="$temp_root/stream.stderr"

producer() {
    printf '{"type":"start","token":"ghp_valid_secret"}\n'
    printf 'not-json %s\n' "$fake_stream_secret"
    printf '\n'
    printf 'still-not-json %s\n' "$second_stream_secret"
    printf '{"type":"result","data":{"status":"complete"}}\n'
}

set +e
producer | "$redactor" - >"$stream_output" 2>"$stream_stderr"
pipeline_status=("${PIPESTATUS[@]}")
set -e

[[ ${pipeline_status[0]} -eq 0 && ${pipeline_status[1]} -eq 0 ]] || {
    echo "Malformed JSONL terminated the streaming pipeline: ${pipeline_status[*]}." >&2
    exit 1
}
jq -e . "$stream_output" >/dev/null
jq -s -e '
    any(.[]; .type == "start" and .token == "[REDACTED]") and
    any(.[]; .type == "shepherd.redaction_warning" and
        .data.reason == "invalid_jsonl_record" and .data.line == 2 and
        .data.byteCount > 0) and
    any(.[]; .type == "shepherd.redaction_warning" and
        .data.reason == "invalid_jsonl_record" and .data.line == 4 and
        .data.byteCount > 0) and
    any(.[]; .type == "result" and .data.status == "complete")
' "$stream_output" >/dev/null
[[ "$(jq -s '[.[] | select(.type == "shepherd.redaction_warning")] | length' "$stream_output")" -eq 2 ]]
! grep -Fq "$fake_stream_secret" "$stream_output"
! grep -Fq "$second_stream_secret" "$stream_output"
grep -Fq 'Recovered 2 invalid JSONL record(s) in stdin.' "$stream_stderr"

log_directory="$temp_root/logs"
mkdir -p "$log_directory"
directory_jsonl="$log_directory/session.jsonl"
cat >"$directory_jsonl" <<EOF
{"type":"before","password":"directory-secret"}
malformed ghp_directory_secret_must_not_survive
{"type":"after","data":{"status":"complete"}}
EOF
chmod 640 "$directory_jsonl"

"$redactor" "$log_directory" >"$temp_root/directory.stdout" 2>"$temp_root/directory.stderr"
jq -e . "$directory_jsonl" >/dev/null
jq -s -e '
    any(.[]; .type == "before" and .password == "[REDACTED]") and
    any(.[]; .type == "shepherd.redaction_warning" and .data.line == 2) and
    any(.[]; .type == "after" and .data.status == "complete")
' "$directory_jsonl" >/dev/null
! grep -Fq 'ghp_directory_secret_must_not_survive' "$directory_jsonl"
[[ "$(stat -c '%a' "$directory_jsonl")" == "640" ]]

invalid_json="$log_directory/invalid.json"
printf '{not-json ghp_document_secret}\n' >"$invalid_json"
invalid_before="$(sha256sum "$invalid_json" | cut -d' ' -f1)"
set +e
"$redactor" "$log_directory" >"$temp_root/invalid.stdout" 2>"$temp_root/invalid.stderr"
invalid_exit=$?
set -e
[[ $invalid_exit -ne 0 ]]
[[ "$(sha256sum "$invalid_json" | cut -d' ' -f1)" == "$invalid_before" ]]
! find "$log_directory" -type f -name '*.redact.*' -print -quit | grep -q .

set +e
printf '{"type":"result"}\n' |
    PATH=/nonexistent /bin/bash "$redactor" - \
        >"$temp_root/no-jq.stdout" 2>"$temp_root/no-jq.stderr"
missing_jq_status=("${PIPESTATUS[@]}")
set -e
[[ ${missing_jq_status[1]} -ne 0 ]]
grep -Fq 'jq is required to redact shepherd logs.' "$temp_root/no-jq.stderr"

echo 'Bash secret redaction contract tests passed.'
