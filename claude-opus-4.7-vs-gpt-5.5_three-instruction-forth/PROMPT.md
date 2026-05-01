# Three-Instruction Forth Implementation

Implement a **standalone, pure-assembly Forth** whose entire runtime is built from just three primitive instructions: `!` (store), `@` (fetch), and `CALL`. This is Frank Sergeant's "pathological minimum" concept — the fewest operations needed to bootstrap a complete Forth system on bare metal, because with store, fetch, and call you can build everything else.

## Background

Frank Sergeant demonstrated that a Forth for an embedded target needs only three instructions communicated over a serial link:

1. **`!` (store)**: Write a byte to a target address
2. **`@` (fetch)**: Read a byte from a target address
3. **`CALL` (call)**: Jump to a subroutine at a target address

Everything else — dictionary, compiler, interpreter, control structures — can be built on the host side, driving the target purely through these three primitives. The original 68HC11 implementation was 66 bytes.

Your task is to implement this concept as a **self-hosted, pure-assembly Forth** running on **macOS arm64 (Apple Silicon)**. The three instructions `!`, `@`, and `CALL` are the *only* primitives written in assembly; all other Forth words must be defined in terms of these three (or in terms of words that are ultimately defined in terms of these three).

## Architecture

**Target**: macOS arm64 (Apple Silicon). Mach-O binary produced from assembly source (use `as` — the system assembler in `/usr/bin/as` — and `ld` — the system linker in `/usr/bin/ld`).

**Threading model**: Direct-threaded or indirect-threaded — your choice, but the implementation must be in pure assembly (ARM64 assembly syntax accepted by the macOS system assembler) with a minimal runtime that boots directly into the Forth interpreter.

**Memory model**:
- Data stack growing downward
- Return stack growing downward (may share or be separate from the data stack — your choice, but document which)
- Dictionary growing upward from a fixed base address
- Allocate reasonable sizes (e.g., 64 KiB data stack, 64 KiB return stack, 128 KiB dictionary space)

**Boot sequence**: The system starts executing, initializes stacks and the dictionary pointer, then enters the outer interpreter (interpreter loop that reads a word, finds it in the dictionary, and executes it).

## Required Deliverables

Create a directory `forth_solution/` containing:

### 1. `boot.s` — The assembly kernel

This file contains **only** the three primitive implementations plus the absolute minimum glue to get the interpreter loop running:

- **`!` (STORE)**: Pop address and value from the data stack; write the value (cell-sized, 8 bytes on arm64) to the address.
- **`@` (FETCH)**: Pop address from the data stack; read the cell-sized value at that address and push it.
- **`CALL`**: This is the inner interpreter / NEXT dispatch. In a threaded Forth, every colon definition's execution jumps through the code field to the next word. `CALL` (often called `docolon`, `ENTER`, or `nest`) is what makes a word call another word — it pushes the current instruction pointer onto the return stack and sets the instruction pointer to the body of the word being called. Combined with `EXIT` (which pops the return stack back), this gives you subroutine threading.

Additionally, `boot.s` may contain:
- A minimal `EXIT` word (return from colon definition — pop return stack to instruction pointer). This is the counterpart to `CALL` and can be considered part of the same primitive pair.
- Stack pointer initialization
- The outer interpreter loop (READ, FIND, EXECUTE) — this *must* be written as Forth words defined in terms of the primitives, not as inline assembly beyond what's strictly needed to read a character and write a character. You may implement two additional I/O primitives in assembly: one word that reads a character from stdin (`KEY`), and one that writes a character to stdout (`EMIT`). These are the only additional assembly primitives allowed.
- A `BYE` word that exits cleanly. On macOS arm64, use `svc #0x80` with the appropriate syscall numbers, or call `exit()` via the system call convention (`mov x16, #1; mov x0, #0; svc #0x80`).

The total assembly in `boot.s` should be minimal. Aim for the spirit of the 66-byte original. This is a hard constraint on philosophy, not a byte count — the system should feel like it has the absolute fewest assembly primitives needed, with everything else built in Forth.

### 2. `core.f` — Forth source built on the primitives

This file defines all standard Forth words in terms of `!`, `@`, `CALL`, `KEY`, and `EMIT`. At minimum, implement:

**Stack operations**: `DUP`, `DROP`, `SWAP`, `OVER`, `NIP`, `TUCK`, `ROT`, `?DUP`, `DEPTH`

**Arithmetic**: `+`, `-`, `*`, `/`, `MOD`, `/MOD`, `1+`, `1-`, `2*`, `2/`, `ABS`, `NEGATE`, `MIN`, `MAX`, `AND`, `OR`, `XOR`, `INVERT`, `LSHIFT`, `RSHIFT`

**Comparison**: `=`, `<>`, `<`, `>`, `<=`, `>=`, `0=`, `0<`, `0>`, `0<>`

**Memory**: `C!`, `C@`, `+!`, `CELLS`, `CHARS`, `ALLOT`, `,` (comma)

**String**: `TYPE`, `."`, `S"`, `COUNT`, `-TRAILING`

**Dictionary**: `:`, `;`, `CREATE`, `DOES>`, `VARIABLE`, `CONSTANT`, `FIND`, `'` (tick), `IMMEDIATE`, `HIDDEN`

**Control flow**: `IF ... ELSE ... THEN`, `BEGIN ... UNTIL`, `BEGIN ... WHILE ... REPEAT`, `DO ... LOOP`, `EXIT`, `RECURSE`

**Interpreter**: `INTERPRET`, `WORD`, `NUMBER?`, `>NUMBER`, `STATE`, `HERE`, `LATEST`, `HEADER`

**I/O**: `.`, `CR`, `SPACE`, `SPACES`, `DUMP`, `WORDS`

**System**: `ABORT`, `QUIT`, `DEPTH`, `.S`

Each word must be defined in Forth (colon definitions using the three primitives + `KEY`/`EMIT`), not in assembly. The only assembly in the entire system is what's in `boot.s`.

### 3. `test.f` — Test suite

A comprehensive test file that can be loaded and executed by your Forth system. Tests must cover:

- **Stack operations**: Verify each stack word leaves the correct state
- **Arithmetic**: Known-answer tests for all arithmetic operations, including edge cases (division by zero handling, overflow)
- **Comparison**: All comparison operators on boundary values (max, min, zero, negative)
- **Memory**: Write/read round-trip, byte vs cell operations
- **Control flow**: Nested conditionals, multiple loop types, early exit, recursion
- **Dictionary**: Define words, find them, test immediate words, test `DOES>`
- **String I/O**: Output verification
- **Interpreter**: Number parsing, word lookup, error handling

The test file should print `PASS` or `FAIL` for each test and print a summary at the end.

### 4. `Makefile` — Build system

A Makefile that:
- Assembles `boot.s` into a Mach-O binary using the macOS system `as` and `ld`
- Provides a `run` target that builds and runs the Forth system, piping `core.f` then `test.f` as input
- Provides a `test` target that runs the test suite and checks the exit code

Note: the assembly source should be named `boot.s` (the macOS `as` convention for ARM64 assembly files).

### 5. `README.md` — Documentation

A brief README explaining:
- The threading model used and why
- How the three primitives map to the ARM64 implementation
- Which words are implemented in assembly vs Forth
- How to build and run
- Known limitations or deviations from ANS Forth

## Constraints

- **Pure assembly**: Only `boot.s` may contain ARM64 machine code. All other logic must be Forth.
- **Five assembly primitives maximum**: `!`, `@`, `CALL`/`EXIT`, `KEY`, `EMIT`. Plus `BYE` to exit. No cheating by adding more assembly primitives to avoid hard Forth problems.
- **Self-hosting**: The system must be able to read `core.f` and `test.f` from stdin and execute them. No preprocessing, no external build tools beyond the macOS system `as` and `ld`.
- **No C runtime**: No libc, no framework linkage. Raw Mach-O binary, starting from the entry point. On macOS arm64 you can use Unix system calls directly via `svc #0x80` with the syscall number in `x16` and arguments in `x0`–`x5`. Alternatively you may link against libSystem for `read`/`write`/`exit` only — but no other library calls.
- **macOS arm64**: Target is Apple Silicon (AArch64 Darwin). Syscall convention: syscall number in `x16`, arguments in `x0`–`x5`, return value in `x0`, syscall instruction is `svc #0x80`. Key syscall numbers: `exit` = 1, `read` = 3, `write` = 4.
- **Cell size**: 64-bit cells (matching the native word size).

## Philosophical Notes

Frank Sergeant's 3-instruction Forth is not about minimalism for minimalism's sake. It demonstrates that the vast complexity of a development environment can be offloaded to the host, and that the target needs only the thinnest bridge to memory and execution. Your implementation should embody this philosophy:

- The assembly kernel should be as small as possible — every instruction must justify its existence.
- The Forth-level code should be clear and read like documentation of the system's architecture.
- Prefer simple, understandable implementations over clever, dense ones.
- The system should feel like it could be bootstrapped on a new architecture by rewriting only the ~5 assembly primitives.

## Scoring Rubric (for evaluator)

| Criterion | Weight |
|-----------|--------|
| Boot correctness (system starts, interpreter works, can define words) | 25% |
| Core word completeness (all required words implemented, pass tests) | 30% |
| Purity and minimalism (assembly kernel is truly minimal, Forth-level words are built on primitives) | 20% |
| Code quality (clarity, structure, naming, documentation) | 15% |
| Test coverage (breadth and depth of test suite) | 10% |

## Submission

Return the complete contents of all five files. Do not omit helper definitions or glue code.