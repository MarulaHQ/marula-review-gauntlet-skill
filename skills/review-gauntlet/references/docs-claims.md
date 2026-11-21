# Docs and claims

Pass 5. Documentation produced 86 of 248 substantive findings across the sampled
pull requests — more than Rust, more than CI. Almost none of them were typos.
They were **claims that the code did not honour**, or instructions that could not
be followed in the order printed.

A runbook is a program. Read it as one.

---

## The rule

> The claim equals the code.

For every changed sentence, find the thing it describes and check that the two
agree. If the sentence describes a sequence, check that the sequence executes.

Write the claims out. A claim table is the pass:

| Claim (quote it) | Where the truth lives | Verdict |
| --- | --- | --- |
| "verifies the download before running it" | `scripts/release/bootstrap-install.sh` | **broken** — runs, then verifies |
| "defaults to Postgres on 5432" | `deploy/docker-compose.yml` | **broken** — defaults to pgbouncer:6432 |
| "`secrets:edit` reveals the value" | `crates/core-api/src/routes/…` | **broken** — gates edit, not reveal |
| "Node 22 or later" | `package.json` engines + `corepack` history | **broken** at 25 |

Three verdicts are allowed: **verified** (you found the code), **fixed** (you
changed one side), **removed** (the claim was not worth making true). "Probably
fine" is not a verdict.

## What to scan

### Commands and flags

- Every command block runs, in the order printed, from the directory the reader
  is in.
- Every flag exists in the program it is attached to. `--profile pooler` must be
  a profile the compose file defines. `--breaking` must be a flag the script
  parses.
- A `curl … | sh` is execution. If the next paragraph says "verify the download",
  the verification must come **before** the pipe, with a separate download step.
- A relative path resolves from where the command is run, not from the repo root.
- Two commands in one block that must run in order are in one block, or the text
  says so.

### Values

- A default stated in prose is a value in a config file. Check the file.
- A port, version, image tag, file size, or timeout in prose matches the code.
- A password or URL stated in prose survives the next rotation. If the URL
  embeds a credential, say what must be updated when it changes.
- A count ("three replicas", "two databases") matches the manifest.

### Names

- The filename in step 3 is the filename created in step 1. A `-2026` suffix in
  one place and not the other makes the guide unfollowable.
- A permission name in prose is the permission the handler checks.
- A component, flag, env var, or path mentioned in prose exists with that exact
  spelling. Run `grep -r -- '--flag'` before you write it.
- The same product name, in the same casing, everywhere.

### Scope words

`only`, `always`, `never`, `first`, `before`, `all`, `cannot`. Each is a
quantifier, and each is testable. "Audio never leaves the browser" is false
unless local processing is guaranteed and available for the language. "Admins
cannot see other clients" is false if the tool can read anything the user may.
"The pooler is optional" is false if the default URL points at it.

**Method:** highlight every quantifier in the changed prose and delete it. Does
the sentence still say what the reader needs? If yes, the quantifier was noise.
If no, it was a claim — verify it.

### Prerequisites

- The version floor is the version the tool actually works on, including the
  minor that removed a bundled tool. Corepack stopped shipping with Node 25; a
  guide that says "Node 22+" and then runs `corepack enable` breaks on a clean
  install.
- A prerequisite the reader must install is a step, not a footnote.
- A step that needs root says so, and gives the non-root path.

### Links and anchors

- A relative link resolves from the file it is in.
- A link to a section uses the heading that exists, not the one that was renamed.
- A link to a download says **which** download. "Verify it" after two downloads
  is ambiguous.

`tools/gauntlet.sh` checks relative links and dead backticked repo paths
mechanically. It does not check whether the sentence is true.

## Duplicated claims drift

The same fact often lives in three files: `README.md`, `docs/install.md`, and
`deploy/README.md`. The review found the same wrong default in all three, and
the same broken rotation command in two.

**Rule:** when you fix a claim, grep for the sentence's subject across the
repository and fix every copy in the same commit. A claim repeated in three
places is one claim and three chances to drift.

```
rg -n -- 'pgbouncer:6432|smtpPort|marula-release-2026' --glob '*.md'
```

## Generated pages

A page built from a source file is not editable. If the fix belongs in the
source, fix the source and regenerate with the sanctioned script; never hand-edit
the output. A hand edit is undone by the next regeneration, and the reviewer can
see it because the file carries a header saying so.

## Tables and glossaries

- Escape pipes inside markdown table cells. An unescaped pipe splits the row.
- A glossary entry keeps whatever contract its neighbours have — if every entry
  ends with a link to the guide that explains it, the new one does too.
- A list of options keeps the same shape: name, meaning, default. A row missing
  the default column is a question the reader has to ask.

## Register

Public pages are read by users, not by the team.

- No lane, wave, PR, phase, or requirement numbers. No internal planning
  references.
- No meta-commentary about the review ("this is not invented", "verified against
  the code"). Cut it.
- No defence of a decision the reader did not question.
- Plain words, active voice. "The installer verifies the archive" beats "the
  archive will be verified by the installer".
- A changelog bullet answers "what changed for me?", never "what commits
  merged".

## Checklist

Before you call pass 5 done:

- [ ] Every changed command block has been read top to bottom as a program.
- [ ] Every default, port and filename has a source in the code.
- [ ] Every quantifier (`only`, `never`, `always`, `first`) is verified or
      deleted.
- [ ] Every relative link and backticked path resolves.
- [ ] Every duplicated claim was fixed in every copy.
- [ ] Generated files were regenerated, not edited.
- [ ] Public prose has no internal identifiers and no meta-commentary.
- [ ] The PR body checklist is filled with evidence, not blanks (see
      `pr-contract.md`).
