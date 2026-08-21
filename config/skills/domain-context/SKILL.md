---
name: domain-context
description: Build and sharpen a project's domain model. Use when discussing codebase terminology, creating or editing CONTEXT.md, resolving domain boundaries, or recording an architectural decision.
---

# Domain context

Actively sharpen the domain model while designing. Challenge terms, invent
edge-case scenarios, and write down vocabulary and durable decisions when they
become clear. Merely reading an existing `CONTEXT.md` is a normal preparation
step, not this skill.

## File structure

Most repositories have one context:

```text
/
├── CONTEXT.md
├── docs/adr/
└── src/
```

If `CONTEXT-MAP.md` exists at the root, it names multiple contexts and points to
each context's `CONTEXT.md`. System-wide decisions live under the root
`docs/adr/`; context-specific decisions live beside that context.

Create files lazily. Create `CONTEXT.md` when the first term is resolved and an
ADR directory only when the first qualifying ADR is needed.

## During the session

### Challenge the glossary

When a user's term conflicts with `CONTEXT.md`, surface the conflict immediately
and ask which meaning is correct.

### Sharpen fuzzy language

When a term is vague or overloaded, propose a precise canonical term. Separate
concepts that the existing language has collapsed.

### Discuss concrete scenarios

Stress-test relationships with specific normal and edge-case scenarios. Use the
scenario to force precision about ownership, lifecycle, and boundaries.

### Cross-reference code

Check claims against schemas, types, APIs, state machines, tests, and enforcement
points. Surface contradictions instead of deciding silently whether prose or
code wins.

### Update `CONTEXT.md` inline

Capture a resolved term when it becomes clear rather than batching glossary work
at the end. Follow [CONTEXT-FORMAT.md](CONTEXT-FORMAT.md).

`CONTEXT.md` is a glossary. Keep implementation details, specifications,
scratch notes, and implementation decisions out of it.

### Offer ADRs sparingly

Offer an ADR only when the decision is all three:

1. hard to reverse;
2. surprising without context;
3. the result of a real tradeoff.

If any condition is missing, skip the ADR. Follow
[ADR-FORMAT.md](ADR-FORMAT.md).
