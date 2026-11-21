# Logic and pitfalls

Pass 3. The defects here are invisible to the compiler, invisible to a linter,
and invisible to the author, because the author is reading their intention.

The pass is not "look harder". It is a set of questions that produce a concrete
failure scenario, or nothing. If a technique produces a feeling rather than a
sentence, it produced nothing.

Every example below is a real finding from this repository's review history.

---

## 1. The invariant ledger

**Ask:** what must always be true, and which line enforces it?

Write the invariants the change depends on. Not the behaviour — the rules.

```
- A ticket is only readable by a caller who can see its client.
- An idempotency replay returns the same response only to a caller who could
  make that request now.
- A project's pods always reference role keys that exist.
- Money is stored in minor units and never in floating point.
- A row written in org A is never read in org B.
```

Then, for each invariant, find the **enforcement**, not the mention.

A mention looks like this: `require_ticket_visible(&tx, &ticket).await?`. It
enforces the invariant for the path that runs it. The finding is the path that
does not.

Real finding: the replay branch returned the stored response before the
visibility check ran. The invariant was written down; the enforcement covered
the fresh path and the replay path was above it. A user who lost access to a
restricted client could replay an older request and read the ticket again.

**Method:** for each invariant, `trail callers <enforcer>` and read every call
site. The defect is in the caller that does not appear.

## 2. Enumerate return paths, not statements

**Ask:** for every exit from this function, what has been checked by then?

List the exits. A handler has more than the happy one:

```
1. body parse error        -> 400, no check needed
2. permission denied       -> 403
3. idempotency replay hit  -> returns stored response   <-- checked?
4. validation failure      -> 422
5. conflict                -> 409
6. fresh success           -> 201, checks run
7. downstream error        -> 502
```

Ordering is the bug. A check placed after an early return protects nothing, and
the early return is usually the one someone added for performance or
idempotency.

Real finding: the transition route checked visibility in its own transaction,
committed, then called a service that loaded the ticket again with no check. Two
steps, one check, a window in the middle.

**Method:** copy the function, delete every line, and keep only the exits. Read
the list top to bottom. The gap is visible when the bodies are gone.

## 3. The bug report

**Ask:** what would the support ticket say?

Write the sentence a user or operator would send. If you can write it in one
line, the path is reachable. If the sentence needs a condition nobody can hit,
you have found nothing.

```
"After I moved the ticket to a restricted client, my colleague could still see
 the title in the link panel."
"The installer said it verified the download, but it ran the script first."
"The upgrade deleted my env file and I had no backup."
"Two releases ran at once and the chart version is now the old one."
```

This is the fastest pass for prose and runbooks, because a runbook failure is
literally a sentence someone types.

Real finding: `docs/install.md` told the reader to verify the download, in a
section where the preceding command executed it. The bug report writes itself.

**Method:** for each changed behaviour, write one sentence. Reject the ones that
require an event the system cannot produce. Fix the rest.

## 4. The assumption audit

**Ask:** what does this line assume, and what is the cheapest way it is false?

Read the diff for these tokens, and for each one name the assumption:

| Token | Assumption it encodes |
| --- | --- |
| `unwrap`, `expect`, `!`, index `[0]` | the value exists |
| `as` cast, `Number()`, `parseInt` | the value is in range and well formed |
| `==` on floats, dates, ids | the representation is stable |
| `Some(x)` after a `get` | the row was not deleted in between |
| `Default::default()` | the default is the right business value |
| a constant | the constant matches the environment |
| `role: "admin"` | roles do not change mid-request |
| `localhost`, `:3000`, `:8080` | the port is the one in the other file |
| a timestamp captured once | time does not move during the operation |

Real finding: two reads in one transaction at READ COMMITTED take two snapshots.
The ticket body and its ETag could come from different committed states. The
assumption was "a transaction is a snapshot"; it is not, by default.

Real finding: a factory stamped `now` inside one transaction, so every row it
created shared a timestamp and keys built from `(timestamp, kind)` collided.

**Method:** list the tokens, list the assumptions, then ask which caller, clock,
retry, or concurrent request can falsify each one.

## 5. Failure injection

**Ask:** what if this call fails, and what if it fails in the second-worst way?

Not "what if it errors" — errors are handled. The second-worst way:

- **Time out** after the write landed but before the response arrived.
- **Return stale** data that is valid but older than the caller assumes.
- **Arrive twice** because the queue is at-least-once.
- **Arrive late**, after the user navigated away or the row was deleted.
- **Succeed partially**: the row inserted, the second statement rolled back with
  the transaction.
- **Return `200` with an error body**, or `204` with no body where a body is read.

Postgres detail worth knowing: a failed statement aborts the whole transaction.
If a later write must still land, the failing one needs a savepoint. A `?` on a
query inside a transaction is not a local failure.

Real finding: a cleanup ran `down -v` on failure, destroying the data the failed
run was supposed to help diagnose.

**Method:** for each external call, write the five lines above and mark which
one the code handles. Unmarked lines are the finding.

## 6. Concurrency and ordering

**Ask:** what happens if two of these run at once, or if the second starts
before the first finishes?

Four shapes, all common:

1. **Read, decide, write.** Needs a row lock or one snapshot. A sequence lock
   taken after the read does not protect the value read before it.
2. **Check, insert.** Needs the constraint, an exclusion constraint, or a lock on
   the parent. A unique index on one column does not stop overlapping ranges.
3. **Two reads that must agree.** Body + revision, setting + value, total +
   lines. One snapshot, or one query.
4. **Retry or redelivery.** Anything that can run twice must be idempotent, and
   the idempotency key must cover every field the operation applies. Omit one
   and two different requests share an identity.

Real finding: a project row was locked after the plan was read, so the
concurrent edit between the read and the lock was silently overwritten.

Real finding: a fingerprint that decided "is this proposal still applicable"
omitted the end date, so two different drafts had one identity.

**Method:** draw the two timelines side by side. If the interleaving is legal and
the result is wrong, it is a finding.

## 7. Boundary archaeology

**Ask:** who else calls this, and does the change hold for them?

The diff is safe at the call site you are looking at. The same function has four
other callers, one of which passes `None` for the field you just made required.

```
trail callers <symbol>            # exact call edges
trail ask "<symbol> callers" --source
```

Real finding: a `ProjectPatch` field was added, and one literal that constructed
the struct was not updated — the compiler caught that one, and the reviewer
asked whether every constructor had been found. It had not, in a test fixture.

Real finding: a helper gained an archive filter, and the delete path that reused
it stopped removing edges to archived rows. Safe at the new call site, wrong at
the old one.

**Method:** for every changed signature, default, or filter, list the callers and
read the arguments they pass.

## 8. The config and default matrix

**Ask:** what happens with the value unset, with an empty value, and with a legacy value?

A default is a promise. Enumerate the real inputs:

| Input | Question |
| --- | --- |
| unset | what does the code do with no value? |
| empty string / `0` / `[]` | is that the same as unset? |
| overridden by env | does the override reach the place that reads it? |
| overridden by flag | does the flag win over the env, as documented? |
| legacy value | does the old spelling still work? |
| quoted vs numeric | does the type coercion match the consumer? |

Real finding: a Helm schema closed a block to the keys the chart knew about, and
rejected `ephemeral-storage` and a numeric `cpu: 2` that users had been setting
for a year. The chart was correct; the schema broke the override.

Real finding: `--set email.smtpPort=587` supplies an integer, the schema only
accepted a string, and the documented override stopped working.

**Method:** write the matrix. The empty column is the finding.

## 9. Upgrade and rollback

**Ask:** what does the new code do to data the old code wrote, and what does the
old code do to data the new code wrote?

- A new column with a default is a forward change. A new `NOT NULL` without one
  is a break for the running writer.
- A new event field is additive. A removed field is a contract break for one
  generation of readers.
- A new index takes a lock on a large table.
- A migration that already ran will not run again, so editing it changes nothing
  except the checksum, which can fail the runner at startup.
- A revert leaves rows the old code cannot represent.

Real finding: a merged migration was edited in the PR. Every database that
applied it keeps the old shape; the checksum change can stop the runner from
starting at all.

**Method:** for each schema or wire change, write the mixed-version state and ask
whether both versions can read and write.

## 10. The untested branch

**Ask:** which line in this diff does no test reach?

Coverage tools tell you the line was executed; they do not tell you the
assertion would fail without the behaviour. The question is narrower: is there a
branch whose only witness is the author's imagination?

Then, for the tests that do exist:

- Would the assertion fail if the behaviour were removed? `expect(x).toBeTruthy()`
  where `x` may be `null` proves nothing.
- Does the test reach the branch it names? A test titled "closes without
  cancelling" must click close.
- Is the fixture timezone-stable, and are its ids real hex UUIDs?
- Is there an overlap case: a stale response arriving after a newer one?

Real finding: a tour test asserted the tour existed but not that it was scoped to
the surface, so a global tour passed.

## 11. Hidden coupling

**Ask:** what does this share that the author did not name?

- Module-level or singleton state across requests.
- A cache key that omits the tenant, the user, or the locale.
- A timestamp or id that is unique per process but not per row.
- A selector that matches a neighbour's element (`[data-tour]` in two places).
- A list that one component sorts and another reads positionally.
- A background job and a request that write the same row.

Real finding: the command palette merged completions from an old query with the
new one, so a slow early response repopulated a filter the user had cleared.

## 12. Money, time, units, rounding

**Ask:** is this the same number in every place it is represented?

- Minor units vs major units, and where the conversion happens.
- Half-even vs half-up; the server and the preview must agree.
- A date parsed as local midnight and serialised as UTC moves a day east of UTC.
- A duration in months is not a duration in days.
- Percentages: of what base, rounded when.
- `Number("1,200")` is `NaN`; `JSON.stringify(NaN)` is `null`.

Real finding: a contract preview used local rounding while the server used
half-even, so the total shown differed from the total saved.

**Method:** pick one value that flows through the diff and trace it end to end,
with its unit written next to every stop.

## 13. The second reader's rule

**Ask:** what will the next person to edit this file get wrong?

The code is a message to the future. If the next edit is likely to reintroduce
the bug, the fix is incomplete even though the bug is gone.

Signals: a guard that looks removable, a comment that explains a workaround
without saying it is one, a test that does not say why the case exists, an
optional parameter whose default is the dangerous value.

The fix is a module header line, a named constant, or a test whose name states
the invariant. Put the reason where the next editor will be looking, not in the
pull request description, which nobody re-reads.

## 14. Kill list

Do not report these. They are how a logic pass turns into noise, and noise is
how the real findings get skipped.

- **Style and preference.** Formatting, naming, structure, "consider extracting".
- **Pre-existing defects** unrelated to the change. Note them in the report under
  accepted risks if they matter; do not block the diff on them.
- **Unreachable hypotheticals.** "If a caller passed `null` here" when the type
  or the route forbids it.
- **Missing abstraction.** Two similar functions are not a defect until the third
  appears.
- **Anything you cannot point to.** No line, no finding.
- **A second instance of a class already reported.** Report the class once and
  name the siblings in the evidence.

## Calibration

The logic pass is where inflation happens. Two tests keep it honest:

1. **The counterfactual.** If this line did not exist, what would break? If the
   answer is "nothing observable", it is not a finding.
2. **The fix test.** Can you name the smallest correct change? If the only fix is
   "restructure the feature", it is a design finding — report it as open, at its
   real severity, with the options.
