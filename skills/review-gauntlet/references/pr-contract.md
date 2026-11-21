# Pull request contract

The description check failed on 25 of the last 50 pull requests. It is the
cheapest finding in the repository to prevent, and it is entirely mechanical.

The check is not a formality. Each item is a claim about the diff, and the
reviewer reads a blank box as an unanswered question.

## The template

`.github/pull_request_template.md`:

```markdown
## What this changes

## Checklist

- [ ] Every commit is signed off per the DCO (`git commit -s`), and the
      `Signed-off-by` trailer matches the commit's author.
- [ ] Conventional commit subjects (`feat:`, `fix:`, `docs:` …) — release notes
      are generated from them.
- [ ] `CHANGELOG.md` updated under `[Unreleased]` if a user can see or do
      something different.
- [ ] No raw hex outside the `packages/ui` token files; `cargo clippy -D warnings`
      and `tsc --noEmit` pass.
- [ ] New user-data tables carry `org_id` and an RLS policy.
```

## What satisfies each item

### What this changes

One or two sentences. Link the issue if one exists. Say what a user can now do,
or what was broken and is not. Not the commit list, not the file list, not the
wave.

### DCO sign-off

Every commit, not the branch. The trailer identity must match the author
identity, not merely exist.

```bash
git log --format='%h %an <%ae>%n%(trailers:key=Signed-off-by,valueonly)' origin/main..HEAD
```

Mismatch, or a missing trailer, is a rewrite (`git rebase --signoff origin/main`),
not a checkbox.

### Conventional subjects

```bash
git log --format='%s' origin/main..HEAD
```

`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`, `ci:`, `perf:`,
`build:`. A squash merge takes the PR title, so the title must satisfy it too.

### Changelog

The repository writes `CHANGELOG.md` at release time. A pull request adds a
fragment:

```bash
node scripts/release-note.mjs add --bump <patch|minor|none> --section <…> --note "…"
```

- `minor` — a capability someone can use.
- `patch` — a fix to something that already works.
- `none` — product code with no user-visible change.

If the diff is tests, docs, `e2e/`, `scripts/`, `.github/`, or generated files,
the check exempts it by path. Say so, or add the fragment. Do not edit
`CHANGELOG.md` by hand.

### Tokens, clippy, tsc

```bash
cargo clippy -D warnings
pnpm -r exec tsc --noEmit
# raw hex outside packages/ui
git diff origin/main...HEAD | grep -nE '^\+.*#[0-9a-fA-F]{3,8}\b'
```

State the result you actually observed. A check you did not run is not "done" —
it is "not run", and the box stays open with that word in it.

### org_id and RLS

Search the migration diff for a new table:

```bash
git diff origin/main...HEAD -- crates/core-db/migrations | grep -nE 'CREATE TABLE'
```

If there is one, it needs `org_id` and a policy in the same file. If there is
not, write "not applicable — no new tables". That is a complete answer; a blank
is not.

## Writing a "not applicable"

The reviewer accepts a reason. It does not accept an empty box.

```
- [x] No raw hex outside `packages/ui` — the diff has no CSS or colour values.
- [x] New user-data tables — none; this adds a column to an existing table.
```

The difference between these and `- [ ]` is not pedantry: the first tells the
reviewer you looked, the second makes them look.

## The ordering trap

A description written before the last commit drifts. Fill the checklist **after**
the final commit, from the final diff, and re-check it after any rebase — a
rebase rewrites the trailers you just verified.

`tools/gauntlet.sh --pr-body` prints a draft with the evidence it can gather on
its own: trailer status per commit, non-conventional subjects, the changed-path
classes, whether a release-note fragment is present, and whether the migration
diff creates a table. It marks only what it measured. The rest stays unchecked
with a prompt for the sentence you need to write.
