---
name: marula-review-gauntlet
description: Marula Core's review gauntlet. Runs the portable review-gauntlet first, then the CodeRabbit oracle against the pull request's base. Use only in a MarulaHQ repository; anywhere else use review-gauntlet alone, because this overlay sends the diff to CodeRabbit.
license: MIT
compatibility: opencode
---

# Marula Core review gauntlet

This is the portable `review-gauntlet` plus the external reviewer that Marula
Core's pull requests go through. Load it only in a MarulaHQ repository. In any
other repository it would send that diff to a third-party service.

## Run

1. Load and follow `skill: review-gauntlet`. Its passes, fix discipline and stop
   rule are the review.
2. After the local passes, and again after a fix batch, run the oracle on the
   branch.

```bash
# during the loop: incremental, uncommitted scope
coderabbit review --agent --uncommitted --base <the branch the PR targets>

# before the push: PR-policy parity, gated on severity
coderabbit review --agent --committed --deep --gate major --base <the branch the PR targets>
```

- `--base` is the branch the pull request targets. Without it the CLI compares
  against `main`, which is the wrong diff for a release-branch PR.
- Exit `2` blocks on a finding at or above major. Exit `1` is an incomplete
  review, not a pass; check `outcome` and `unreviewedFileCount`.
- `reused: true` is not a fresh review. `review_skipped` with zero findings means
  no analysis ran.
- CLI reviews are not identical to pull-request reviews; they optimise for local
  feedback. A clean CLI is strong evidence, not proof.
- `--gate` requests a fresh full-diff review, so it costs more allowance than an
  incremental run.
- Fix what it finds, then re-run once. Do not loop it: the hourly allowance is
  shared with the pull-request review. Two local runs is the budget.

## Contract and report

The repository's `.coderabbit.yaml` path instructions are part of pass 1. Fill
the PR template checklist from the final commit, with evidence, as pass 11 says.
Add the oracle result to the report:

```
External reviewer: coderabbit <command> — <findings by severity, or "not installed">
```

If the CLI is not installed or not authenticated, record the exact command under
"Not verified" and say the oracle did not run. Do not substitute a guess.
