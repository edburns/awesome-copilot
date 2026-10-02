# Cargo Tracker Change Arrival Deadline fixture — Devoxx 2026 edition

This fixture is a self-contained end-to-end invocation of `shepherd-task` with
lesson propagation disabled. It applies the five-task Change Arrival Deadline
plan to the tricked-out Devoxx 2026 Cargo Tracker baseline, whose Maven
application is under `demo/`, and verifies the completed campaign.

There is one campaign, one stage-25 run, and no paired comparison or recovery
phase.

## Fixed baseline

- Source branch: `edburns/dd-3016202-cargotracker-devoxx-be-2026-experiment`
- Baseline SHA: `5c7f3ca91a2c5bd93ec6aa5d52c63a5ffbd951c7`
- Shared baseline branch created by the fixture:
  `experiment/shepherd-shared-baseline`
- Campaign branch: `edburns/dd-3016202-cargotracker-devoxx-be-2026-add-feature-control`
- Maven application directory: `demo/`
- Lesson propagation: `off`
- Implementation tasks: 5, executed serially
- Substantive check: `Shepherd task Cargo Tracker`

The historical non-tricked-out branch
`edburns/dd-3016202-cargotracker-devoxx-be-2026-control` is not used, modified,
or deleted by this fixture.

The resolved five-task plan is stored as `cargotracker-plan.md.gz.b64`. The
Bash initializer verifies its SHA-256 digest before decoding it, preserving the
exact fixture content across installed and checked-out locations.

The baseline removes the historical CI-construction campaign directory and its
evidence-matrix maintenance requirement. Feature tasks retain the existing CI,
tests, acceptance checks, and shepherd run telemetry without maintaining that
historical matrix. The PowerShell initializer embeds the same resolved plan;
offline contracts verify that both representations remain identical.

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
- PowerShell driver: `git`, `gh`, `copilot`, and `pwsh` on `PATH`
- Authenticated GitHub CLI
- A disposable Cargo Tracker fork containing the fixed source branch and
  baseline commit
- Actions, Copilot Coding Agent, and Copilot code review enabled
- The shepherd-task plugin and skills installed from this checkout

The target and control-worktree paths must not already exist. The remote
`experiment/shepherd-shared-baseline` and
`edburns/dd-3016202-cargotracker-devoxx-be-2026-add-feature-control` branch
names must also be unused.

## Prepare a disposable repository

1. Fork `azure-javaee/dd-3016202-cargotracker-devoxx-be-2026`, using a unique name
   such as `YYYYMMDD-HHMM-cargotracker-add-feature`. Do not select
   **Copy the master branch only**.
2. Enable Actions and Issues.
3. Set the default branch to
   `edburns/dd-3016202-cargotracker-devoxx-be-2026-experiment`.
4. Set Copilot code review effort to **Balanced**.
5. Leave the fork network so another disposable repository can be created for
   a later run.
6. Confirm the repository still contains the source branch and exact baseline
   SHA above, and that neither fixture-created branch already exists.

The driver does not accept arbitrary content from the repository's default
branch as its baseline. It fetches the fixed source branch, verifies that the
exact baseline SHA is its ancestor, validates the expected `demo/` tree and
feature absence at that SHA, and creates both fixture branches from that
commit.

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
$Fixture = '.\plugins\shepherd-task\test\cargotracker-add-change-arrival-deadline-feature-devoxx-2026-edition'

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
fixture="plugins/shepherd-task/test/cargotracker-add-change-arrival-deadline-feature-devoxx-2026-edition"
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
.\plugins\shepherd-task\test\cargotracker-add-change-arrival-deadline-feature-devoxx-2026-edition\run-campaign.ps1 `
  -RepositoryUrl 'https://github.com/OWNER/DISPOSABLE-CARGOTRACKER-FORK' `
  -WorkareasDir 'C:\workareas'
```

Or run the native Bash driver:

```bash
"${COPILOT_HOME:-$HOME/.copilot}/plugins/shepherd-task/test/cargotracker-add-change-arrival-deadline-feature-devoxx-2026-edition/run-campaign.sh" \
  --repository-url 'https://github.com/OWNER/DISPOSABLE-CARGOTRACKER-FORK' \
  --workareas-dir "$HOME/workareas"
```

To validate the installed Bash layout and all offline integration contracts
without cloning, creating issues, or invoking paid Copilot operations:

```bash
"${COPILOT_HOME:-$HOME/.copilot}/plugins/shepherd-task/test/cargotracker-add-change-arrival-deadline-feature-devoxx-2026-edition/run-campaign.sh" \
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
