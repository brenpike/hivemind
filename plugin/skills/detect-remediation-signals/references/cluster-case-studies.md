# Cluster Case Studies — Worked Exemplars

Six worked examples from a real multi-day review spiral (~20 P1/P2 findings).
They are **few-shot exemplars that TEACH the judgment** in `detect-remediation-signals` —
they are NOT test fixtures and NOT an exhaustive taxonomy. Each shows: the finding sequence
(symptoms) → the shared root → the `fix_framing` / `root_class` label → which signal fires →
the closed-by-construction structural fix that made the next same-framing finding impossible.

These ground the doctrine's vocabulary in lived experience. For the binding definitions, read
`${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md`.

## Contents

1. YAML hand-parse injection — real parser (cluster)
2. Validator charset treadmill — positive allowlist (cluster)
3. NUL-via-bash-command-substitution — reject NUL where bytes are intact (cluster)
4. Read-failure-looks-like-empty — shape-validated read + sentinel (cluster)
5. Trusting manifest-declared paths — ground-truth derivation in the same PR (cluster)
6. Break-fix instance — per-construct edit recurrence (break-fix)
7. Cross-iteration young-surface recurrence — shared query primitive (cluster)

The common shape of the first five: each is one root presenting as N "different" comments.
Patching any single instance only spawns the next symptom on the next pass — the **same
framing, different byte/field/path**. The sixth shows the opposite failure mode: a fix that
itself reintroduces a defect, which is break-fix, not cluster.

---

## 1. YAML hand-parse injection (cluster)

**Symptoms (5+ findings):** description block-scalar field-override; multiline `name`
block-scalar injection; nested-mapping key spoof; recurring block-scalar / indent fights.

**Shared root:** a line-based sed/awk extractor cannot separate YAML *structure* from
attacker *content* — every new injection vector is the same defect with a different YAML
construct.

- `fix_framing`: `hand-parse-untrusted-yaml`
- `root_class`: `structure-content-confusion`

**Signal fired:** root-cluster. The same-framing test is "yes" — the next comment would be
another block-scalar/indent trick. Five same-framing members at N≥3 trips the cluster.

**Closed-by-construction fix:** convert the manifest to JSON parsed by `jq` — a real parser
cannot confuse content for structure, dissolving the whole class. (ADR-0018 §A,
format-follows-consumer, already mandated this; it was missed because the manifest was not
re-classified when it gained a `jq` consumer.) Prefer **a real parser over hand-parsing**.

## 2. Validator charset treadmill (cluster)

**Symptoms (5+ findings, one per round):** reject spaces → reject hash/equals/tilde/bang →
reject VT/FF controls → reject pipe → reject plus/at/comma → (next would be percent, caret …).

**Shared root:** the validators were reject-enumeration (blacklist) — every round finds one
more byte to ban, forever.

- `fix_framing`: `reject-enumeration`
- `root_class`: `blacklist-charset-validation`

**Signal fired:** root-cluster. The same-framing test is "yes" — the next comment is always
"reject one more byte." The per-round, one-byte-at-a-time shape is the textbook treadmill.

**Closed-by-construction fix:** positive allowlists (anchored character-class, closed by
construction) — an unlisted byte (control bytes, Unicode bidi U+202E, markdown structural) is
rejected by default. Prefer **positive allowlist over reject-enumeration**.

## 3. NUL-via-bash-command-substitution (cluster)

**Symptoms (3 findings):** (a) a child ledger `run.status` value containing a NUL byte; (b) a
manifest file containing a NUL byte; (c) a `\u0000` JSON escape that `jq` decodes to a real
NUL in a scalar.

**Shared root:** untrusted bytes pass through bash command substitution, which silently drops
NUL, so the validator sees a shorter string than `jq` produced — a lossy round-trip before
validation.

- `fix_framing`: `validate-after-lossy-roundtrip`
- `root_class`: `nul-stripped-by-command-substitution`

**Signal fired:** root-cluster (N=3, default threshold). Three distinct entry points, one
root.

**Closed-by-construction fix:** reject any file containing a NUL byte, and reject control
bytes inside `jq` during projection — **validate where the bytes are intact**, so no value is
silently altered before validation.

## 4. Read-failure-looks-like-empty (cluster)

**Symptoms (3 findings):** malformed manifest → silent zero strains; valid-JSON-wrong-shape;
multi-document JSON stream.

**Shared root:** a read/parse failure was indistinguishable from a legitimately empty brood,
hiding live children.

- `fix_framing`: `read-failure-conflated-with-empty`
- `root_class`: `unvalidated-read-shape`

**Signal fired:** root-cluster (N=3). Each symptom is a different way the read can fail open.

**Closed-by-construction fix:** a single-snapshot shape-validated read + a
`MANIFEST_UNREADABLE` sentinel + a single-document requirement (`jq` slurp, `length==1`), so a
failed read is loud and distinct from empty.

## 5. Trusting manifest-declared paths — containment family (cluster)

**Symptoms (4 findings):** symlinked-manifest-leaf; worktree-residency-under-checkout;
symlink-swap TOCTOU; worktree-must-be-a-real-worktree.

**Shared root:** the coordinator anchors reads to untrusted manifest paths, and each round
adds one more containment check.

- `fix_framing`: `trust-untrusted-path`
- `root_class`: `manifest-declared-path-trust`

**Signal fired:** root-cluster (N≥3). The same-framing test is "yes" — the next comment would
be one more containment check on the same untrusted path.

**Closed-by-construction fix:** derive the worktree from `git worktree list` ground truth and
stop trusting the manifest path — prefer **ground-truth derivation over validating untrusted
input**. With the manifest path no longer the anchor, containment findings on it cannot exist.

**Lesson:** a found root cause is fixed at its source in the PR that found it, per the
doctrine's `## First-Finding Triage`, and is never deferred. The reviewer routes the cluster to
this structural fix in the same PR — never to N more per-finding containment patches, and never
to a deferral.

## 6. Break-fix instance — per-construct edit recurrence (break-fix, NOT cluster)

**Symptoms:** a single-snapshot fix introduced a `cat` with a discarded exit status, so an
unreadable ledger downgraded to `MISSING` instead of `MALFORMED`. The reviewer caught it the
next iteration and noted the ledger-read-site had been touched in 3 consecutive iterations.

**Shared root:** each fix is itself a change that can spawn the next finding — the ledger-read
construct was edited, broke, re-edited.

- `fix_framing`: `discard-exit-status-on-read`
- `root_class`: `fix-reintroduced-prior-defect`

**Signal fired:** break-fix, not cluster. The defect is *instability* (a fix that breaks a
prior fix / re-edits the same construct), not a class of same-framing symptoms across files.
Per-construct edit recurrence — the SAME `file:line-range` touched in 3+ consecutive
iterations — raises break-fix sensitivity. break-fix is MANDATORY and outranks cluster in
precedence.

**Lesson:** track per-construct edit recurrence; a construct repeatedly touched is a
break-fix risk even when each individual edit looked correct in isolation.

## 7. Cross-iteration young-surface recurrence — shared query primitive (cluster)

**Symptoms (3 findings, across distinct loop iterations on a freshly-introduced module):**
iteration 1 — a duplicate record slips through because an existence check used a fuzzy/approximate
search as an exactness oracle; iteration 2 — a DISTINCT framing on a different line of the same
module: a pagination boundary on the same search call drops a match; iteration 3 — yet another
framing, a case-fold mismatch in the same lookup. The framings differ each pass and the line
ranges are disjoint, so the within-pass `fix_framing` and `file:line-range` keys do NOT cluster
these.

**Shared root:** the module is YOUNG — introduced in this same initiative — and keeps absorbing
findings across iterations, all orbiting ONE underlying search/query primitive used where an
exact-existence lookup was needed. The recurrence on the young surface IS the cluster signal; the
shared primitive is what binds the distinct findings.

- `fix_framing`: `null` (framings differ across iterations; this axis does not need a shared one)
- `root_class`: `wrong-primitive-for-existence-check`

**Signal fired:** root-cluster via the cross-iteration same-surface recurrence axis (doctrine
`## Cross-Iteration Same-Surface Recurrence`). Gate A holds — three distinct iterations re-emit on
the same surface, framing- and line-independent. Gate B holds — the surface is young
(introduced this initiative), so it escalates to zoom-out rather than to a bounded-tail
merge-advisory. The threshold on this axis is **N=2**;
three members clear it, and the shared query PRIMITIVE is part of the same-framing rationale. The within-pass severity modifier never fired — each pass was individually
quiet — which is exactly why this orthogonal axis exists.

**Closed-by-construction fix:** zoom out and CHANGE THE PRIMITIVE — replace the fuzzy/approximate
search with a ground-truth exact-key lookup (an indexed unique key or a direct keyed fetch) that
cannot return an approximate match. Per the `### Closed-by-Construction Acceptance Test`, this
NAMES AN ELIMINATED CLASS: with the search no longer the existence oracle, fuzzy/boundary/case-fold
matching findings cannot exist, so the cluster CLOSES. Contrast the complete-the-known-set non-fix:
adding a case-fold normalization (or one more pagination guard) to the existing fuzzy search only
ENUMERATES the observed case — the shape stays identical and the next un-enumerated edge of the
same primitive is the next finding, leaving the cluster OPEN. Prefer **ground-truth derivation over
validating untrusted input**.
