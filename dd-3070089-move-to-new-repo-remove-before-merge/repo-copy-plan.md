# Extract Shepherd Task into `edburns/shepherd-task`

## Recommendation and intended result

Create an independent repository, not another fork, by filtering a disposable
copy of the seven source branches down to the Shepherd Task paths. Start its
`main` at the filtered active branch. Attach the filtered historical branches
using explicit **history-only merges** whose trees remain unchanged. Then add
the small amount of standalone-repository scaffolding in separate commits.

This meets both requirements:

1. The implementation on `main` comes from
   `origin/edburns/shepherd-task-v1.0.4-20260930`, not from a combination of old
   implementations.
2. All retained Shepherd Task history from the seven branches is reachable
   from `main`, including development not present in the active branch's
   ancestry. Awesome Copilot's unrelated file contents are not retained.

Do not use a snapshot copy, squash, cherry-pick-only migration,
`git subtree split` of just the plugin directory, or an unfiltered branch push.
Those approaches respectively lose history, miss the top-level skills or
divergent development, or carry the parent repository along.

**This document is a plan, not authorization to execute the migration.** Writing
it does not create a GitHub repository, rewrite history, install the plugin,
modify source branches, or push anything.

## Findings from the source checkout

Inspection date: October 19, 2026. The checkout was clean before this plan was
added. Its `HEAD` and the locally cached active remote-tracking ref both point
to `0134099e315ffe0e03d5665741e321b241693993`.

The following are the locally observed `origin` refs; they have not been
refreshed from GitHub during planning. At execution time, fetch the seven named
branches, record their actual tips, and explicitly approve any differences
from this table before proceeding.

| Source branch, beneath `origin/` | Observed tip | Ancestor of active tip? |
|---|---|---|
| `edburns/shepherd-task-v1.0.4-20260930` | `0134099e315ffe0e03d5665741e321b241693993` | Yes; active tip itself |
| `edburns/shepherd-task-v1.0.4-20260930-evidence-only-implemented` | `44e56d218ed4b8ccf42a7069a32e2d517aed78b3` | No |
| `edburns/dd-3068479-shepherd-task` | `13c8acb6d1922e60b0bede6e22478687f86e7e05` | No |
| `edburns/dd-3032934-shepherd-task` | `53b27628a1b432fa502e44094af2de628fbcabbc` | No |
| `edburns/dd-3032934-shepherd-task-01` | `15a633f68ad6a86a8fea7e31dde536a2f74da3a2` | No |
| `edburns/dd-3034809-test-03` | `1c2cc4f9331e79bcc33cd3a9f2cc586d623a5efa` | No |
| `edburns/dd-3032934-shepherd-task-20260721-2035Z` | `18a3b9bc7deddd139bdfa9ad66636c3c20c07a24` | No |

The checkout is not shallow. Filtering only the active branch would therefore
be an incomplete migration, not merely a different presentation of the same
history. Some commits are rebased or replayed variants; retain those variants
rather than trying to deduplicate them by subject or patch ID.

The active estate comprises 225 tracked plugin files and 15 tracked files in
six skill directories. Its authoritative lineup version is `1.0.4`.
`plugins/shepherd-task/README.md` is the normative documentation and
`plugins/shepherd-task/plugin.json` declares the estate.

The current inventory references outside the estate are:

- `.github/plugin/marketplace.json`
- `docs/README.plugins.md`
- `docs/README.skills.md`

No Shepherd-specific GitHub Actions workflow was found in the current
`.github` configuration. Historical branches also contain temporary campaign
documents, experiment evidence, and changes to shared Awesome Copilot tooling.
These require classification, not indiscriminate copying.

## Preservation contract

### What "entire git history" means here

Preserve every substantive retained-path change reachable from the seven
approved branch tips, including deleted files, old names, reverted changes,
branch-only development, authorship, timestamps, and commit messages.
Preserve meaningful branch/merge relationships subject to filtering's removal
of empty commits and degenerate merges.

This is **rewritten history**, not the original object graph:

- Commit IDs change when trees or ancestry change.
- Mixed commits retain their Shepherd changes but lose unrelated changes.
- Commits with no retained changes are pruned. Pure catalog-registration
  changes are deliberately outside the runtime/source preservation contract.
- Commit signatures cannot remain valid across rewriting; do not represent
  rewritten commits or newly created tags as originally signed.
- Existing textual references to source SHAs remain provenance references,
  not promises that those objects exist in the destination.
- GitHub issues, PRs, review discussions, Actions runs, releases, attachments,
  and repository settings are not Git history and are not automatically moved.

Keep the original repository intact as the historical reference. Preserve an
old-to-new commit map and branch-tip ledger so a reader can trace the rewrite.

### Preserve the layout first

Use this initial source layout in the destination:

```text
README.md                         # New landing page linking to normative docs
LICENSE                           # Existing MIT notice, copied unchanged
.gitattributes                    # New minimal line-ending rules
.gitignore                        # New Shepherd-specific exclusions
.github/workflows/                # New, narrowly scoped CI
docs/migration/                   # Sanitized provenance and rewrite records
plugins/shepherd-task/            # Retained at the same path
skills/shepherd-task-*/            # Six active skill directories
```

Do not flatten the plugin into the repository root during extraction.
The installers derive the source root from `scripts/../../..`; the version
commands require the tracked `plugins/shepherd-task` source path; contract
tests resolve top-level skill paths relative to that layout. Preserving these
paths avoids an unnecessary runtime migration.

Legacy skill directories remain visible in historical commits and archival
branches, not in the active `main` tree unless they are already present there.

## Phase 1: freeze inputs and establish the allowlist

Perform migration work outside this checkout and all existing worktrees.
Use a new, explicitly named work directory and keep private evidence outside
the repository that will be published.

The following Bash fragments describe execution after approval. Use
`$HOME/workareas/shepherd-task-migration-work-directory` as the migration work
directory. This path must not already exist; stop if it exists or any command
fails. No fragment is intended to be run independently of its preceding gates.

```bash
set -euo pipefail
SOURCE=/home/edburns/workareas/awesome-copilot-03
WORK="$HOME/workareas/shepherd-task-migration-work-directory"
test ! -e "$WORK"
mkdir -p "$WORK/evidence"

branches=(
  edburns/shepherd-task-v1.0.4-20260930
  edburns/shepherd-task-v1.0.4-20260930-evidence-only-implemented
  edburns/dd-3068479-shepherd-task
  edburns/dd-3032934-shepherd-task
  edburns/dd-3032934-shepherd-task-01
  edburns/dd-3034809-test-03
  edburns/dd-3032934-shepherd-task-20260721-2035Z
)
ACTIVE=${branches[0]}
```

1. Verify `origin` is `edburns/awesome-copilot`; never write to the source
   `origin` or `upstream`. Fetch only the named source branches, without tags,
   into a new bare snapshot repository. This refreshes the inputs without
   changing the source worktree or its remote-tracking refs.
2. Compare fetched tips with the table above. Stop for approval if any differ.
3. Record source repository identity, branch names, full SHAs, Git and
   `git-filter-repo` versions, and execution time in the private evidence
   directory. Make a private source bundle before filtering.

```bash
git init --bare "$WORK/source-snapshot.git"
refspecs=()
for branch in "${branches[@]}"; do
  refspecs+=("refs/heads/$branch:refs/heads/source/$branch")
done
git -C "$WORK/source-snapshot.git" fetch --no-tags \
  git@github.com:edburns/awesome-copilot.git "${refspecs[@]}"
git -C "$WORK/source-snapshot.git" symbolic-ref HEAD \
  "refs/heads/source/$ACTIVE"
git -C "$WORK/source-snapshot.git" for-each-ref \
  --format='%(refname) %(objectname)' refs/heads/source/ \
  > "$WORK/evidence/source-refs.txt"
git -C "$WORK/source-snapshot.git" bundle create \
  "$WORK/evidence/source-before-filter.bundle" --branches
git -C "$WORK/source-snapshot.git" bundle verify \
  "$WORK/evidence/source-before-filter.bundle"
```

The bundle and snapshot contain the original repository's reachable history.
They are **private rollback inputs**, not destination contents; never upload
them to the new repository or its releases.

### Historical path allowlist

Create `$WORK/evidence/retained-paths.txt` with these literal directory entries,
one per line:

```text
plugins/shepherd-task/
skills/shepherd-task-10-create-ignorance-reduction-plan/
skills/shepherd-task-20-create-issues-from-plan/
skills/shepherd-task-30-from-assignment-to-ready/
skills/shepherd-task-40-from-ready-to-merged-to-base/
skills/shepherd-task-50-create-post-mortem/
skills/shepherd-task-approve-workflows-and-wait-for-completion/
skills/shepherd-task-create-ignorance-reduction-plan/
skills/shepherd-task-create-issues-from-plan/
skills/shepherd-task-create-post-mortem/
skills/shepherd-task-from-assignment-to-ready/
skills/shepherd-task-from-ready-to-merged-to-base/
```

The five unnumbered legacy directories were found in the inspected history.
Keep their original paths: do not rename them into the numbered directories
inside the rewrite. Their actual transitions should remain understandable.

Before finalizing the allowlist, audit all seven histories:

- Enumerate added/deleted paths and rename/copy records, not just current
  tracked files. Inspect the earliest Shepherd additions and relevant
  predecessor commits for source paths whose names do not contain
  `shepherd`.
- Inspect changes outside the allowlist in Shepherd-related commits. Classify
  each as a true component dependency, generated inventory, shared catalog
  tooling, temporary campaign evidence, or unrelated work.
- Pay particular attention to the historical
  `dd-3031763-improve-agentic-velocity-remove-before-merge/` directory:
  it contains plans, prompts, lessons, and experiment records. Exclude raw
  campaign artifacts by default; retain a particular authored specification
  only if review establishes that it is part of the system rather than a
  development run. Record each decision.
- Add any confirmed historical component path explicitly to the allowlist.
  If a mixed file needs partial extraction, design and review that
  content-level transformation separately; including the whole file would
  import unrelated content.

**Gate:** approve the path/classification ledger before filtering. A filename
search alone is not proof that every predecessor path was found.

### Exclusions and catalog history

Do not retain the full root README, generated resource indexes, marketplace,
website, other resources/plugins, parent package manifests/lockfile, shared
`eng/` machinery, editor configuration, contributor databases, or parent
repository policies and automation.

In particular, do not filter whole `docs/README.*.md` or marketplace files:
their historical snapshots contain the unrelated catalog. Record the source
commits that registered Shepherd in the catalog in the migration ledger
instead. Recreate only the standalone metadata actually needed.

If preservation of catalog-registration edits themselves becomes a
requirement, stop and extend the plan with a reviewed Shepherd-entry-only
history transformation. Do not claim those excluded edits were preserved.

## Phase 2: rewrite only the disposable copy

Use a fresh mirror of the frozen snapshot, not this working repository.
Do not use `--refs` for a partial rewrite, `--force` to bypass fresh-clone
safety, or `refs/replace` to reconnect original history.

```bash
git clone --mirror --no-local \
  "$WORK/source-snapshot.git" "$WORK/filtered.git"
git -C "$WORK/filtered.git" filter-repo \
  --paths-from-file "$WORK/evidence/retained-paths.txt" \
  --prune-empty always \
  --prune-degenerate auto \
  --preserve-commit-hashes \
  --replace-refs delete-no-add
cp "$WORK/filtered.git/filter-repo/commit-map" \
  "$WORK/evidence/commit-map.txt"
```

`--preserve-commit-hashes` preserves textual hash references in commit
messages; it does **not** preserve the IDs of rewritten commits. Preserve
source commit messages rather than editing them to look destination-native.
`--prune-empty always` removes commits with no retained file changes,
including pre-existing empty checkpoints; meaningful merge commits may remain.

Record the rewritten tip for every input branch. A source tip that changed
only excluded paths may map to a retained ancestor, so use the actual
rewritten branch ref as the archival tip and reconcile it with the commit
map. Stop if a branch unexpectedly disappears or has no retained history.

Review retained blobs and messages before any publication, across **all**
rewritten branches, not just `main`. The normative README warns that Markdown
session shares are not JSON-redacted. Treat examples and old fixtures as
review inputs too. Do not upload source bundles or raw logs for scanning.
If sensitive material is found, resolve it in a new reviewed filtering pass
and regenerate all maps and verification evidence.

## Phase 3: make all retained history reachable from `main`

Clone only the rewritten repository into the destination working directory.
This prevents original objects, reflogs, and backup refs from entering the
published repository.

```bash
git clone --no-local "$WORK/filtered.git" "$WORK/shepherd-task"
cd "$WORK/shepherd-task"
git switch --create main "origin/source/$ACTIVE"
git tag -a migration/active-source \
  -m "Filtered active source; see migration provenance"
baseline_tree=$(git rev-parse 'HEAD^{tree}')
```

Create an `archive/<original-branch-name>` local branch for each of the six
historical rewritten refs. For each one, if it is not already an ancestor of
`main`, make a history-only merge:

```bash
for branch in "${branches[@]:1}"; do
  archive="archive/$branch"
  git branch "$archive" "origin/source/$branch"
  if ! git merge-base --is-ancestor "$archive" main; then
    git merge --no-ff --allow-unrelated-histories -s ours "$archive" \
      -m "Preserve extracted history from $branch without changing active files" \
      -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
Copilot-Session: <migration-execution-session-id>"
  fi
  test "$(git rev-parse 'HEAD^{tree}')" = "$baseline_tree"
  git merge-base --is-ancestor "$archive" main
done
```

Replace the trailer placeholder with the actual execution session ID.
Use `-s ours`, **not** `-X ours`: this is deliberately an ancestry integration,
not a conflict-resolution preference. Filtering may leave unrelated roots,
which is why the merge allows unrelated histories.

This preserves historical alternatives as ancestors without resurrecting
their obsolete files or behavior. Commit messages and the migration document
must say so explicitly; these merges are not evidence that those alternative
implementations were tested or adopted.

At this point, `main` must have exactly the active extracted tree.
Only after this gate may standalone adaptation commits change it.

## Phase 4: standalone adaptation, separate from extraction

Keep the raw extraction and the new repository's maintenance changes
distinguishable in history.

| Surface | Standalone treatment |
|---|---|
| Root `README.md` | Add a concise introduction, installation commands, and a link to `plugins/shepherd-task/README.md`; do not fork the normative manual into a second maintained copy. |
| `LICENSE` | Copy the pinned source MIT license unchanged, including the existing GitHub copyright notice; record its source SHA. Do not replace its notice with a new author-only notice. |
| `plugin.json.repository` | Change the current `github/awesome-copilot` URL to `edburns/shepherd-task`. Preserve the plugin name, schema URL, version contract, and six-skill lineup. |
| `com.github.awesome-copilot` manifest extension | Retain initially as an existing composition contract: installers, version tools, readers, and tests consume it. Its name does not require importing the parent catalog. Rename only in a separate coordinated change if needed. |
| Workshop and executable examples | Update active clone/checkout instructions, local directory names, and source-repository examples. Preserve historical evidence links where intentional and label them as historical. |
| `.gitattributes` / `.gitignore` | Add minimal standalone rules: LF for scripts/Markdown and exclusions for generated installs, campaign logs, local worktrees, and credentials. Do not copy all parent policies. |
| Contributor and agent instructions | Write short Shepherd-specific guidance and test commands; do not inherit unrelated Awesome Copilot contribution rules. |
| CI | Add focused native Bash and PowerShell contract jobs. Avoid the catalog's website/build, contributor tooling, and Node.js test infrastructure. |
| Migration provenance | Add a sanitized source-ref ledger, retained/excluded path decisions, tool versions, old/new commit map, baseline tree IDs, verification results, and an explanation of history-only merges. No source bundle or raw campaign logs. |

The existing local installer is the initial supported installation mechanism.
Retaining its layout does not require carrying `.github/plugin/marketplace.json`
or the parent `npm run build`.

Do not advertise direct marketplace/plugin installation unless a standalone
distribution has been built and verified: the current source manifest uses
Awesome Copilot composition metadata, and the local installer materializes
the top-level skills. A source tree is not automatically an equivalent served
plugin package.

Keep the extracted baseline at version `1.0.4`. Decide and document whether
the adaptation warrants a patch release; if so, use the existing version
command to advance the entire estate together rather than hand-editing
individual version stamps.

## Phase 5: verification gates

### Content and history

Before adaptation, verify all seven rewritten branch snapshots against the
corresponding original branch snapshots restricted to the allowlist. Compare
path, file mode, and blob ID records from `git ls-tree -r`; use reviewed
path-prefix matching rather than relying on shell expansion of deleted paths.
The projection should match exactly because extraction does not rename or
edit retained files.

Also verify:

1. The `migration/active-source` tree is the exact active-source projection.
   The tree after all history-only merges is identical to that baseline.
2. Every historical rewritten tip is an ancestor of `main`; check with
   `git merge-base --is-ancestor`. Keeping branches alone is insufficient for
   the requested `main` history.
3. For each original commit that substantively changes retained content,
   reconcile its commit-map entry with the rewritten graph. Investigate
   zero mappings and pruned merges individually; account for redundant
   merges without requiring an artificial empty replacement commit.
4. Inspect the union of paths in every reachable rewritten tree. Before
   adaptation, every path must be under the approved historical allowlist.
   After adaptation, permit only the explicitly added standalone files.
5. Run `git fsck --full`. Inspect refs for original backups, replace refs,
   unexpected tags, and parent-repository branches. Check for gitlinks or
   LFS pointers; resolve any dependency without importing an unrelated repo.
6. Reconcile important historical SHAs named in docs against the commit map.
   Leave external campaign fixture repository SHAs unchanged.
7. Record commit/file/object counts and packed size. Size is a useful
   diagnostic, not proof of a clean extraction.

A path filter removes unrelated file payloads, not every textual mention of
Awesome Copilot. Source URLs, retained commit messages, copyright attribution,
and the compatibility namespace are expected and must not be erased merely
to make a text search empty.

### Runtime and native platform contracts

Run the existing offline contracts in the extracted checkout and again after
any adaptation that affects them. Use isolated temporary `COPILOT_HOME` and
home/profile locations; never replace the user's real installed lineup.

Start with:

```bash
bash plugins/shepherd-task/test/version-command-contract.sh
bash plugins/shepherd-task/test/version-lineup-contract.sh
bash plugins/shepherd-task/test/macos-bash-compatibility-contract.sh
bash plugins/shepherd-task/test/post-merge-gate-contract.sh
bash plugins/shepherd-task/test/redact-secrets-contract.sh
```

```powershell
pwsh -NoLogo -NoProfile -File plugins/shepherd-task/test/version-command-contract.ps1
pwsh -NoLogo -NoProfile -File plugins/shepherd-task/test/version-lineup-contract.ps1
pwsh -NoLogo -NoProfile -File plugins/shepherd-task/test/post-merge-gate-contract.ps1
pwsh -NoLogo -NoProfile -File plugins/shepherd-task/test/redact-secrets-contract.ps1
```

These are the first gates, not the complete suite. Enumerate all top-level
contracts and the offline fixture contracts documented under `test/`, review
their prerequisites, and run the relevant full offline set in both native
implementations. Include monitor/session artifacts, lesson defaults, OTel
summaries, stage 15/20/40 contracts, encoding/PSNCPPS, and fixture consistency.
Do not run every test-directory script indiscriminately: preparation and
campaign drivers can create repositories, issues, commits, and paid sessions.

Verify installation, uninstall, upgrade/downgrade safeguards, rollback,
version mutation in a disposable source copy, installed-only validation, and
that `install-manifest.json.sourceCommit` reports the **new checkout's HEAD**.
Exercise Bash on Linux/macOS and PowerShell on its supported environments.
Do not introduce Node.js as the test runner or mock runtime.

Keep Java-dependent Cargo Tracker runs separate from offline contracts.
An explicitly approved live smoke campaign must target a disposable
repository with Actions and Copilot configured, never either source or
destination repository merely because it is available. Record any live or
platform validation not run; do not silently count it as passed.

**Publication gate:** snapshot parity, history reachability, content review,
standalone adaptation review, and the agreed offline platform checks pass.
Record each exact command and result in the migration evidence.

## Phase 6: create and publish the independent repository

Choose visibility explicitly. Recommended sequence: create private, publish
and verify, then make public only after content/provenance review. Do not
initialize a README, license, or `.gitignore` through GitHub, because the
filtered history is the initial history.

Use `gh` for repository creation and settings:

```bash
gh repo create edburns/shepherd-task --private \
  --description "Skills and native scripts for shepherding GitHub engineering campaigns"
```

If the name already exists, stop and inspect it; do not overwrite it.
From the new standalone checkout only:

```bash
git remote remove origin
git remote add origin git@github.com:edburns/shepherd-task.git
git remote -v
git push --dry-run origin refs/heads/main:refs/heads/main
git push origin refs/heads/main:refs/heads/main
gh repo edit edburns/shepherd-task --default-branch main --enable-issues
```

Push each approved `refs/heads/archive/<original-branch-name>` and the
`migration/active-source` tag with explicit refspecs after reviewing the ref
ledger. Do not use `git push --mirror`, `--all`, or `--tags`.
Do not recreate parent-repository release tags unless individually selected
and reconciled with the rewritten commits.

Create a fresh validation clone from GitHub. Repeat tree, ancestry, ref,
installation, and agreed offline checks there. Verify through `gh` that the
repository is not a fork, its default branch is `main`, and CI succeeds on the
exact published SHA. Configure branch protection/rulesets only after the
standalone check names exist. Copilot settings, collaborators, and Actions
permissions require separate configuration.

After acceptance, update relevant discovery links in the old fork with a
pointer to the new repository if desired. That is a separate source change,
not deletion or rewriting of the old project. Do not transfer/delete the
Awesome Copilot fork or seek to merge this extraction upstream.

## Rollback, acceptance, and scope boundary

Until publication, failures require only correcting or recreating a
specifically identified disposable migration copy. Keep the frozen source
snapshot and private bundle until acceptance. Do not reset, rebase, clean, or
force-push the source checkout or any of its branches.

If verification fails after the initial private publication, stop rollout.
Prefer rebuilding in another local disposable directory and reviewing the
corrected result before any explicitly approved destination history rewrite.
After public adoption, avoid another rewrite; ordinary fixes are preferable.

The migration is accepted when:

- `edburns/shepherd-task` is an independent repository with default `main`.
- Its recorded baseline exactly matches the approved active source's
  Shepherd estate, and subsequent differences are reviewed adaptation commits.
- Every retained historical branch tip is reachable from `main`.
- Published reachable history contains only approved component paths and
  standalone scaffolding, not the unrelated Awesome Copilot catalog.
- Rewrite provenance and the old/new mapping are durable and sanitized.
- The native installation/version contracts and agreed platform checks pass.
- The original fork, branches, issues, and historical references remain intact.

Do not publish this temporary campaign directory wholesale. Carry forward a
reviewed, sanitized migration report into the new `docs/migration/` directory
instead.

## Technical references

Consult the installed tool help and the primary documentation when executing:

- Git Filter Repo manual:
  `https://github.com/newren/git-filter-repo/blob/main/Documentation/git-filter-repo.txt`
  (path filtering does not follow renames automatically; commit maps, pruning,
  fresh-clone safeguards, and message-hash preservation).
- Git merge manual: `https://git-scm.com/docs/git-merge`
  (`ours` strategy versus the `ours` strategy option).
- Source-specific normative documentation:
  `plugins/shepherd-task/README.md`, especially Installation, Version contract,
  Logs/telemetry/redaction, and File map.
