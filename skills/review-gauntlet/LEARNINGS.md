# Learnings ledger

The gauntlet's memory. One line per defect class that reached a pull request
despite the passes. The rule is simple: if a class repeats three times, the fix
is a rule or a probe, not more care.

## How to add an entry

After a review round, for each finding the external reviewer raised that the
gauntlet missed, append one line under the matching class:

```
- YYYY-MM-DD · PR #<n> · <the finding in one sentence> · pass <n> · <the rule,
  probe, or config change that prevents the repeat>
```

Then do the third-column work: add the check to the pass reference, add a probe
to `tools/gauntlet.sh`, or narrow the repository rule that let it through. An
entry with no action is a diary.

## Seeded from the 50-PR study (2026-11-21)

These are the classes already known, with the pass that owns each. They are the
baseline the gauntlet was built against, not a record of misses since.

### Documentation and prose (pass 5)

- The claim exceeds the code: "sends the email" for a handler that enqueues it.
- A runbook step runs before the step it depends on. Verification comes after
  execution.
- A default in prose differs from the config file's default.
- A filename, flag, env var, or profile in prose does not exist.
- The same wrong claim in three files, and only one was fixed.
- A quantifier ("only", "always", "never") that the code does not enforce.
- A prerequisite the reader must install is a footnote, not a step.

### Scripts and release tooling (pass 6)

- `set -e` does not fire for a failed command used as an `if` condition.
- A relative path resolves against a directory the script has already left.
- Cleanup deletes the install directory, the env file, or the logs a failed run
  needs.
- A failure path runs `down -v` and destroys the evidence.
- A log or event stream starts after the action it is meant to capture.
- Two references to one image compare unequal because one is normalised.
- A secret in a DSN is neither percent-encoded nor updated on rotation.

### CI and workflows (pass 6)

- A reusable workflow call passes no secrets; the login skips silently.
- A concurrency group lets a tag run and a dispatch run publish the same
  version.
- A path filter leaves a required check skipped, so the branch cannot merge.
- A cache is restored after the step that needed it.
- A release is published before its assets upload.

### Helm and values (pass 6)

- A closed schema rejects an override the chart used to accept.
- A numeric `--set` value fails a string-only schema.
- A schema block closes before every key the templates read is declared.
- A rendered manifest carries a duplicate key.
- A probe field exists on two of three probes.

### Frontend (pass 7)

- A response from a previous route or entity writes into the current one.
- An action-triggered refresh replaces a draft the user edited.
- A rejected save closes the form and loses the input.
- A disabled button is used as the only guard.
- Success feedback renders inside the branch the action removes.

### Correctness and authorization (passes 2 and 4)

- An idempotency replay returns the stored response before the visibility check.
- Authorization is enforced in the route but not in the service that writes.
- The source object is checked; the destination of a reassignment is not.
- Two reads that must agree run in separate snapshots.
- A lock is taken after the value it should protect was read.
- A fingerprint omits a field the operation applies.

### Rust and SQLx contract (pass 1)

- A runtime `sqlx::query` in a module the path instruction requires checked
  macros for.
- A checked macro added without the `.sqlx/` cache regenerated.
- A merged migration edited instead of a new one added.
- A new unique constraint without a `map_unique_constraint` arm.

### Paperwork (pass 11)

- The PR body has the template headings but leaves checklist items blank.
- The DCO trailer exists but does not match the author.
- A user-visible change had no release-note fragment.

## Entries

Append below. Newest last.
