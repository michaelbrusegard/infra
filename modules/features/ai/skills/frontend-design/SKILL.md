---
name: frontend-design
description: Design and implement distinctive, production-ready frontend interfaces grounded in the product and its users. Use when building a new UI, substantially redesigning an existing one, or when a frontend needs a clear visual direction rather than generic component-library defaults.
---

# Frontend Design

Make deliberate choices from the product context. Do not decorate a generic
layout and call it a design.

## Establish the direction

1. Read the brief, existing product, design system, and nearby UI before making
   choices. Preserve established patterns unless the task is explicitly a
   redesign.
2. Identify the user, the page's main job, the content hierarchy, and the one
   feeling the interface should convey.
3. Choose a coherent direction for type, color, spacing, density, layout, and
   motion. Name one signature idea that belongs to this product and justify it.
4. Define a small token system before implementation. Reuse project tokens when
   they exist; otherwise keep new values centralized and internally consistent.

Spend the visual emphasis in one place. Everything else should make that choice
clearer.

## Build the interface

- Use the repository's framework, components, and conventions. Do not replace
  working foundations just to express the design.
- Let structure communicate priority. Use size, position, whitespace, and type
  before adding containers, borders, or decoration.
- Use real or representative content. Empty marketing language and fake metrics
  make even good layouts feel templated.
- Write interface copy from the user's point of view with plain verbs and
  consistent action names.
- Make mobile, keyboard navigation, focus states, contrast, loading, empty,
  error, and reduced-motion behavior part of the design.
- Add motion only when it explains hierarchy, state, or causality. Prefer one
  composed moment over unrelated effects.

## Avoid defaults without a reason

Question card grids, centered hero stacks, gradient text, glow effects, excessive
rounded pills, interchangeable dashboard tiles, generic geometric backgrounds,
and the same neutral sans-serif everywhere. Any of them can be correct, but none
is a direction by itself.

Do not invent a second visual system inside an established product. Distinction
can come from composition, typography, content, or interaction without fighting
the rest of the application.

## Verify visually

Run the existing checks, then inspect the actual interface at representative
desktop and mobile sizes. Use screenshots or browser tooling when available.
Fix clipping, overflow, weak hierarchy, inconsistent spacing, illegible type,
missing focus states, contrast problems, and motion that ignores user settings.
Do not claim visual verification when no rendered interface was inspected.
