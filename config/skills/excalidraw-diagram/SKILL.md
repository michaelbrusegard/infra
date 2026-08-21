---
name: excalidraw-diagram
description: Create or edit Excalidraw JSON diagrams that make relationships, sequence, hierarchy, ownership, or system boundaries easier to understand. Use when the user asks for an Excalidraw diagram or when a visual materially clarifies a concept that prose cannot explain as well.
---

# Excalidraw Diagram

Make the relationship visible. Do not turn a list of nouns into equal boxes.

## Choose the visual argument

State in one sentence what the viewer should understand after seeing the
diagram. Choose the smallest structure that proves it:

- flow or timeline for sequence and state changes;
- tree for hierarchy or ownership;
- fan-out or convergence for one-to-many and many-to-one relationships;
- cycle for feedback and repeated work;
- side-by-side composition for a real comparison;
- nested regions for boundaries, deployment, or responsibility.

If a short paragraph or table is clearer, do not force a diagram unless the
user explicitly requested one.

## Use concrete evidence

For technical diagrams, inspect the implementation or authoritative source
before drawing. Use real component names, commands, events, payload shapes, and
boundaries. Include a small code, data, or UI example only when it teaches
something the labels cannot.

Separate overview from detail. A complex diagram should have a readable summary
flow, clear regions, and selected evidence—not every fact at the same visual
weight.

## Compose deliberately

- Give the eye one obvious starting point and one primary direction.
- Map behavior to shape. Use decisions, branches, cycles, and boundaries only
  when the underlying concept has them.
- Default labels and annotations to free-floating text. Add a container when it
  groups, connects, or carries meaning.
- Use whitespace, scale, and type for hierarchy. Keep the palette restrained
  and use color consistently to encode meaning.
- Connect every claimed relationship with a line, arrow, overlap, or nesting.
  Proximity alone is ambiguous.
- Prefer descriptive element IDs and stable grouping. For large diagrams, build
  one coherent region at a time and check cross-region bindings as you go.

Start from valid Excalidraw JSON:

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://excalidraw.com",
  "elements": [],
  "appState": { "viewBackgroundColor": "#ffffff", "gridSize": 20 },
  "files": {}
}
```

Use readable text only in `text` and `originalText`. Keep IDs unique, opacity at
100, and bindings internally consistent. Use clean edges for technical diagrams
unless the user asks for a rough hand-drawn treatment.

## Render and correct

Validate the JSON, render it with available Excalidraw or browser tooling, and
inspect the result. Fix clipped text, overlaps, unclear labels, crossed arrows,
bad endpoints, uneven spacing, weak hierarchy, unreadable detail, and lopsided
composition. Repeat until the exported view is clear at its intended size.

If rendering is unavailable, validate the structure and say that visual
inspection was not completed.
