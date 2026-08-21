# ADR format

ADRs live in `docs/adr/` and use sequential names such as
`0001-event-sourced-orders.md`. Create the directory lazily and increment the
highest existing number.

## Template

```md
# {Short decision title}

{One to three sentences stating the context, decision, and reason.}
```

That is enough for most decisions. Add optional status, considered options, or
consequences only when they provide information the paragraph cannot.

## When to offer an ADR

All three conditions must hold:

1. The decision is hard to reverse.
2. A future reader would find it surprising without context.
3. Real alternatives existed and the choice involved a tradeoff.

Good ADR subjects include architectural shape, integration between contexts,
technology choices with meaningful lock-in, ownership boundaries, deliberate
deviations from the obvious design, constraints invisible in code, and
non-obvious rejected alternatives.
