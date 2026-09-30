# Figure 04 — Stage 40: Ready boundary to merged

Stage 40 performs current-head Copilot review, resolves findings locally,
publishes campaign lessons when enabled, revalidates the publication commit,
merges into the campaign base branch, and satisfies deferred post-merge gates
before closing the task.

```mermaid
flowchart TD
    R0[Resolve unique remote matching campaign repository] --> A[Find linked open PR]
    A --> B[Mark PR Ready for review]
    B --> C[Capture target HEAD and previous Copilot review ID]
    C --> D[Request reviewer Copilot, up to 3 attempts]
    D --> E{Request positively acknowledged?}
    E -->|No| FAIL1[Stop in resumable state]
    E -->|Yes| F[Wait up to configured timeout for new review on target HEAD]
    F --> G{Review completed?}
    G -->|No| FAIL2[Stop in resumable state]
    G -->|Yes| H{Review refused because PR exceeds file limit?}
    H -->|Yes| FAIL3[Stop; split or reduce PR manually]
    H -->|No| I[Count unresolved top-level comments for this review ID]
    I --> J{Findings exist?}
    J -->|Yes| K[Create sibling worktree from PR branch]
    K --> L[Evaluate each finding and implement meritorious fixes locally]
    L --> M[Run applicable tests and commit each fix]
    M --> N[Push all fixes to matching repository remote]
    N --> O[Reply with evidence and resolve each thread]
    O --> P[Wait for CI and fix real failures]
    P --> Q[Approve action_required workflows and wait]
    Q --> R{8 review iterations exhausted?}
    R -->|Yes| FAIL4[Stop for manual intervention]
    R -->|No| C
    J -->|No| S{Lesson mode}
    S -->|off| V[Final workflow approval and checks]
    S -->|campaign| T{Validated section already present and candidate absent?}
    T -->|No| U[Curate candidate plus implementation, tests, CI, fixes, and review evidence]
    U --> U2[Replace candidate with validated section or explicit no-reusable-lessons result]
    U2 --> U3[Commit only campaign-lessons.md and push]
    U3 --> P
    T -->|Yes| V
    V --> W[Require current-head CI, acknowledged review, zero unresolved findings, and valid lesson state]
    W --> X[Clean up sibling worktree]
    X --> Y[Require base branch is campaign base and never main]
    Y --> Z{Merge conflicts?}
    Z -->|Yes| ZA[Rebase locally onto campaign base and force-with-lease]
    ZA --> V
    Z -->|No| ZB[Merge commit with branch deletion]
    ZB --> ZC[Capture immutable primary merge SHA]
    ZC --> ZD{Deferred post-merge gates?}
    ZD -->|No| ZH[Close task issue]
    ZD -->|Yes| ZE[Wait for relevant base push workflow on exact primary merge SHA]
    ZE --> ZF{Merged evidence update required?}
    ZF -->|Yes| ZG[Create, review, validate, and merge evidence-only follow-up PR]
    ZF -->|No| ZI[Re-evaluate every deferred row]
    ZG --> ZI
    ZI -->|Any row not PASS| FAIL5[Reopen issue and stop]
    ZI -->|All PASS| ZH
    ZH --> DONE[Report merged with all post-merge gates passed]
```

The lesson publication commit changes the PR head, so pre-publication CI and
review evidence is discarded. The publication head must complete the same
workflow and review loop before merge. Post-merge evidence is bound to the
primary merge SHA; a later evidence-only commit must not replace that anchor.
