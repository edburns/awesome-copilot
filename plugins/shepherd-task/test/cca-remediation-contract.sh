#!/usr/bin/env bash
# shepherd-task-version: 1.0.4
set -euo pipefail
test_root="$(cd "$(dirname "$0")" && pwd)"
plugin_root="$(cd "$test_root/.." && pwd)"
skill_name=shepherd-task-30-from-assignment-to-ready
skill_root="$plugin_root/../../skills/$skill_name"
[[ -d "$skill_root" ]] || skill_root="$plugin_root/skills/$skill_name"
fixtures="$test_root/fixtures/cca-remediation"
temp_root="$(mktemp -d)"
trap 'rm -rf "$temp_root"' EXIT
results_path="${1:-}"
[[ -z "$results_path" ]] || : >"$results_path"
export REMEDIATION_FIXTURE="$temp_root"
export GH_COMMAND="$temp_root/bin/gh"
export SHEPHERD_REMEDIATION_CLOCK_COMMAND="$temp_root/bin/clock"
export SHEPHERD_REMEDIATION_SLEEP_COMMAND="$temp_root/bin/sleep"
mkdir -p "$temp_root/bin"
for command in gh clock sleep; do
    cp "$fixtures/mock.sh" "$temp_root/bin/$command"
    chmod +x "$temp_root/bin/$command"
done
# Any accidental use of these runtimes must fail, including inside a mock.
for command in node npm perl; do
    cat >"$temp_root/bin/$command" <<'EOF'
#!/bin/sh
echo "Unexpected runtime invocation: $0" >&2
echo "$0" >>"$REMEDIATION_FIXTURE/forbidden-runtime"
exit 99
EOF
    chmod +x "$temp_root/bin/$command"
done
export PATH="$temp_root/bin:$PATH"
sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
printf '@copilot Please publish concrete evidence.\n' >"$temp_root/review.txt"
count=0
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { count=$((count + 1)); printf 'PASS: %s\n' "$1"; }
reset_fixture() {
    jq -n --arg scenario "$1" \
        '{scenario:$scenario,time:1000000,poll:0,posts:0,assigned:0}' >"$temp_root/state.json"
}
invoke() {
    local script="${1:-$plugin_root/scripts/request-cca-remediation.sh}"
    if bash "$script" owner/repo 6 11 campaign-base "$sha" "$temp_root/review.txt" \
        >"$temp_root/result.json" 2>"$temp_root/error.txt"; then
        actual_code=0
    else
        actual_code=$?
    fi
    jq -e 'type == "object"' "$temp_root/result.json" >/dev/null || {
        cat "$temp_root/error.txt" >&2
        fail "No JSON result"
    }
}
assert_result() {
    local scenario="$1" code="$2" outcome="$3"
    [[ "$actual_code" == "$code" ]] || { cat "$temp_root/error.txt" >&2; fail "$scenario: expected $code, got $actual_code"; }
    jq -e --arg outcome "$outcome" --argjson code "$code" '
      .schemaVersion == 1 and .outcome == $outcome and .acceptance == "not-evaluated" and
      .nextAction == (if $code == 0 then "revalidate" else "stop" end) and
      (if $code == 8 then .elapsedMs >= 600000 else true end)' "$temp_root/result.json" >/dev/null || fail "$scenario: result contract"
    ! grep -q 'SHEPHERD COMPLETE' "$temp_root/result.json" || fail "$scenario: accepted readiness"
    if [[ "$code" != 0 ]]; then grep -q 'SHEPHERD FAILED' "$temp_root/error.txt" || fail "$scenario: failure diagnostic"; fi
    jq -e '.posts <= 1 and .assigned <= 1' "$temp_root/state.json" >/dev/null || fail "$scenario: duplicate mutation"
    case "$scenario" in
        evidence) jq -e '.descriptionChanged == true and .headChanged == false' "$temp_root/result.json" >/dev/null ;;
        no-publication) jq -e '.descriptionChanged == false and .headChanged == false' "$temp_root/result.json" >/dev/null ;;
        changed) jq -e '.headChanged == true' "$temp_root/result.json" >/dev/null ;;
        active-before-request) jq -e '.posts == 0' "$temp_root/state.json" >/dev/null ;;
        reassign) jq -e '.assigned == 1' "$temp_root/state.json" >/dev/null ;;
        uncertain-*)
            jq -e --arg scenario "$scenario" '.posts == 1 and .assigned ==
                (if $scenario == "uncertain-reassignment" then 1 else 0 end)' "$temp_root/state.json" >/dev/null
            grep -q 'request state may need reconciliation' "$temp_root/error.txt"
            ;;
        phase-a-*)
            jq -e '.assigned == 1 and .posts == 1 and .poll >= 3' "$temp_root/state.json" >/dev/null
            jq -e '.elapsedMs >= 120000' "$temp_root/result.json" >/dev/null
            ;;
        *overrun) jq -e '.posts == 1 and .assigned == 0' "$temp_root/state.json" >/dev/null ;;
    esac
}

while read -r scenario code outcome scope; do
    reset_fixture "$scenario"
    invoke
    assert_result "$scenario" "$code" "$outcome"
    if [[ "$scope" == both && -n "$results_path" ]]; then
        jq -cS --arg scenario "$scenario" 'del(.observedAt,.message) + {scenario:$scenario}' \
            "$temp_root/result.json" >>"$results_path"
    fi
    pass "$scenario"
done <"$fixtures/cases.tsv"

printf 'Concrete evidence on HEAD %s' "$sha" >"$temp_root/expected.md"
for scenario in evidence no-publication; do
    reset_fixture "$scenario"
    invoke
    assert_result "$scenario" 0 cycle-completed
    if bash "$plugin_root/scripts/verify-github-issue-body.sh" owner/repo 11 \
        "$temp_root/expected.md" 1 0 >"$temp_root/publication.out" 2>&1; then
        publication_code=0
    else
        publication_code=$?
    fi
    if [[ "$scenario" == evidence ]]; then [[ "$publication_code" == 0 ]]; else [[ "$publication_code" != 0 ]]; fi
    pass "publication: $scenario"
done

mkdir -p "$temp_root/published/skills"
cp -R "$plugin_root/scripts" "$temp_root/published/scripts"
cp -R "$skill_root" "$temp_root/published/skills/$skill_name"
cp -R "$skill_root" "$temp_root/standalone"
for scripts in "$skill_root/scripts" "$temp_root/published/scripts" "$temp_root/standalone/scripts"; do
    reset_fixture evidence
    invoke "$scripts/request-cca-remediation.sh"
    assert_result evidence 0 cycle-completed
    pass "layout: $scripts"
done
export COPILOT_HOME="$temp_root/copilot-home"
bash "$plugin_root/scripts/install-task-shepherd.sh" >"$temp_root/install.out"
for destination in "$COPILOT_HOME/skills/$skill_name" "$COPILOT_HOME/plugins/shepherd-task/skills/$skill_name"; do
    for asset in request-cca-remediation.sh request-cca-remediation.ps1 cca-remediation-state.jq; do
        cmp "$skill_root/scripts/$asset" "$destination/scripts/$asset"
    done
    [[ ! -e "$destination/scripts/cca-remediation-clock.pl" ]]
done
for scripts in "$COPILOT_HOME/plugins/shepherd-task/scripts" "$COPILOT_HOME/skills/$skill_name/scripts"; do
    reset_fixture evidence
    invoke "$scripts/request-cca-remediation.sh"
    assert_result evidence 0 cycle-completed
    pass "installed layout: $scripts"
done

for final in \
    '{"outcome":"cycle-completed","acceptance":"not-evaluated","nextAction":"revalidate"}' \
    '**SHEPHERD FAILED:** Ineffective remediation on PR #11 for task #6: implementation unchanged.'; do
    printf '# Copilot CLI Session\n\n### Copilot\n\n%s\n' "$final" >"$temp_root/session.md"
    if bash "$plugin_root/scripts/assert-shepherd-session-outcome.sh" "$temp_root/session.md" 30 6 11 \
        >"$temp_root/outcome.out" 2>&1; then fail 'Outer gate accepted lifecycle-only/ineffective result'; fi
    grep -Eq 'did not report a terminal|reported semantic failure' "$temp_root/outcome.out" || fail 'Outer gate failed for wrong reason'
    pass 'outer outcome rejection'
done
printf '# Copilot CLI Session\n\n### Copilot\n\n**SHEPHERD COMPLETE:** PR #11 for task #6 is ready for marking as Ready for review.\n' >"$temp_root/session.md"
bash "$plugin_root/scripts/assert-shepherd-session-outcome.sh" "$temp_root/session.md" 30 6 11 >"$temp_root/outcome.out"
pass 'outer outcome positive control'
grep -Fq 'Use the same committed remediation helper as Step 7' "$skill_root/SKILL.md"
grep -Fq 'rerun all normal gates' "$skill_root/references/cca-remediation-loop.md"
grep -Fq 'ineffective' "$skill_root/references/cca-remediation-loop.md"
! grep -Fq 'while [' "$skill_root/references/cca-remediation-loop.md"
for asset in request-cca-remediation.sh request-cca-remediation.ps1 cca-remediation-state.jq; do
    grep -Fq "scripts/$asset" "$skill_root/SKILL.md"
done
pass 'skill wiring and acceptance boundary'

real_date="$(command -v date)"
export REMEDIATION_REAL_DATE="$real_date"
cat >"$temp_root/bin/date" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$REMEDIATION_FIXTURE/date-calls"
exec "$REMEDIATION_REAL_DATE" "$@"
EOF
chmod +x "$temp_root/bin/date"
unset SHEPHERD_REMEDIATION_CLOCK_COMMAND
reset_fixture evidence
before="$(date +%s)"
invoke
after="$(date +%s)"
assert_result evidence 0 cycle-completed
jq -e --argjson maximum "$(((after - before + 1) * 1000))" \
    '.elapsedMs >= 0 and .elapsedMs <= $maximum and .elapsedMs % 1000 == 0' "$temp_root/result.json" >/dev/null
[[ "$(grep -c '^+%s$' "$temp_root/date-calls")" -ge 3 ]]
[[ ! -e "$temp_root/forbidden-runtime" ]]
pass 'production date clock; no Node.js, npm or Perl invocation'
printf 'Bash remediation contracts passed: %s checks.\n' "$count"
