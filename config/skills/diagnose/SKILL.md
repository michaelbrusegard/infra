---
name: diagnose
description: Run a disciplined diagnosis loop for hard bugs, deployed incidents, and performance regressions. Use when the user asks to diagnose, debug, investigate, explain a failure, or determine why something is broken, failing, throwing, or slow.
---

# Diagnose

Build a red-capable feedback loop before forming a theory. Skip a phase only
with an explicit reason. A request to diagnose is read-only unless the user also
asks for a fix.

Read `CONTEXT.md` and relevant ADRs when they exist.

## Redact

Commands, outputs, and captured artifacts may contain credentials, auth
headers, private URLs, or user data. Replace secrets with `<REDACTED>`, keep
credentials in environment variables, and quote only the lines that carry the
signal. Ask the user when redaction removes evidence required for diagnosis.

## Phase 1: build the feedback loop

This is the skill. A tight pass/fail signal turns bisection, instrumentation,
and hypothesis testing into mechanical work. Without one, reading more code
only makes an untested story sound better.

Construct the loop at the narrowest faithful seam, roughly in this order:

1. A failing unit, integration, or end-to-end test.
2. A curl or HTTP script against a development server.
3. A CLI invocation with fixture input and expected output.
4. A headless-browser script that asserts on the DOM, console, or network.
5. A replay of a redacted request, payload, trace, or event log.
6. A throwaway harness around the smallest real subsystem.
7. A property or fuzz loop for intermittent wrong output.
8. A bisection harness suitable for `git bisect run`.
9. A differential loop comparing working and failing versions or configs.
10. A structured human-in-the-loop script when a manual action is unavoidable.

Tighten the loop until it is:

- **Red-capable.** It asserts on the user's exact symptom, not merely a nearby
  crash or a command's exit status.
- **Deterministic.** The same input gives the same verdict. For flaky bugs,
  raise and pin the reproduction rate with repetition, concurrency, stress, or
  controlled timing.
- **Fast.** Prefer seconds to minutes by caching setup and skipping unrelated
  initialization.
- **Agent-runnable.** One command runs unattended, except for a structured
  human checkpoint when no other route exists.

Phase 1 is complete only after running that command once and recording its
redacted invocation and output. If no loop can be built, stop. List what was
tried and request the missing environment access, a redacted artifact, or
permission for temporary instrumentation. Do not continue into speculation.

## Phase 2: reproduce and minimize

Run the loop and confirm it catches the same failure the user reported. Repeat
it enough to establish a stable verdict. Then remove inputs, callers, config,
data, and steps one at a time. Re-run after every cut.

This phase is complete when every remaining element is load-bearing. Removing
any one makes the loop green.

## Phase 3: hypothesize

Generate three to five ranked, falsifiable hypotheses before testing any of
them. State each as a prediction:

> If X is the cause, changing Y will make the bug disappear or changing Z will
> make it worse.

Discard any hypothesis that cannot predict an observable result. Show the list
to the user before testing because their domain knowledge may re-rank it, but
continue with the evidence-backed ranking if they are unavailable.

## Phase 4: instrument

Map every probe to one prediction and change one variable at a time. Prefer:

1. debugger or REPL inspection;
2. targeted logs at boundaries that distinguish hypotheses;
3. never logging everything and grepping afterward.

Tag temporary logging with a unique prefix such as `[DEBUG-a4f2]` so one search
can remove it. For performance regressions, establish a baseline with a timing
harness, profiler, or query plan, then bisect. Measure first.

## Phase 5: confirm, then fix only when authorized

For diagnosis-only work, confirm the root cause by satisfying the winning
hypothesis's prediction, re-running the original loop, and ruling out the
closest alternatives. Report the smallest plausible fix direction and stop.

When the user also asked for a fix, find the correct regression-test seam. It
must exercise the real bug pattern as it appears at the call site. A shallow
test that cannot reproduce the chain gives false confidence. If no correct seam
exists, document that architectural gap.

When a correct seam exists:

1. Turn the minimized reproduction into a failing test.
2. Watch it fail for the expected reason.
3. Apply the smallest fix.
4. Watch the regression test pass.
5. Re-run the original, unminimized feedback loop.

## Phase 6: clean up and report

Before declaring the work done:

- re-run the original reproduction;
- run the regression test when a fix was authorized;
- remove every tagged debug statement;
- remove throwaway artifacts or put explicitly retained ones in a clear debug
  location;
- state the confirmed hypothesis and decisive evidence.

Separate observed facts, root cause and confidence, ruled-out hypotheses,
remaining gaps, likely blast radius, and the verification result. Do not call a
correlation the root cause.
