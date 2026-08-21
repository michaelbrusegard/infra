---
name: write-agent-instructions
description: Write documents consumed by agents, including skills, AGENTS.md, CLAUDE.md, and referenced instruction files. Use when creating, revising, pruning, or restructuring durable agent guidance.
---

# Write agent instructions

Use the same writing discipline for every document an agent consumes. The
packaging changes, but the goal does not. Make the agent follow the same process
reliably, not produce identical prose.

When writing a skill, also read
[SKILL-MECHANICS.md](SKILL-MECHANICS.md) for invocation and router decisions.

## Context pointers

A **context pointer** is text already in the agent's context that names
out-of-context material and states when to open it. A skill description is a
pointer. A line in `AGENTS.md` pointing to another document is the same object.

The pointer's wording decides whether the target is reached. A required document
behind a weak pointer is a variance bug. Sharpen the pointer before inlining the
whole target.

A pointer must state what the material is and name each distinct branch that
should trigger it. Every word in an always-loaded pointer costs attention on
every turn:

- Front-load the leading trigger word.
- Keep one trigger per real branch. Collapse synonyms that name the same case.
- Remove identity already carried by the target document.

## The two loads

- **Context load** is always-loaded text that spends tokens and attention on
  every turn.
- **Cognitive load** is the set of documents the person must remember and when
  to invoke them. It is the cost of retaining human agency, not something to
  minimize blindly.

Material reached only through a pointer avoids most context load at the cost of
the pointer. Material with no pointer relies entirely on cognitive load.

## Information hierarchy

Agent documents contain **steps** and **reference**. Put each piece on the
lowest rung that still makes it reliably available:

1. **In-file step.** An ordered action needed on every path.
2. **In-file reference.** Rules or definitions consulted within the workflow.
3. **Disclosed reference.** A separate file opened through a context pointer
   only on the branches that need it.

Progressive disclosure protects the hierarchy. Inline what every branch needs
and disclose branch-specific reference. Too much inline reference buries the
steps. Too much disclosure hides material the workflow always needs.

Within a file, co-locate a concept's definition, rules, and caveats. Scattering
one meaning across headings makes the agent reconstruct it. Sprawl is different:
even unique and relevant material becomes unreliable when the document is too
long. Split by branch or sequence when that reduces the path each run carries.

## Steps and completion criteria

Every step ends on a completion criterion. It needs both:

- **Clarity.** The agent can tell done from not done. Sharpen a vague boundary
  before hiding later steps. If the boundary is irreducibly fuzzy and later
  steps pull the agent toward premature completion, split the sequence across a
  real context boundary.
- **Demand.** The criterion requires the necessary legwork. "Every modified
  model accounted for" is stronger than "produce a change list".

Prefer criteria that are checkable and exhaustive.

## Leading words

A **leading word** is a compact concept the model already knows and can use to
anchor behavior, such as a `tight` debugging loop or a `red` test. Repeat the
word, not its definition, after defining it once. It can drive execution inside
the document and invocation from a pointer.

Refactor repeated phrases into an accurate leading word when one exists. A
made-up word recruits no prior understanding and must earn the definition cost.

Phrase the positive target. Negation makes the prohibited behavior more
available. Keep a prohibition only for a hard boundary that cannot be stated
positively, and pair it with the intended action.

## Pruning

- Keep each meaning in one authoritative place. Repeating a definition raises
  its apparent importance and creates maintenance drift.
- Treat the environment as a source of truth. Files, scripts, config, layout,
  and `--help` output should not be cached in prose unless the lookup is costly
  or the missing fact is the reason behind the setup.
- Remove stale, irrelevant, and branch-specific sediment.
- Delete no-op instructions that do not change model behavior. Test disputed
  defaults empirically rather than editing by taste.
- Put a repeated mechanical invariant in a test, lint rule, script, schema, or
  hook instead of prose.

## Apply the reference

1. Read the current instruction files completely and identify the observed
   failure or repeated request each proposed change addresses.
2. Choose the smallest durable scope: current prompt, repository `AGENTS.md`,
   nested instructions, global guidance, skill, or deterministic mechanism.
3. Build the pointer and hierarchy before polishing sentences.
4. Give every workflow step a completion criterion.
5. Validate paths, commands, frontmatter, and supporting assets.
6. Prune duplication, caches, no-ops, stale facts, weak negation, and prose a
   mechanism should enforce.
7. Run the available skill validator and any focused fixture or script tests.
