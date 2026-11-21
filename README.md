# Review gauntlets

Two agent skills. The portable one runs every local review pass and calls no
external service. The Marula overlay adds the CodeRabbit oracle for Marula Core
pull requests.

| Skill | Use |
| --- | --- |
| `skills/review-gauntlet` | Any repository. Local only. |
| `skills/marula-review-gauntlet` | `MarulaHQ` repositories only. Runs the portable loop, then CodeRabbit. |

## Why

Across the last 50 merged pull requests in `marula-core`, the external reviewer
posted 248 substantive findings and failed the description check on half the
PRs. 232 of those findings were "quick win", and 86 were prose. The cost was
cheap, artifact-shaped defects being found by the external reviewer instead of
locally.

`skills/review-gauntlet/RESEARCH.md` holds the full breakdown and the evaluation
of the 19 skills that were read before this one was written.

## Install

```bash
git clone https://github.com/MarulaHQ/marula-review-gauntlet-skill
cd marula-review-gauntlet-skill
./deploy.sh
```

The script links both skills into `~/.agents/skills` and into every other agent
skills directory it finds: `~/.claude`, `~/.codex`, `~/.cursor`, `~/.gemini`,
`~/.copilot`, `~/.config/opencode`. `--copy` copies instead of linking.
`--no-pre-review` skips the companion `pre-review` link.

A manual install is the same two lines:

```bash
mkdir -p ~/.agents/skills
ln -sfn "$PWD/skills/review-gauntlet" ~/.agents/skills/review-gauntlet
ln -sfn "$PWD/skills/marula-review-gauntlet" ~/.agents/skills/marula-review-gauntlet
```

## Use

Ask the agent to "run the review gauntlet", "review until clean", or "pre-push
review". In a MarulaHQ repository, its `AGENTS.md` routes to the overlay, which
also runs the CodeRabbit oracle. Anywhere else, use the portable skill; do not
load the overlay, because it sends the diff to a third-party service.

## Layout

| Path | Purpose |
| --- | --- |
| `skills/review-gauntlet/SKILL.md` | The portable loop: preflight, seven passes, fix, re-review, report |
| `skills/review-gauntlet/references/logic-pitfalls.md` | Invariant ledger, return paths, bug-report test, failure injection, concurrency, config matrix |
| `skills/review-gauntlet/references/docs-claims.md` | A runbook is a program; claim equals code |
| `skills/review-gauntlet/references/infra-pitfalls.md` | Workflows, shell, Helm, images |
| `skills/review-gauntlet/references/pr-contract.md` | The description check |
| `skills/review-gauntlet/references/coderabbit-path-instructions.md` | Proposed path instructions for Marula's `.coderabbit.yaml` |
| `skills/review-gauntlet/tools/gauntlet.sh` | Mechanical preflight: dead links and paths, ghost env vars, lint, chart render, PR body |
| `skills/review-gauntlet/LEARNINGS.md` | Ledger of misses and the pass that owed them |
| `skills/marula-review-gauntlet/SKILL.md` | The CodeRabbit oracle and the Marula contract, run after the portable loop |

## Dependencies

The portable skill loads these when the agent has them installed. It vendors
none of them, so there is one source of truth for each:

- `pre-review` for pass 1. Install the companion from
  `../marula-code-review-skill` or let `deploy.sh` link it.
- Cloudflare `security-audit` for pass 4, in guidance mode only.
- langgenius `frontend-code-review` for pass 7.
- `receiving-code-review` and `verification-before-completion` for the fix pass.
- The `trail` tools for call sites and file APIs, ahead of grep.

The Marula overlay additionally needs the CodeRabbit CLI, authenticated, and is
only for a repository that already uses CodeRabbit.

## License

MIT. See `LICENSE`.
