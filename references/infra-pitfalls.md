# Infrastructure pitfalls

Pass 6. Workflows, shell scripts, Helm charts, and release tooling produced 65 of
248 findings. Every one was semantic. A linter catch rate of zero is normal here:
the code parses, the YAML is valid, the script runs — and the property the author
believed is false.

Read the artifact's own failure mode.

---

## GitHub Actions workflows

### Reusable workflow calls

- A `uses: ./.github/workflows/x.yml` call sees no secrets unless the caller
  passes them: `secrets: inherit`, or each name declared under
  `on.workflow_call.secrets` in the callee.
- A missing secret does not fail the job. It arrives empty, and the login step
  that needs it skips silently. The failure surfaces later as an anonymous
  request the registry refuses.
- `needs` + `if` can skip a job the caller believes ran. Check the condition
  against every path.

**Worked example:** an image build called a reusable workflow to log in to a
private registry, passed no secrets, and the login step exited early. The build
then pulled anonymously — the exact request the PR was fixing.

### Concurrency

Three separate properties, often confused:

| Property | Setting | What it does not do |
| --- | --- | --- |
| Do not cancel the running release | `cancel-in-progress: false` | does not keep a third pending run |
| Keep every pending release | `queue: max` | does not serialize different groups |
| One lock across triggers | a group keyed by the artifact version | a tag run and a dispatch run are different groups by default |

- A publish flow needs one serialized operation around **both** the existence
  check and the push. A check in one job and a push in another is a race even
  with `needs`.
- Registry pushes are usually overwrite-friendly. "It already exists" is only a
  guard if something enforces it.
- `needs` does not order two runs of the same workflow.

### Path filters and required checks

- A `paths:` filter that omits a needed path leaves the job **skipped**, and a
  skipped required check can block a merge forever.
- A rename is two paths. Filter on `github.event.pull_request.files[].previous_filename`
  as well, or a renamed file slips past the filter.
- A docs-only PR that skips the Rust matrix must still satisfy the required check
  names, or the branch is unmergeable. Either keep a cheap always-on job with
  the same name, or make the required check path-agnostic.
- `continue-on-error` on a required job makes the check green and the guarantee
  false.

### Caching

- A cache key must include everything that changes the output: lockfile hash,
  toolchain version, target triple, profile.
- A cache restore that lands **after** the step that needed it saves nothing.
  Order: restore, use, save.
- `RUSTC_WRAPPER`/`sccache` set in one step must be visible in the step that
  compiles. Per-step `env:` is not global.
- Saving on every branch multiplies storage and thrashes. Save on the default
  branch, restore everywhere.
- A cache that holds a poisoned or stale artifact is worse than a cold build. If
  the key cannot express the change, do not cache it.

### Permissions and identity

- Default `permissions:` to read, then grant per job. A workflow that can write
  contents can publish a release from a branch you did not intend.
- `pull_request_target` plus a checkout of the pull request head is arbitrary
  code execution with a write token. Never combine them.
- The actor who signs a release, comments, or pushes is the identity in the
  token. A bot that pushes with the default token triggers no downstream
  workflow.
- An `if:` that gates on `github.actor` is not authorization; the actor can be a
  bot.

### Artifacts and outputs

- Artifact names are shared across matrix legs. Two legs uploading `build` race
  and overwrite. Name them `build-${{ matrix.target }}`.
- A digest produced in one job reaches another through `outputs:`, not through a
  file the second job does not have.
- `download-artifact` with `merge-multiple: true` loses per-leg structure.
- A release created before its assets upload is visible, half-empty, and can be
  consumed by a user in the gap.

### The workflow's own run

- A step that shells out has `set -e` semantics only if the shell is bash **and**
  the script sets it. `shell: bash` defaults to `-e` in Actions; a custom shell
  string may not.
- A failed command in an `if` condition does not stop the job, `set -e` or not.
  `if helm show chart …; then` treats a timeout as "does not exist". Distinguish
  a confirmed absence from an unknown result.
- A `run:` block that pipes through `tee` loses the exit status unless `pipefail`
  is set.

## Shell scripts

### The preamble

```bash
set -euo pipefail
```

Then immediately account for the exceptions: a command expected to fail goes in
an `if`, or gets `|| true` with a comment saying why.

### Arguments

- Parse both `--flag value` and `--flag=value` if the tool is user-facing.
- `set -u` plus `$1` on an empty argument is an exit. Use `${1:-}`.
- An unknown flag exits non-zero with a message, not silently ignored.
- Validate before acting: existence, writability, a real calendar date, a
  relative path that resolves.

### Paths

- `cd "$dir"` without `|| exit` continues in the wrong directory if the move
  fails.
- A relative path is relative to the **current** directory. After any `cd`, a
  path captured earlier is wrong. Resolve to absolute once, at the top.
- Preserve the caller's working directory: run in a subshell, or restore it.
- `--dir` and `BUNDLE_DIR` accept relative paths from the user. Resolve them
  before you `cd` away.

### Cleanup

- `tmp=$(mktemp -d)` then `trap 'rm -rf "$tmp"' EXIT` — in that order. A trap that
  references an unset variable under `set -u` fails to fire.
- Cleanup must not delete what the script does not own: the install directory,
  the user's env file, a previous backup, the logs a failed run needs.
- A failure path that runs `down -v` or `rm -rf` destroys the evidence for the
  failure. Preserve by default; destroy only on an explicit flag.

### Exit codes

- A function's failing command inside `$(...)` is invisible unless you check
  `$?` or the function returns it.
- `cmd | tee log` returns `tee`'s status. `pipefail` fixes the pipeline; it does
  not fix a command substitution.
- An E2E script that stops at the first failed step and reports success because
  the last command succeeded is the worst case. Accumulate failures explicitly.

### Ordering

- Start the log or event stream **before** the action you want to observe, drain
  it **after** the action completes, and read it only then.
- Write the new file, then move it into place. A partial write is a corrupt file.
- Generate secrets before the file that consumes them is written.

### Values that invert

- URL-encode a credential that goes into a DSN. `p@ss/word` breaks the URL.
- Normalise before comparing: `docker.io/library/busybox:1.36` and
  `busybox:1.36` are one image, and an archive membership check that compares
  strings rejects the archive it needs.
- Normalise a version: `v0.4.0` and `0.4.0` are one release.

### Probes and readiness

- A container probe against a database during first-time initialisation can hit
  the temporary server the entrypoint starts. Probe the address the real server
  listens on (TCP with host and port), not the unix socket.
- `pg_isready` without `-h` is a socket probe. Add `-h 127.0.0.1 -p <port> -d <db>`.
- A readiness check must fail closed. A probe that returns 0 on error is not a
  probe.

## Helm charts

### Schema and template parity

- Every key the templates read must be declared in `values.schema.json` **and**
  in `values.yaml`. A key in neither is an override that silently does nothing; a
  key in the schema but not the template is a promise the chart does not keep.
- `additionalProperties: false` is correct only after **every** key the chart or
  a documented override uses is declared. Close a block early and you reject
  settings users have relied on.
- Placement blocks (`affinity`, `tolerations`, `nodeSelector`) pass Kubernetes
  shapes through. Either validate their item shape or leave them open — do not
  half-close them.

### Type coercion

`--set` produces integers and booleans, not strings. If a value is quoted in the
template but supplied by `--set`, the schema must accept both.

| Field | Common break |
| --- | --- |
| resource quantities (`cpu`, `memory`, `ephemeral-storage`) | closed to `cpu`/`memory`, or string-only |
| `smtpPort`, ports | string-only schema, numeric `--set` |
| storage sizes (`garage.capacity`) | string-only, numeric byte count |
| `nodeSelector` values | numeric label value rendered as a number |
| `tolerations` items | a bare string where an object is required |
| probe `timeoutSeconds` | present on liveness/readiness, missing on startup |
| PDB `maxUnavailable` | `"10"` read as ten pods, not ten percent |
| `topologySpread.maxSkew` | `0` passes the schema, Kubernetes rejects it |
| NetworkPolicy `extraIngress` items | `null` renders an empty rule that allows everything |

### Render and compare

```bash
helm lint deploy/helm/<chart>
helm template <release> deploy/helm/<chart> --values <a real user values file>
```

Render with the values a user is told to set. The defects above are invisible at
defaults and appear at the override the documentation recommends.

### Release semantics

- A chart version is immutable once published. Publishing must be create-only or
  serialized; Helm push does not enforce it.
- `appVersion` and the image tag must be the same release, or the chart claims a
  version it does not deploy.
- A hook or Job that runs on every upgrade needs an idempotent body and a
  `helm.sh/hook-delete-policy`.
- A rendered manifest with a duplicate key (two `nodeSelector` blocks) can be
  rejected by a strict parser.

## Images and release bundles

- Build each architecture on a native runner, then join the digests in one job.
  An emulated build is slow and occasionally wrong.
- Publish by digest and reference the digest. A tag can move between plan and
  publish.
- An offline bundle is complete only if every image the compose file names is
  inside it, under the reference the consumer will look up.
- Checksums must cover hidden files and the exact tree that ships. A checksum
  over a glob that misses `.env.example` is a checksum of something else.
- Give each run its own temporary directory. Two concurrent runs sharing one path
  delete each other's files.
- The release is created after the assets succeed, not before.
- A pin to "the latest installer" is not a pin. Each shipped installer names the
  release it belongs to.

## The pass

For each changed artifact:

1. Name the property the author believes (serialized, authenticated, complete,
   idempotent, backward compatible).
2. Find the line that enforces it.
3. Ask what a second run, a concurrent run, a retry, a timeout, or an older
   client does.

If step 2 has no answer, the property is a hope.
