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
spec.

| Agent           | Response                                                                  | Solution                                                            |
| --------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Claude Opus 4.7 | [`RESPONSE.md`](claude-opus-4.7-vs-gpt-5.5_quant/claude-opus-4.7/RESPONSE.md) | [`quant_solution/`](claude-opus-4.7-vs-gpt-5.5_quant/claude-opus-4.7/quant_solution) |
| GPT-5.5         | [`RESPONSE.md`](claude-opus-4.7-vs-gpt-5.5_quant/gpt-5.5/RESPONSE.md)        | [`quant_solution/`](claude-opus-4.7-vs-gpt-5.5_quant/gpt-5.5/quant_solution)         |

## Layout

```
<challenge>/
  PROMPT.md             — the shared task given to both agents
  <agent>/
    RESPONSE.md         — the agent's full reply, verbatim
    <artifacts>/        — files the agent was asked to produce
```

Challenge directories are named `<agent-a>-vs-<agent-b>_<topic>`.
