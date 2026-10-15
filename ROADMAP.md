# wolfram-nb-mode — provisional roadmap

This is a reviewable queue, not a release promise. These candidates are based
on the current `master` tree and existing contributor documentation. Convert
an item into its own scoped issue before implementation; this planning document
is not approval to change code.

## Prioritized candidates

### 1. Extract ordinary Wolfram code from `BoxData` / `RowBox` (P1)

**Evidence:** `CONTRIBUTING.md` lists BoxData parsing as an area for
contribution. In `wolfram-nb-mode.el`, `wolfram-nb--parse-cell` currently
replaces every matched BoxData body with `[Complex BoxData content]`, while the
README describes code-cell editing and evaluation.

**Acceptance criteria:** Define the supported common `RowBox` forms; add small
notebook fixtures and ERT coverage proving supported Input/Code cells produce
usable Wolfram source and survive a save/reopen cycle. Unsupported box forms
must remain distinguishable from real source rather than silently becoming a
placeholder that can be saved as content.

### 2. Define and test notebook round-trip fidelity (P1)

**Evidence:** `wolfram-nb--parse-cell` retains only `:content` and `:style`, and
`wolfram-nb--make-cell` emits new cells with only content and style. The
integration test named `integration-test-roundtrip-fidelity` should be checked
against representative notebook options before relying on the README's
bidirectional-preservation claim.

**Acceptance criteria:** Document which cell metadata/options are preserved,
normalized, or intentionally discarded. Add a checked-in fixture with
representative options and an ERT round-trip assertion for the agreed contract;
unsupported lossy cases must be documented or rejected visibly.

### 3. Make complex `CellGroupData` coverage portable and part of the suite (P2)

**Evidence:** `tests/test-cellgroupdata.el` reads
`/Users/juangonzalez/Scratch/JuanWeeklyReports.nb`, writes a fixed `/tmp` file,
and invokes its test at load time. `tests/test-all.sh` does not load that file;
its CellGroupData checks are the smaller cases in `tests/test-mode.el`.

**Acceptance criteria:** Replace the personal-file dependency with a small
sanitized fixture under the repository, express the complex case as ERT, and
run it from `tests/test-all.sh`. A clean checkout must not require a user file
or share a fixed temporary output path.

### 4. Make test results and coverage claims auditable (P2)

**Evidence:** `tests/test-all.sh` classifies the three Emacs runs by matching
captured output strings rather than preserving each process exit status. The
same script hard-codes suite counts, while `docs/TESTING.md` labels several
areas “100%” without identifying a coverage measurement.

**Acceptance criteria:** Propagate each runner's exit status, report executed
and skipped test counts from actual results, and align the testing guide with
the checks the canonical script really runs. Coverage claims should identify a
measurement method or be phrased as test inventory, not measured coverage.

## Scope notes

- Keep each implementation candidate in a separate issue/PR so parser,
  serialization, and test-infrastructure changes remain reviewable.
- No release dates or version commitments are implied.
- Wolfram evaluation remains optional where `wolframscript` is unavailable;
  report skipped or blocked runtime checks rather than calling them passed.
