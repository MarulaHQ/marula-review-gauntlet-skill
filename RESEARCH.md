# Research: why the review loop keeps costing a round

Evidence base for `review-gauntlet`. Collected 2026-11-21 from the public
repository `MarulaHQ/marula-core`.

## Method

- The last 50 merged pull requests (`#66`–`#147`).
- Every inline review comment authored by `coderabbitai` on those PRs: 295
  records, of which 248 are substantive findings (47 are agent analysis-chain
  transcripts, excluded).
- Every review body on those PRs: 146, including the summary sections where the
  pre-merge checks and nitpicks live.
- Classification by changed path for the artifact, and by the reviewer's own
  severity and domain labels where present.

Reproduce with `gh api repos/<owner>/<repo>/pulls/<n>/comments` and
`.../reviews`.

## What the external reviewer actually finds

### By artifact

| Class | Findings | Share | Which pass now owns it |
| --- | ---: | ---: | --- |
| Documentation and prose | 86 | 35% | 5 claims |
| Scripts and release tooling | 35 | 14% | 6 infrastructure |
| Frontend (`.tsx`, `.ts`, e2e) | 34 | 14% | 7 frontend, 2 correctness |
| CI and workflows | 30 | 12% | 6 infrastructure |
| Rust: the SQLx contract | 16 | 6% | 1 contract |
| Helm and values schema | 15 | 6% | 6 infrastructure |
| Rust: authorization and other | 20 | 8% | 2 correctness, 4 security |
| Config | 1 | <1% | 1 contract |

The Rust core, where the design work happened, is the smallest source. The
defects are concentrated in the surfaces that get the least review attention:
prose, scripts, CI, and charts.

### By severity and effort

| Effort | Count |
| --- | ---: |
| Quick win | 232 |
| Heavy lift | 15 |
| Trivial | 1 |

| Domain (reviewer label) | Count |
| --- | ---: |
| Functional correctness | 130 |
| Data integrity and integration | 43 |
| Stability and availability | 26 |
| Maintainability and code quality | 25 |
| Security and privacy | 18 |
| Performance and scalability | 5 |

Security findings carried explicit CWEs: incorrect authorization (CWE-863) ×4,
SSRF (CWE-918) ×4, improper permission handling (CWE-732) ×2, OS command
injection (CWE-78) ×2, and one each of CWE-20, -200, -276, -345, -367, -377,
-522.

### Paperwork

**25 of 50 pull requests failed the description check.** Every failure asked for
the same three things: the template headings, each checklist item marked or
explained, and stated commit conventions. It is the single most repeated
finding in the sample and the cheapest to prevent.

### Concentration

| PR | Findings | What it was |
| --- | ---: | --- |
| #106 | 41 | installer docs rewrite |
| #80 | 33 | broad feature batch (UI + Rust + migrations) |
| #85 | 26 | onboarding and tours |
| #97 | 18 | Helm chart |
| #113 | 17 | Windows installer |

Long PRs are not proportionally worse. They are worse because one artifact class
repeats: #106 is one docs rewrite, #97 is one chart.

## What follows

1. **The cost is cheap defects, not hard ones.** 232 of 248 were "quick win". The
   missing capability was a local pass that reads artifacts the way the external
   reviewer does, not deeper expertise.
2. **The misses are artifact-shaped.** "A runbook is a program", "a workflow's
   concurrency is a lock", "a Helm schema is an API contract" are the three
   insights that close most of the gap. A generic code checklist does not
   surface any of them.
3. **Paperwork is a fifth of the cost.** Automate the evidence, not the prose.

## Skill evaluation

Every candidate was read in full before this verdict. "Adopt wholesale" means
the skill is loaded as written in the pass it belongs to. "Adopt parts" means
specific sections were carried into a reference pack. "Reference" means the
pass points at it without copying.

| Skill | Source | Verdict | What we took |
| --- | --- | --- | --- |
| `code-review` (CodeRabbit) | `coderabbitai/skills` | **Adopt wholesale** | The CLI invocation, NDJSON reading, severity preservation, and the autonomous fix-then-re-run loop. It is the oracle adapter, not a reviewer. |
| CodeRabbit CLI | `docs.coderabbit.ai/cli` | **Adopt wholesale** | `--agent` output, `--gate`, `--deep`, `--base`, `review findings`, `--show-prompts`, and the incomplete-run exit codes. |
| `receiving-code-review` | `obra/superpowers` | **Adopt wholesale** | Evaluate before implementing. Restate, verify, push back with evidence. No performative agreement. Already vendored in this workspace. |
| `verification-before-completion` | `obra/superpowers` | **Adopt wholesale** | The fix phase's evidence gate: a named command, run now, output read. |
| `requesting-code-review` | `obra/superpowers` | **Adopt parts** | The reviewer gets focused context, never the session history. Severity triage into fix now / fix before proceeding / record. |
| `systematic-debugging` | `obra/superpowers` | **Adopt parts** | The counterfactual and root-cause discipline, carried into the logic pass as the "fix test" and "counterfactual" checks. |
| `security-audit` | `cloudflare/security-audit-skill` | **Adopt wholesale (guidance mode)** | Trust-boundary scoping, principal/resource/outcome test, the six domains. Never the six-phase audit. |
| `insecure-defaults` | `trailofbits` | **Reference** | Pattern catalog for pass 4 when the diff touches config, defaults, or credentials. |
| `frontend-code-review` | `langgenius/dify` (pinned) | **Adopt wholesale** | Pass 7: evidence-first, rule routing by touched contract, and the seven reference packs. The Dify UI pack is ignored: this repository has its own tokens. |
| `code-review` | `getsentry/skills` | **Keep as generalist** | Runtime errors, bounds, N+1, backwards compatibility, and the "flag for senior review" triggers. Thin, and it does not overlap the artifact passes. |
| `rust-best-practices` | Apollo handbook (installed) | **Reference** | Pass 2 for ownership, error types, async pitfalls, and the `unwrap`/`expect` contract. |
| `postgres-best-practices` | Supabase (installed) | **Reference** | Pass 2 for RLS performance, locking, transaction isolation, and index choices. |
| `code-review-checklist` | installed | **Reference** | Generic breadth check when a diff does not match any specialized pass. |
| `deployment-procedures` | installed | **Reference** | Pass 6: rollout, rollback, and how to verify one. |
| `better-writing` | installed | **Reference** | Pass 5 register: plain words, active voice, no public meta-commentary. |
| `react-patterns`, `vercel-react-best-practices` | installed | **Reference** | Pass 7: effect dependencies, state ownership, and render cost. |
| `workers-best-practices`, `durable-objects` | Cloudflare (installed) | **Reference only** | The repository has a `workers/` tree, but no finding in the sample came from it. Loading them on every UI diff would be noise. |
| `coderabbit-config` | `coderabbitai/skills` | **Adopt parts** | `coderabbit config --agent --generate` to propose path instructions, and `--show-prompts` to see what the reviewer read. |
| `trail` | installed | **Use, not cite** | `trail callers` for the boundary-archaeology and writer-enumeration techniques. It finds the call sites a self-review assumes. |

### Not adopted, and why

- **The Sentry tone section.** Review output here is a report to a maintainer, not
  a comment to a contributor. Empathy guidance does not survive the format.
- **The Dify UI reference pack.** It teaches a design system this repository does
  not use; applying it would produce false findings against `docs/theme.md`.
- **The full Cloudflare six-phase audit.** A lane gate is not a pen test. The
  guidance-mode boundary is what keeps the pass cheap and repeatable.
- **A second generic code checklist.** There are already three in the workspace.
  More checklists correlate with less review, not more.

## Why the CodeRabbit CLI is the lever

The CLI runs the same pattern recognition as the pull-request review, reads the
repository's `.coderabbit.yaml` (including `path_instructions`), and can gate on
severity:

```bash
coderabbit review --agent --uncommitted
coderabbit review --agent --committed --deep --gate major
```

That is the only way to know, before the push, whether the external reviewer
will find anything. The measured difference matters: the local run is cheaper
and incremental, while `--deep` uses the pull-request policy.

Limits to respect, from the vendor's documentation:

- CLI reviews are not identical to PR reviews. They optimise for local feedback.
  Treat a clean CLI as strong evidence, not proof.
- Exit `1` is an **incomplete** review, not a clean one. Check `outcome` and
  `unreviewedFileCount`.
- `reused: true` makes a gate incomplete. It is not a fresh result.
- `review_skipped` with zero findings means no analysis ran.
- `--gate` requests a fresh full-diff review, so it costs more allowance than an
  incremental run. Two local runs per PR is a sensible budget.
- The rate limit is shared with the pull-request review. Burning it locally can
  delay the review everyone else is waiting on.

## Gaps the gauntlet does not close

- **Self-review bias.** The author still writes the passes. Parallel specialist
  subagents reduce it. They do not remove it.
- **Runtime behaviour.** No pass here substitutes for the E2E suite or the stack.
  The gauntlet names the gate. The human authorises it.
- **Product judgement.** A finding that needs a decision stays open at its real
  severity. The loop stops at "nothing left to fix", not "nothing left to
  discuss".
- **The external reviewer's learnings.** CodeRabbit folds explanations from PR
  replies into later reviews. A convention recorded only locally will be
  re-litigated in public. That is why a declined finding names where its reason
  lives, and why a third repeat is a config change rather than another argument.

## Recommended repository changes

These are proposals, not applied here.

1. **Path instructions for the artifact classes that dominate.** The current
   `.coderabbit.yaml` covers Rust, migrations, web, UI, event fixtures and
   public copy. OpenAPI pins and test paths have their own blocks. It says
   nothing about `docs/**` (non-site), `deploy/**`,
   `scripts/**`, `.github/workflows/**`, `deploy/helm/**`, or
   `release-notes/**`, which together produced 166 of 248 findings. Add blocks
   that state the conventions (runbooks execute in order, workflows serialize
   publication, schema changes preserve documented overrides) so the reviewer
   applies the repo's rule instead of re-deriving it.
2. **Name the SQLx exemptions.** Fourteen comments in one PR came from one path
   instruction and two declining replies. If some modules deliberately use
   runtime queries, name them in the instruction or in a module header. A
   disagreement settled in public is settled once.
3. **Fix the PR template's changelog line.** It says "`CHANGELOG.md` updated
   under `[Unreleased]`", but `CONTRIBUTING.md` says a PR adds a fragment and
   only `apply` writes the changelog. The template should say "release-note
   fragment added", or the description check keeps asking for something the
   contributor was told not to do.
4. **Optional CI job:** run `tools/gauntlet.sh --strict` on docs-only and
   infra-only PRs. Those classes are mechanical enough that a failing job is
   faster than a review round, and they do not need the Rust matrix.

## What to measure after adoption

| Metric | Now | Target |
| --- | --- | --- |
| PRs failing the description check | 50% | 0 |
| Median CodeRabbit findings per PR | ~5 (mean 5.0) | ≤ 2 |
| Review cycles per PR | unknown (not instrumented) | 1 |
| Findings per artifact class | see table | track the top three |

Track them from `gh api` with the same script that produced this document. A
class that does not fall after two releases is a missing rule, not a discipline
problem, and belongs in `LEARNINGS.md` with the pass that should have caught it.
