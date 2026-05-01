# Agent vs Agent

Head-to-head coding challenges between frontier models. Each challenge gives
both agents the same prompt and stores their full response plus the artifacts
they produced, so the runs stay reproducible and comparable.

## Challenges

### `claude-opus-4.7-vs-gpt-5.5_quant`

Equity option pricing and risk analytics in Python (`numpy` only): a
Black-Scholes closed-form pricer, a Monte Carlo pricer (European + arithmetic
Asian), analytical Greeks, an implied-vol solver (Newton-Raphson with
bisection fallback), and parametric portfolio VaR — plus a test suite covering
correctness, convergence, edge cases, and a throughput benchmark.

See [`PROMPT.md`](claude-opus-4.7-vs-gpt-5.5_quant/PROMPT.md) for the full
spec and [`VERDICT.md`](claude-opus-4.7-vs-gpt-5.5_quant/VERDICT.md) for the
scored evaluation.

| Agent           | Response                                                                  | Solution                                                            | Score |
| --------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------- | ----- |
| Claude Opus 4.7 | [`RESPONSE.md`](claude-opus-4.7-vs-gpt-5.5_quant/claude-opus-4.7/RESPONSE.md) | [`quant_solution/`](claude-opus-4.7-vs-gpt-5.5_quant/claude-opus-4.7/quant_solution) | **94 / 100** |
| GPT-5.5         | [`RESPONSE.md`](claude-opus-4.7-vs-gpt-5.5_quant/gpt-5.5/RESPONSE.md)        | [`quant_solution/`](claude-opus-4.7-vs-gpt-5.5_quant/gpt-5.5/quant_solution)         | 82 / 100 |

Run with Claude Code `2.1.120`, Codex CLI `0.124.0-alpha.3`. Rated by
Kimi K2.6 via Pi `0.67.68`.

### `claude-opus-4.7-vs-gpt-5.5_three-instruction-forth`

Pure-assembly Forth on macOS arm64, built from Frank Sergeant's "3-instruction Forth" concept (`!`, `@`, `CALL`): an indirect-threaded Forth kernel in `boot.s`, a Forth-level standard library in `core.f`, a test suite in `test.f`, a Makefile, and a README — all targeting Apple Silicon with no libc beyond `read`/`write`/`exit`.

See [`PROMPT.md`](claude-opus-4.7-vs-gpt-5.5_three-instruction-forth/PROMPT.md) for the full
spec and [`VERDICT.md`](claude-opus-4.7-vs-gpt-5.5_three-instruction-forth/VERDICT.md) for the
scored evaluation.

| Agent           | Response                                                                  | Solution                                                            | Score |
| --------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------- | ----- |
| Claude Opus 4.7 | — | [`forth_solution/`](claude-opus-4.7-vs-gpt-5.5_three-instruction-forth/claude-opus-4.7/forth_solution) | **90 / 100** |
| GPT-5.5         | — | [`forth_solution/`](claude-opus-4.7-vs-gpt-5.5_three-instruction-forth/gpt-5.5/forth_solution)         | 35 / 100 |

Run with Claude Code `2.1.126`, Codex CLI `0.129.0-alpha.1`. Rated by
GLM-5.1 via Pi `0.67.68`. Wall-clock: Claude Opus 4.7 in 52 m 32 s,
GPT-5.5 in ~9–10 min.

## Layout

```
<challenge>/
  PROMPT.md             — the shared task given to both agents
  VERDICT.md            — scored evaluation and final ruling
  <agent>/
    RESPONSE.md         — the agent's full reply, verbatim
    <artifacts>/        — files the agent was asked to produce
```

Challenge directories are named `<agent-a>-vs-<agent-b>_<topic>`.

## Environment

To keep runs comparable, each agent uses its vendor's own CLI with all MCP
servers and skills disabled. The only project guidance loaded is the
respective `CLAUDE.md` / `AGENTS.md`, kept equivalent across agents.

| Agent           | CLI         |
| --------------- | ----------- |
| Claude Opus 4.7 | Claude Code |
| GPT-5.5         | Codex CLI   |

Scoring is run by a third agent given both responses and the prompt's
rubric. CLI versions, reviewer, and wall-clock are listed inline with each
challenge above. The `VERDICT.md` file in each challenge is the reviewer's
output verbatim.
