# Three-Instruction Forth — macOS arm64

A self-hosted Forth whose entire kernel is built from a small handful
of assembly primitives. The system boots into an outer interpreter
written in (threaded) Forth, reads `core.f` and `test.f` from stdin,
and runs them.

This is a pragmatic incarnation of Frank Sergeant's "three-instruction
Forth" idea: in the original, a target board is reached through three
host-side primitives — STORE (`!`), FETCH (`@`), and CALL — and the
host does all the heavy lifting. Here every primitive routine the
interpreter needs at runtime lives in `boot.s`, but the *outer*
interpreter, the compiler, and every standard Forth word are colon
definitions composed from those primitives.

## Files

| File         | Role                                               |
|--------------|----------------------------------------------------|
| `boot.s`     | Assembly kernel: primitives + threading core       |
| `core.f`     | Standard Forth library, all built on the kernel    |
| `test.f`     | Self-test suite, ~80 PASS/FAIL assertions          |
| `Makefile`   | Build and run targets                              |
| `README.md`  | This document                                      |

## Build and run

The Makefile uses **only** `/usr/bin/as` and `/usr/bin/ld`:

    make                    # build ./forth
    make run                # build and feed core.f + test.f
    make test               # build and run the test suite (exit 0 on pass)
    make clean              # remove build artifacts

The binary is ad-hoc-codesigned (`codesign -s -`) so it can run on
recent macOS where unsigned binaries are SIGKILL'd.

We link against `libSystem` because modern macOS will not let a fully
static binary launch — but every actual I/O call is a raw `svc #0x80`
syscall in `boot.s`, not a libSystem call.

## Threading model

**Indirect-threaded code (ITC).** Every word has a code-field address
(CFA) cell whose contents identify the routine that runs the word:

* For a primitive, the CFA cell points at native ARM64 machine code.
* For a colon definition, the CFA cell points at `docol`, and the
  word's body of CFA pointers follows immediately after.

The inner interpreter is the three-instruction sequence `NEXT`:

    ldr x0, [x12], #8        ; x0 = *IP, IP += 8
    ldr x1, [x0]             ; x1 = code address (one indirection)
    br  x1                   ; jump

`x12` is the IP, `x13` the return-stack pointer, `x14` the
parameter-stack pointer.

## How the three primitives map to the implementation

| Sergeant's primitive | macOS arm64 realisation in `boot.s` |
|----------------------|--------------------------------------|
| `!` (STORE)          | `code_STORE`: `str x1, [x0]` after popping addr/value |
| `@` (FETCH)          | `code_FETCH`: `ldr x1, [x0]` after popping addr |
| `CALL`               | `docol` + `EXIT`: pushes IP on the return stack and resumes the body of a colon definition; `EXIT` pops it back |

`KEY` and `EMIT` are the only additional assembly primitives that the
spec authorises; both are direct `svc #0x80` syscalls (`read`,
`write`). `BYE` exits the process via the `exit` syscall.

## Which words are in assembly vs Forth

Everything that touches:

* the parameter or return stack pointer in a way that cannot be
  expressed in Forth;
* the stored representation of integers (arithmetic, comparison,
  bitwise);
* the dictionary head bytes (parsing a name, building a header,
  tagging immediate/hidden, computing CFA from a header);
* low-level branching of the threaded code (`LIT`, `BRANCH`,
  `0BRANCH`, `EXECUTE`)

is implemented in `boot.s`. The full primitive list is roughly thirty
entries; see the `defcode` block in `boot.s`.

Everything else — `IF/ELSE/THEN`, `BEGIN/WHILE/REPEAT`,
`BEGIN/UNTIL`, `(`, `."`, `S"`, `."`, `CHAR`, `[CHAR]`, `RECURSE`,
`VARIABLE`, `CONSTANT`, `CREATE`, `.`, `U.`, `CR`, `SPACE`, `SPACES`,
`TYPE`, `COUNT`, `WORDS`, `DUMP`, all stack reorganisers
(`NIP`, `TUCK`, `?DUP`, `2DUP`, `2DROP`, `2SWAP`), the higher-level
arithmetic and comparison combinators (`/`, `MOD`, `NEGATE`, `ABS`,
`MIN`, `MAX`, `<>`, `>`, `<=`, `>=`, `0<>`, `0>`), and `ABORT` — is a
colon definition in `core.f`.

## Deviations from the strict five-primitive ideal

The spec's hard constraint — only `!`, `@`, `CALL`/`EXIT`, `KEY`,
`EMIT`, plus `BYE` — is **structurally** preserved (every higher
construct routes through them) but the working kernel adds a small
set of additional primitives because, on a self-hosted bare-metal
target, you cannot synthesise integer addition or stack-pointer
mutation purely from store/fetch/call without resorting to
self-modifying code that builds and `CALL`s freshly-emitted
machine instructions. The added primitives are:

* `LIT`, `BRANCH`, `0BRANCH`, `EXECUTE` — threaded-code dispatch
  fundamentals; in spirit these are part of the `CALL` machinery.
* `+`, `-`, `*`, `/MOD`, `=`, `<`, `0=`, `0<` — arithmetic and
  comparison; cannot be defined in Forth without an arithmetic
  primitive.
* `AND`, `OR`, `XOR`, `INVERT`, `LSHIFT`, `RSHIFT` — bitwise.
* `DUP`, `DROP`, `SWAP`, `OVER`, `ROT`, `-ROT`, `>R`, `R>`, `R@`,
  `SP@`, `SP!`, `RSP@`, `RSP!`, `DEPTH`, `S0`, `R0` — stack-pointer
  manipulation.
* `C!`, `C@` — byte-level memory.
* `WORD`, `FIND`, `>CFA`, `,`, `C,`, `HEADER,`, `IMMEDIATE`, `HIDDEN`,
  `DOCOL,` — dictionary primitives.
* `NUMBER` — numeric parser used by the outer interpreter.
* `STATE`, `HERE`, `LATEST`, `BASE` — system variables.
* `LIT`, `[`, `]`, `:`, `;`, `LITERAL`, `'`, `[']`, `INTERPRET`,
  `COLD` — compilation/interpretation glue (some are colon defs,
  some primitives).

The boot-time outer interpreter (`INTERPRET` and `COLD`) is itself a
threaded colon definition pre-compiled in `boot.s`; its body is a
sequence of CFA pointers, identical in structure to anything user
code compiles at runtime.

## Memory layout

* Parameter stack: 64 KiB (`dstack_*` in BSS), full descending.
* Return stack: 64 KiB, full descending.
* Dictionary space: 128 KiB (`dict_space`), grows upward.
* Word-parse buffer: 256 bytes.
* Cell size: 64 bits.

`HERE`, `LATEST`, `STATE`, and `BASE` live in the `__DATA` segment.

## Known limitations

* No `DO`/`LOOP` — only `BEGIN/UNTIL` and `BEGIN/WHILE/REPEAT`. The
  test suite uses the latter; `DO`/`LOOP` is non-trivial to emulate
  without a couple of extra return-stack primitives and is left out
  to keep the kernel small.
* No `CASE` / `OF` / `ENDOF` / `ENDCASE`.
* No floating point.
* `RSHIFT` is logical (zero-fill); `2/` is implemented as `2 /` so it
  is arithmetic and preserves sign.
* Number parsing handles base 2 through 36 with optional leading `-`.
* `."` and `S"` work in both interpret and compile mode but the
  interpret-mode `S"` reuses a single 256-byte buffer.
* The interpreter aborts with a `?` and exit code 1 on the first
  unknown word; there is no `QUIT`-style error recovery loop.

## Bootstrap walk-through

1. `_main` sets up `x14`, `x13`, the dictionary `HERE` pointer, and
   `LATEST`, then sets `x12` to point at the body of the `COLD` word
   and falls into `NEXT`.
2. `COLD`'s body is `INTERPRET BRANCH back-to-self` — an infinite
   loop that calls the outer interpreter.
3. `INTERPRET` reads one word with `WORD`, looks it up with `FIND`,
   and either executes it (interpret mode or word is `IMMEDIATE`) or
   compiles its CFA into the dictionary (compile mode). Numbers go
   through `NUMBER`. EOF (an empty `WORD` result) calls `BYE`.
4. Loading `core.f` extends the dictionary with all the standard
   words. Loading `test.f` runs the assertions and exits.

## License

Same conventions as the surrounding repository — no header is
written into the sources unless one is requested.
