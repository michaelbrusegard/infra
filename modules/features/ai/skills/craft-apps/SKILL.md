---
name: craft-apps
description: Drive the installed Craft desktop apps and Blender, headlessly or through the craft MCP gateway. Use when a task means reading, editing, converting or rendering a PDF, image, vector drawing, raw photo, video, motion graphic, page layout, audio session, document, slide deck, spreadsheet, 3D CAD part or Blender scene, or when the user names PdfCraft, PhotoCraft, VectorCraft, LightCraft, FilmCraft, EffectCraft, DesignCraft, SoundCraft, WordCraft, DeckCraft, GridCraft, SolidCraft or Blender.
---

# Craft apps

Each app has a window (`photocraft`) and a headless tool (`photocraft-cli`) that
run the same commands. Both routes below reach the same engine; pick by the
shape of the task.

## Headless

For one-shot work on files: convert, extract, render, batch.

1. Run `<app>-cli --help`. The subcommands differ per app and change between
   releases, so read them instead of assuming another app's.
2. Do the work with the tool's one-shot or script subcommand, writing to a new
   file beside the input.
3. Verify the result by reading it back with the same tool (info, text or a
   rendered PNG) before reporting it done.

## Gateway

For many calls against one open document, or edits the user wants to watch in
the app's window. The `craft` MCP server offers four tools: `craft_list_apps`,
`craft_find_tools`, `craft_describe_tool`, `craft_call_tool`.

Blender is reached the same way, as the app `blender`, and only while Blender
is open: its tools run Python inside the running program.

The user switches it on. When a tool answers that agents are turned off, or the
app needed is not listed, ask the user to run `craft-agents on` (every app) or
`craft-agents on <app>...`, then call again; it takes effect at once.
`craft-agents` alone prints the current state.
