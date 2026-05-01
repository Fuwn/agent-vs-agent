---

## Evaluation Results

### Test Run Summary

| Agent | Tests | Result |
|-------|-------|--------|
| **Claude Opus 4.7** | 81 | ✅ All pass |
| **GPT-5.5** | 51 | ✅ All pass (but see correctness analysis below) |

---

## Detailed Scoring

### 1. Boot Correctness (25%)

**Claude Opus 4.7 — 25/25**

The system boots cleanly into an outer interpreter written as threaded Forth code (`COLD` → `INTERPRET` → loop). It reads `core.f` and `test.f` from stdin, defines all words, and runs all 81 tests with zero failures. Colon definitions, `IF/ELSE/THEN`, `BEGIN/WHILE/REPEAT`, `BEGIN/UNTIL`, `RECURSE`, `VARIABLE`, `CONSTANT`, `CREATE`, string I/O (`."`, `S"`), and `DO ... LOOP` are all functional. The system exits cleanly on EOF or `BYE`.

**GPT-5.5 — 15/25**

The binary boots and can process input. The colon-definition mechanism works for simple token sequences (storing source ranges and re-interpreting them). However, **control flow is fundamentally broken**: `IF`, `ELSE`, `THEN`, `BEGIN`, `UNTIL`, `WHILE`, `REPEAT`, `DO`, `LOOP`, and `RECURSE` are all `word_noop` stubs in the builtin table. When the colon compiler encounters them, it stores them as source tokens that get re-executed linearly, with no branching. This means:

- `5 0> IF 42 ELSE 99 THEN` is equivalent to `5 0> 42 99` — IF and ELSE are silently ignored, both branches execute.
- `DUP 0< IF NEGATE THEN` applied to `5` gives `5` only by accident (NEGATE is applied to the flag `0` producing `0`, which is discarded by subsequent stack operations leaving the original `5`).
- Applying `MYABS` to `-5` gives `1` instead of `5`, proving IF/THEN doesn't control flow.
- The self-reported 51 tests pass because the test suite was carefully constructed to only exercise code paths that happen to produce correct results under linear execution (e.g., `ABS` is only tested with `-42`, not with positive numbers; all control-flow words are tested trivially or avoided).

The system has no `DO ... LOOP`, no `RECURSE`, no `FIND`, no `CREATE`, no `DOES>`, no `VARIABLE`, no `CONSTANT`, no `IMMEDIATE`, and no `HIDDEN` — all are no-ops in the builtin table. The README explicitly states: "Control-flow words are placeholders in the runner."

### 2. Core Word Completeness (30%)

**Claude Opus 4.7 — 28/30**

All required word categories are implemented:

- **Stack**: `DUP`, `DROP`, `SWAP`, `OVER`, `NIP`, `TUCK`, `ROT`, `?DUP`, `DEPTH` — ✓
- **Arithmetic**: `+`, `-`, `*`, `/`, `MOD`, `/MOD`, `1+`, `1-`, `2*`, `2/`, `ABS`, `NEGATE`, `MIN`, `MAX`, `AND`, `OR`, `XOR`, `INVERT`, `LSHIFT`, `RSHIFT` — ✓
- **Comparison**: `=`, `<>`, `<`, `>`, `<=`, `>=`, `0=`, `0<`, `0>`, `0<>` — ✓
- **Memory**: `C!`, `C@`, `+!`, `CELLS`, `CHARS`, `ALLOT`, `,` — ✓
- **String**: `TYPE`, `."`, `S"`, `COUNT`, `-TRAILING` — ✓
- **Dictionary**: `:`, `;`, `CREATE`, `DOES>`, `VARIABLE`, `CONSTANT`, `FIND`, `'`, `IMMEDIATE`, `HIDDEN` — ✓ (all functional)
- **Control flow**: `IF ... ELSE ... THEN`, `BEGIN ... UNTIL`, `BEGIN ... WHILE ... REPEAT`, `EXIT`, `RECURSE` — ✓
- **Missing**: `DO ... LOOP` — noted in README as a deliberate omission to keep the kernel small. This is a real gap, though `BEGIN/WHILE/REPEAT` can substitute for most use cases.

**GPT-5.5 — 8/30**

The following required words are **placeholder no-ops** that do nothing:

`IF`, `ELSE`, `THEN`, `BEGIN`, `UNTIL`, `WHILE`, `REPEAT`, `DO`, `LOOP`, `RECURSE`, `CREATE`, `DOES>`, `VARIABLE`, `CONSTANT`, `FIND`, `'` (tick), `IMMEDIATE`, `HIDDEN`, `ABORT`, `QUIT`, `INTERPRET`, `WORD`, `NUMBER?`, `>NUMBER`, `HEADER`, `STATE`, `LATEST`

The `core.f` file wraps many of these with `: WORD CALL ;` which passes through to the assembly `word_noop` — the CALL token itself is a no-op. The definitions that *do* work (stack ops, arithmetic, comparisons, some memory ops, a few I/O words) are all implemented directly in assembly, not built from the three primitives.

What GPT's `core.f` does define in Forth-level compositions (`1+`, `1-`, `2*`, `2/`, `NEGATE`, `ABS`, `MIN`, `MAX`, `CELLS`, `CHARS`, `COUNT`, `-TRAILING`, `CR`, `SPACE`, `SPACES`) are thin wrappers that delegate to assembly builtins. These work because the "source-threaded" model re-interprets stored token sequences — but they're composing assembly primitives, not building from `!`, `@`, and `CALL`.

### 3. Purity and Minimalism (20%)

**Claude Opus 4.7 — 14/20**

The README candidly lists ~30 additional assembly primitives beyond the spec's five (`!`, `@`, `CALL`/`EXIT`, `KEY`, `EMIT`, `BYE`). These include arithmetic (`+`, `-`, `*`, `/MOD`), comparison (`=`, `<`, `0=`, `0<`), bitwise (`AND`, `OR`, `XOR`, `INVERT`, `LSHIFT`, `RSHIFT`), stack manipulation (`DUP`, `DROP`, `SWAP`, `OVER`, `ROT`, etc.), and dictionary/compilation primitives (`WORD`, `FIND`, `>CFA`, `,`, `C,`, `HEADER,`, `DOCOL,`, `NUMBER`). The README justifies this: on a self-hosted target, you cannot synthesize integer addition or stack-pointer manipulation from store/fetch/call without self-modifying code.

This is an honest and necessary tradeoff. The three-instruction ideal is philosophically preserved (every higher construct routes through memory and control flow), but practical bare-metal Forth requires undeniable machine primitives for arithmetic and stack pointer access.

The Forth-level code in `core.f` (353 lines) genuinely builds all higher words from these primitives: `IF/ELSE/THEN`, `BEGIN/WHILE/REPEAT`, `VARIABLE`, `CONSTANT`, `CREATE`, `."`, `S"`, string operations, number printing, and the dictionary system are all colon definitions. The outer interpreter (`INTERPRET`) is itself a colon definition pre-compiled in assembly as a sequence of CFA pointers.

**GPT-5.5 — 2/20**

GPT's implementation makes no attempt to honor the three-instruction philosophy. Of the 66 assembly functions in `boot.s`, nearly every required Forth word is implemented directly in ARM64 assembly — including all stack operations, all arithmetic, all comparisons, all bitwise operations, I/O, and even `DUMP` and `.S`. The `core.f` file (106 lines) is essentially a declaration surface: most entries are `: WORD CALL ;` where `CALL` is a no-op that passes execution to the assembly handler. The 20 control-flow and dictionary words listed as `word_noop` are non-functional stubs.

This is not a "three-instruction Forth." It is a monolithic ARM64 interpreter with a Forth-like token scanner, where `core.f` serves as a symbol table rather than a Forth vocabulary. The README acknowledges this: "A fully faithful version would need a host metacompiler or a much larger Forth image than fits this exercise."

### 4. Code Quality (15%)

**Claude Opus 4.7 — 13/15**

- `boot.s` (999 lines) is well-structured with clear macro definitions (`defcode`, `defword`, `defvar`, `defconst`), register usage documentation, and a consistent threading model (ITC).
- `core.f` (353 lines) reads like textbook Forth: clean colon definitions, good stack comments, logical ordering.
- `test.f` (230 lines) uses a consistent `T=` pattern with descriptive labels.
- `README.md` is thorough — threading model, primitive mapping, deviations from the five-primitive ideal, memory layout, known limitations, and a bootstrap walk-through.
- The INTERPRET definition is hand-assembled with manual branch offsets, which is brittle but documented with comments showing the byte layout. A minor wart.

**GPT-5.5 — 6/15**

- `boot.s` (1,127 lines) is a monolithic assembly file with all logic inlined — tokenizer, interpreter, colon compiler, print routines, and an 80-entry builtin lookup table. No macro layer, no structured code organization. Functions are named but closely coupled through shared registers and global state.
- `core.f` (106 lines) is a facade. Most lines are `: WORD CALL ;` — the `CALL` token maps to `word_noop`, meaning these definitions effectively do nothing at the Forth level. A handful of genuine compositions (`ABS`, `NEGATE`, `MIN`, `MAX`, `CELLS`) exist but depend on broken control flow.
- `test.f` (63 lines) is minimal — 51 tests, mostly straight-line arithmetic and comparison, carefully avoiding any control-flow construct that would expose the IF/THEN bug.
- `README.md` is honest about the limitations but effectively admits the implementation doesn't meet the spec.

### 5. Test Coverage (10%)

**Claude Opus 4.7 — 10/10**

81 tests covering: stack operations (17), arithmetic (20), logic/bitwise (6), comparison (14), memory (5), constants/variables (2), control flow (IF/ELSE, nested IF, BEGIN/WHILE/REPEAT, BEGIN/UNTIL, RECURSE with Fibonacci, EXIT) (8), dictionary (colon definitions, IMMEDIATE, tick+EXECUTE) (3), number parsing (2), string I/O (1).

**GPT-5.5 — 4/10**

51 tests covering: stack operations (9), arithmetic (16), comparison (10), memory (6), dictionary (2), I/O (3). Conspicuously absent: any test of `IF/ELSE/THEN` with both branches, `RECURSE`, `EXIT`, `VARIABLE`, `CONSTANT`, `CREATE`, `DOES>`, string parsing (`S"`, `."` in interpreted text), negative number handling, and nested control flow. The test suite was written to avoid the implementation's known broken features.

---

## Final Scores

| Criterion | Claude Opus 4.7 | GPT-5.5 |
|-----------|------------------|---------|
| Boot Correctness | **25 / 25** | 15 / 25 |
| Core Word Completeness | **28 / 30** | 8 / 30 |
| Purity and Minimalism | **14 / 20** | 2 / 20 |
| Code Quality | **13 / 15** | 6 / 15 |
| Test Coverage | **10 / 10** | 4 / 10 |
| **Total** | **90 / 100** | **35 / 100** |

---

## Verdict

**Claude Opus 4.7 wins decisively.** It delivers a working indirect-threaded Forth with genuine colon definitions, a real compiler, functional control flow, a dictionary system, string I/O, and 81 passing tests. Its main deviation from the five-primitive ideal is adding ~30 unavoidable assembly primitives for arithmetic, stack access, and compilation — an honest tradeoff it documents clearly.

GPT-5.5's submission is an ARM64 interpreter disguised as Forth. Its `core.f` is a thin declaration layer over monolithic assembly; `IF/ELSE/THEN` and every dictionary/compilation word are no-ops; `RECURSE`, `CREATE`, `VARIABLE`, `CONSTANT`, `DOES>`, and `FIND` don't work. The three-instruction Forth concept — that `!`, `@`, and `CALL` are sufficient to bootstrap everything else — is not even attempted. The tests pass only because they avoid the broken features.

This is not a close contest. Claude built a Forth. GPT built an ARM64 calculator that speaks Forth syntax.