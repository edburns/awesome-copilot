#!/usr/bin/env bash
# shepherd-task-version: 1.0.4
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
skill="shepherd-task-30-from-assignment-to-ready"
for candidate in "$script_dir/../skills/$skill" "$script_dir/../../../skills/$skill"; do
    if [[ -f "$candidate/scripts/request-cca-remediation.sh" ]]; then
        exec bash "$candidate/scripts/request-cca-remediation.sh" "$@"
    fi
done
echo "SHEPHERD FAILED: Bundled Stage 30 remediation helper is missing." >&2
exit 2
