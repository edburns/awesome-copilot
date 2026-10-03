# Cargo Tracker Change Arrival Deadline fixture - Devoxx 2026 control

This fixture is a self-contained end-to-end invocation of `shepherd-task` with
lesson propagation disabled. It applies the five-task Change Arrival Deadline
plan to a prepared Cargo Tracker baseline and verifies the completed campaign.

There is one campaign, one stage-25 run, and no paired comparison or recovery
phase.

## Provenance and experiment boundary

This directory is copied from
`plugins/shepherd-task/test/cargotracker-add-change-arrival-deadline-feature/`
at tag `shepherd-task-v1.0.4`, not from the tricked-out Devoxx fixture.
The five-task specification, acceptance requirements, and minimal
`Shepherd task Cargo Tracker` package workflow come from that tagged fixture.
The adaptations are the fixed source branch/SHA, fixture identity, application
paths/commands under `demo/`, and factual baseline configuration corrections.
The pinned POM uses `maven.compiler.release=17`, not the tagged plan's Java 7
source/target level; the plan preserves that setting rather than downgrading it.
PowerShell offline mocks use PowerShell rather
than the tag's JavaScript mocks; they add no Node.js dependency.
Offline session-outcome transcripts include the `### Copilot` response headers
required by the current harness parser; this changes no application gates.

The tagged plan's completed-phase observations are historical context, not
newly verified evidence for this baseline. Section 3.9 corrects its old
`skipTests=true`/remote-Payara-only assumption: the pinned POM configures an Open
Liberty managed Arquillian adapter without that skip flag. Execute the tagged
commands and report actual results; do not disable configured tests, import the
experiment arm's test/CI improvements, or impose fixed test-count gates.

## Fixed baseline

- Source branch: `edburns/dd-3016202-cargotracker-devoxx-be-2026-control`
- Baseline SHA: `634f3ca4787c84fd652cdf5c883c37f1098e0c61`
- Campaign branch: `experiment/shepherd-control`
- Shared baseline branch created by the fixture: `experiment/shepherd-shared-baseline`
- Maven application directory: `demo/`
- Lesson propagation: `off`
- Implementation tasks: 5, executed serially
- Substantive check: `Shepherd task Cargo Tracker`

The resolved five-task plan is stored as `cargotracker-plan.md.gz.b64`. The
Bash initializer verifies its SHA-256 digest before decoding it, preserving the
exact fixture content across installed and checked-out locations.

## What it exercises

1. Verifies and publishes the prepared Cargo Tracker baseline.
2. Creates one detached control worktree at the exact baseline SHA.
3. Initializes stage 00 without specifying a lesson mode.
4. Verifies that stage 00 persisted `lessonPropagation=off`.
5. Runs stage 15 and stage 20 to create the five ordered implementation issues.
6. Runs stage 25 once for all five issues.
7. Verifies closed issues, merged PRs, serial ordering, substantive Maven CI,
   issue-body contracts, and the unchanged campaign-lessons placeholder.
8. Preserves the checkout, worktree, campaign artifacts, run logs,
   post-mortem, and a machine-readable summary.

## Requirements

- Bash 3.2+ on GNU/Linux or macOS, Git Bash, or PowerShell 7
- Bash driver: `bash`, `git`, `gh`, `copilot`, `jq`, `find`, `base64`,
  `gzip`, and either `sha256sum` or `shasum` on `PATH`
- PowerShell driver: `git`, `gh`, `copilot`, `pwsh`, and `jq` on `PATH`
- Authenticated GitHub CLI
- A disposable Cargo Tracker fork containing the fixed source branch and
  baseline commit
- Actions, Copilot Coding Agent, and Copilot code review enabled
- The shepherd-task plugin and skills installed from this checkout

The target and control-worktree paths must not already exist. The remote
baseline and control branch names must also be unused.

Use a fresh disposable fork of
`azure-javaee/dd-3016202-cargotracker-devoxx-be-2026` containing the source branch
and pinned commit. Do not copy only the default branch. The source branch is
read-only input; the fixture creates its separate baseline and campaign branches.
Keep the same installed harness revision as the experiment run when comparing
results. This fixture does not require the evidence-only remediation branch.

Install the current plugin before running either driver:

```bash
plugins/shepherd-task/scripts/install-task-shepherd.sh
```

Both drivers resolve the installed fixture and stage scripts from
`${COPILOT_HOME:-$HOME/.copilot}/plugins/shepherd-task`; they do not require
the source checkout as their working directory.

## Offline contracts

From the repository root:

```powershell
$Fixture = '.\plugins\shepherd-task\test\cargotracker-add-change-arrival-deadline-feature-devoxx-2026-edition-control'

& "$Fixture\03-resolve-repository-remote.ps1"
& "$Fixture\05-stage20-artifact-contract.ps1"
& "$Fixture\06-stage40-review-contract.ps1"
& "$Fixture\07-driver-encoding-contract.ps1"
& "$Fixture\08-psncpps-contract.ps1"
& "$Fixture\09-skill-powershell-contract.ps1"
& "$Fixture\10-cargotracker-fixture-contract.ps1"
& "$Fixture\11-stage15-plan-discovery-contract.ps1"
& "$Fixture\12-session-outcome-contract.ps1"
```

The native Bash contracts can be run from any working directory:

```bash
fixture="plugins/shepherd-task/test/cargotracker-add-change-arrival-deadline-feature-devoxx-2026-edition-control"
for contract in \
  03-resolve-repository-remote.sh \
  05-stage20-artifact-contract.sh \
  06-stage40-review-contract.sh \
  07-driver-encoding-contract.sh \
  08-psncpps-contract.sh \
  09-skill-powershell-contract.sh \
  10-cargotracker-fixture-contract.sh \
  11-stage15-plan-discovery-contract.sh \
  12-session-outcome-contract.sh; do
  "$fixture/$contract"
done
```

These contracts are offline and non-paid. They use local mock GitHub responses
where API behavior must be exercised. They do not create issues, invoke
Copilot, push branches, or run the end-to-end campaign.

## Run the end-to-end control campaign

Install the current source first:

```powershell
.\plugins\shepherd-task\scripts\install-task-shepherd.ps1
```

Then run:

```powershell
.\plugins\shepherd-task\test\cargotracker-add-change-arrival-deadline-feature-devoxx-2026-edition-control\run-campaign.ps1 `
  -RepositoryUrl 'https://github.com/OWNER/DISPOSABLE-CARGOTRACKER-FORK' `
  -WorkareasDir 'C:\workareas'
```

Or run the native Bash driver:

```bash
"${COPILOT_HOME:-$HOME/.copilot}/plugins/shepherd-task/test/cargotracker-add-change-arrival-deadline-feature-devoxx-2026-edition-control/run-campaign.sh" \
  --repository-url 'https://github.com/OWNER/DISPOSABLE-CARGOTRACKER-FORK' \
  --workareas-dir "$HOME/workareas"
```

To validate the installed Bash layout and all offline integration contracts
without cloning, creating issues, or invoking paid Copilot operations:

```bash
"${COPILOT_HOME:-$HOME/.copilot}/plugins/shepherd-task/test/cargotracker-add-change-arrival-deadline-feature-devoxx-2026-edition-control/run-campaign.sh" \
  --repository-url 'https://github.com/OWNER/REPOSITORY' \
  --workareas-dir "$HOME/workareas" \
  --validate-installed-only
```

Use `--show-domain-fixture-output`, `--show-shepherd-task-script-output`,
`--show-contract-output`, or `--show-native-tool-output` for individual output
channels, or `--show-all-output` for all of them.

Use `-ValidateInstalledOnly` for the equivalent non-mutating installed-layout
validation in PowerShell.

The control driver intentionally omits `-LessonPropagation` when invoking
stage 00. The resulting manifest must explicitly contain
`"lessonPropagation": "off"`.

The run is successful only when all five issues are closed, all linked pull
requests are merged serially, the repository-owned Maven/Open Liberty check
succeeds, stage 25 records a successful `off` run, and
`campaign-lessons.md` retains its initial placeholder. No cleanup is performed.
