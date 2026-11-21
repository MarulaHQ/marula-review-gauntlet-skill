# review-gauntlet

An agent skill for closing the gap between local review and the external pull
request review. It runs the `pre-review` gate as pass 1, adds the correctness pass,
the logic pass, the security pass, the claims pass, the infrastructure pass and
the frontend pass, fixes what survives verification, and re-runs until a full
cycle finds nothing.

The measure of success is that CodeRabbit has nothing left to say when the pull
request opens.

## Why

Across the last 50 merged pull requests in `marula-core`, CodeRabbit posted 248
substantive findings and failed the description check on half the PRs. 232 of
those findings were "quick win", and 86 were prose. The cost was not hard code.
It was cheap, artifact-shaped defects being found by the external reviewer
instead of locally.

`RESEARCH.md` holds the full breakdown and the evaluation of the 19 skills that
were read before this one was written.

## Install

```bash
./deploy.sh
```

The script links this checkout into `~/.agents/skills/review-gauntlet` and into
every other agent skills directory it finds: `~/.claude`, `~/.codex`,
`~/.cursor`, `~/.gemini`, `~/.copilot`, `~/.config/opencode`. `--copy` copies
instead of linking. `--no-pre-review` skips the companion `pre-review` link.

A manual install is the same two lines:

```bash
mkdir -p ~/.agents/skills
ln -sfn "$PWD" ~/.agents/skills/review-gauntlet
```

## Use

Ask the agent to "run the review gauntlet", "review until clean", or "pre-push
review". The skill triggers on a diff, a branch, or a pull request body that
needs finishing.

Before a push, the external oracle is the CodeRabbit CLI:

```bash
coderabbit review --agent --uncommitted --base <target>          # during the loop
coderabbit review --agent --committed --deep --gate major --base <target>
```

`--base` is the branch the pull request targets. Without it the CLI compares
against `main`, which is the wrong diff for a PR to a release branch.

Exit `2` means a blocking finding remains. Exit `1` means the review was
incomplete, not clean.

## Layout

| Path | Purpose |
| --- | --- |
| `SKILL.md` | The loop: preflight, seven passes, fix, re-review, oracle, PR body, report |
| `references/logic-pitfalls.md` | Invariant ledger, return paths, bug-report test, failure injection, concurrency, config matrix |
| `references/docs-claims.md` | A runbook is a program; claim equals code |
| `references/infra-pitfalls.md` | Workflows, shell, Helm, images |
| `references/pr-contract.md` | The description check |
| `references/coderabbit-path-instructions.md` | Proposed path instructions for the classes `.coderabbit.yaml` does not cover |
| `tools/gauntlet.sh` | Mechanical preflight: dead links and paths, ghost env vars, lint, chart render, PR body |
| `LEARNINGS.md` | Ledger of misses and the pass that owed them |

## Dependencies

The skill loads these when the agent has them installed. It vendors none of
them, so there is one source of truth for each:

- `pre-review` for pass 1. Install the companion from
  `../marula-code-review-skill` or let `deploy.sh` link it.
- Cloudflare `security-audit` for pass 4, in guidance mode only.
- langgenius `frontend-code-review` for pass 7.
- `receiving-code-review` and `verification-before-completion` for the fix pass.
- The `trail` tools for call sites and file APIs, ahead of grep.

## License

MIT. See `LICENSE`.
