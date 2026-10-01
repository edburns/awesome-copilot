#!/usr/bin/env bash
# shepherd-task-version: 1.0.4
#
# redact-secrets.sh — Redact secret-bearing fields from shepherd JSONL logs.
#
# Usage: ./redact-secrets.sh <log-directory>
#        ./redact-secrets.sh -
#   A directory contains .json* files produced by shepherd-task. With "-" the
#   script reads JSONL from stdin and writes redacted JSONL to stdout.

set -euo pipefail

TARGET="${1:?Usage: $0 <log-directory>}"

JQ_FILTER='
    def sensitive_key:
        test("(?i)(password|passwd|secret|token|api[-_]?key|authorization|credential|private[-_]?key|access[-_]?key|client[-_]?secret|connection[-_]?string)");
    def content_key:
        test("(?i)^(content|encryptedContent|reasoningOpaque|arguments|result|error|prompt|toolRequests|userContent|assistantContent|toolCompleteResultContent)$");
    def scrub_string:
        gsub("(?i)bearer[[:space:]]+[A-Za-z0-9._~+/-]+"; "Bearer [REDACTED]")
        | gsub("\\b(?:gh[opsu]_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]+|xox[baprs]-[A-Za-z0-9-]+|AIza[0-9A-Za-z_-]+)"; "[REDACTED]")
        | gsub("[A-Za-z0-9+/]{20,}[+/][A-Za-z0-9+/]{20,}={0,2}"; "[REDACTED]");
    def scrub:
        if type == "object" then
            with_entries(
                if ((.key | sensitive_key) or (.key | content_key)) then
                    .value = "[REDACTED]"
                else
                    .value |= scrub
                end
            )
        elif type == "array" then
            map(scrub)
        elif type == "string" then
            scrub_string
        else
            .
        end;
    scrub
'

command -v jq >/dev/null 2>&1 || {
    echo "jq is required to redact shepherd logs." >&2
    exit 1
}
printf '{}\n' | jq -c "$JQ_FILTER" >/dev/null 2>&1 || {
    echo "Unable to initialize the shepherd JSON redaction filter." >&2
    exit 1
}

emit_invalid_jsonl_record() {
    local line_number="$1"
    local byte_count="$2"
    jq -cn \
        --argjson line "$line_number" \
        --argjson byteCount "$byte_count" \
        '{
            type: "shepherd.redaction_warning",
            data: {
                reason: "invalid_jsonl_record",
                line: $line,
                byteCount: $byteCount
            }
        }'
}

redact_jsonl_stream() {
    local context="$1"
    local line=""
    local line_number=0
    local invalid_count=0
    local redacted=""
    local jq_exit=0
    local byte_count=0
    local jq_error_file
    jq_error_file="$(mktemp)"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        if [[ -z "$line" ]]; then
            printf '\n'
            continue
        fi

        : >"$jq_error_file"
        if redacted="$(printf '%s\n' "$line" | LC_ALL=C jq -c "$JQ_FILTER" 2>"$jq_error_file")"; then
            printf '%s\n' "$redacted"
            continue
        else
            jq_exit=$?
        fi

        if ! grep -q '^jq: parse error:' "$jq_error_file"; then
            rm -f "$jq_error_file"
            echo "Redaction failed for $context at line $line_number; jq exited $jq_exit." >&2
            return "$jq_exit"
        fi

        byte_count="$(LC_ALL=C printf '%s' "$line" | wc -c | tr -d '[:space:]')"
        emit_invalid_jsonl_record "$line_number" "$byte_count"
        invalid_count=$((invalid_count + 1))
        echo "Replaced invalid JSONL record in $context at line $line_number ($byte_count bytes)." >&2
    done

    rm -f "$jq_error_file"
    if [[ $invalid_count -gt 0 ]]; then
        echo "Recovered $invalid_count invalid JSONL record(s) in $context." >&2
    fi
}

redact_file() {
    local file="$1"
    local temp
    temp=$(mktemp "${file}.redact.XXXXXX")

    if [[ "$file" == *.jsonl ]]; then
        if ! redact_jsonl_stream "$file" <"$file" >"$temp"; then
            rm -f "$temp"
            echo "Unable to redact JSONL; left unchanged: $file" >&2
            exit 1
        fi
    elif ! jq "$JQ_FILTER" "$file" >"$temp"; then
        rm -f "$temp"
        echo "Invalid JSON; left unchanged: $file" >&2
        exit 1
    fi

    local mode
    if mode="$(stat -f '%Lp' "$file" 2>/dev/null)" &&
        [[ "$mode" =~ ^[0-7]{3,4}$ ]]; then
        :
    elif mode="$(stat -c '%a' "$file" 2>/dev/null)" &&
        [[ "$mode" =~ ^[0-7]{3,4}$ ]]; then
        :
    else
        rm -f "$temp"
        echo "Unable to determine file mode: $file" >&2
        exit 1
    fi
    chmod "$mode" "$temp"
    mv "$temp" "$file"
    echo "Redacted $file"
}

if [[ "$TARGET" == "-" ]]; then
    redact_jsonl_stream "stdin"
    exit 0
fi

LOG_DIR="$TARGET"
if [[ ! -d "$LOG_DIR" ]]; then
    echo "Log directory not found: $LOG_DIR" >&2
    exit 1
fi

files=()
while IFS= read -r -d '' file; do
    files+=("$file")
done < <(find "$LOG_DIR" -type f -name '*.json*' -print0)
if [[ ${#files[@]} -eq 0 ]]; then
    echo "No .json* files found in $LOG_DIR" >&2
    exit 1
fi

for file in "${files[@]}"; do
    redact_file "$file"
done
