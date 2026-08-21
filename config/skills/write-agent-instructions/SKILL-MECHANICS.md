# Skill mechanics

This is the skill-specific branch of `write-agent-instructions`. The main skill
owns the writing rules. This file owns invocation, frontmatter, and router
decisions.

## Invocation

A model-invoked skill has a description the agent can discover. Other skills
may also route to it. Its description is always-loaded context, so write it as a
sharp context pointer that carries the real trigger branches.

A user-invoked skill is reached only when the person names it. Where the harness
supports an explicit user-only frontmatter flag, use it and make the description
human-facing. This removes context load but makes the person the index.

Choose model invocation only when the agent must discover the skill itself or
another skill must route to it. Choose user invocation when human judgment
should decide whether it runs.

## Split by invocation

Split a model-invoked skill only when it has a distinct leading word that should
trigger independently or several workflows need to route to its reference. The
new always-loaded description must earn its cost.

## Router skills

When user-invoked skills become hard to remember, add one user-invoked router
that names them and says when the person should reach for each. A router hints.
It cannot automatically fire a skill that the harness exposes only to the user.

## Portability

Use frontmatter fields supported by every target harness. Put harness-specific
metadata in a documented adapter only when it is required. Do not add generated
interface metadata that the user does not use.
