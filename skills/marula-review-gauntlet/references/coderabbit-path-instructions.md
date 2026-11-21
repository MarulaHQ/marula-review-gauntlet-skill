# Proposed `.coderabbit.yaml` path instructions

Proposal, not applied. Review it with the maintainer before committing:
`path_instructions` are rules the external reviewer applies verbatim, so a wrong
line costs a review round every time it fires.

The purpose is not "look harder". It is to state conventions the repository
already follows, so the reviewer stops re-deriving them and so a deliberate
choice stops reading as a defect. The blocks below cover the path classes that
produced 166 of 248 findings and have no instruction today.

Append under `reviews.path_instructions`:

```yaml
    - path: "{docs/**,README.md}"
      instructions: |
        - A runbook is a program: the commands execute in the order printed,
          from the directory the reader is in. Flag a verification step that
          runs after the thing it verifies, a flag the referenced script does
          not parse, or a relative path that does not resolve from that
          directory.
        - A default, port, version or filename stated here is a value in a
          config file or a filename a script creates. Flag a claim that does
          not match the source, and a claim repeated across README,
          `docs/install.md` and `deploy/README.md` that was fixed in only one.
        - Quantifiers are claims: "only", "always", "never", "first", "before".
          Flag one the code does not enforce.
        - Prerequisites are steps, not footnotes. A version floor must be the
          version the tool works on, including a release that removed a
          bundled tool.

    - path: "{scripts/**,deploy/docker-compose.yml,deploy/install.sh}"
      instructions: |
        - Scripts set `set -euo pipefail`, parse both `--flag value` and
          `--flag=value`, and resolve user paths before changing directory.
          `set -e` does not stop a failed command used as an `if` condition.
        - Cleanup removes only what the script created. A failure path keeps
          the logs, env file and previous backup it may need to diagnose the
          failure; `down -v` and `rm -rf` run only on an explicit flag.
        - A log or event stream starts before the action it observes and is
          read after the action finishes.
        - Compare normalised values: `docker.io/library/x:1` and `x:1` are one
          image; `v0.4.0` and `0.4.0` are one release.
        - A credential placed in a DSN is URL-encoded and is updated when the
          credential rotates.

    - path: ".github/workflows/**"
      instructions: |
        - A reusable workflow call passes the secrets it needs explicitly, or
          `secrets: inherit`. A missing secret arrives empty and the step that
          needs it skips silently.
        - Publication is serialized across every trigger that can produce the
          same artifact, including both the existence check and the push.
          `cancel-in-progress: false` does not keep a third pending run.
        - A `paths:` filter must not leave a required check skipped, and a
          rename matches `previous_filename` too.
        - A cache is restored before the step that uses it, and its key covers
          the lockfile, toolchain and profile.
        - Default `permissions:` to read. `pull_request_target` never checks out
          the pull request head.
        - A release is created after its assets upload.

    - path: "deploy/helm/**"
      instructions: |
        - `values.schema.json` is a public contract: a documented override that
          the chart used to accept must still validate. Accept both a string
          and a number where `--set` can produce a number, and declare every key
          the templates read before closing a block with
          `additionalProperties: false`.
        - Kubernetes shapes are validated as shapes: `nodeSelector` values are
          strings, `tolerations` items are objects, a PDB `maxUnavailable` is a
          percentage or a count, and `topologySpread.maxSkew` is at least 1.
        - A rendered manifest must not carry a duplicate key.
        - A chart version is immutable once published.

    - path: "release-notes/unreleased/**"
      instructions: |
        - One fragment per change, written with
          `node scripts/release-note.mjs add --bump <patch|minor|none>`, and the
          bump matches what a user gets: `minor` for a capability, `patch` for
          a fix, `none` for product code with no visible change.
        - The bullet answers "what changed for me?" in the user's voice. No
          wave, lane, PR or file numbers, and no internal planning.
```

## Two changes worth making regardless

1. **Name the SQLx exemptions.** Fourteen comments in one PR came from the
   `**/*.rs` instruction and two replies declining it. If some modules
   deliberately keep runtime queries, name them in the instruction or in a
   module header. A disagreement settled in public is settled once.
2. **Fix the PR template's changelog line.** It asks for
   `CHANGELOG.md` under `[Unreleased]`, while `CONTRIBUTING.md` says a PR adds a
   fragment and only `apply` writes the changelog. The description check keeps
   asking for something the contributor was told not to do.
