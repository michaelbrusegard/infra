---
name: wizard
description: Generate an interactive bash wizard that walks a human through steps only they can perform. Use for infrastructure setup, credentials, CI secrets, third-party dashboards, or a one-off migration or cutover. Do not invoke it for steps the agent can perform.
---

# Wizard

A wizard is a bash script that walks a human through a manual procedure that is
tedious to do by hand and tedious to re-explain. It opens each URL, says what to
click and copy, captures values, writes them where they belong, confirms each
stage, and shows how much remains.

The interaction is already implemented by [template.sh](template.sh). It
provides stage progress, confirmation gates, cross-platform URL opening, hidden
secret entry, idempotent `.env` updates, GitHub secret and variable writes, and
a closing summary. Scope the procedure and author its stages. Keep the library
above the `STAGES` marker unchanged.

A wizard is ephemeral by default. Put it in a scratch location or `scripts/`
and remove it after the job. Commit it only when the user wants a repeatable
setup path in the repository.

## Process

### 1. Scope the procedure

Find every manual step and every value it produces. Read the repository before
asking questions:

- For setup, inspect `.env*`, README files, compose files, framework config,
  and CI workflows for every referenced secret and variable.
- For a migration or cutover, establish the current state, target state, and
  irreversible actions between them.

Show the ordered stages and the value each produces, then confirm the shape
with the user. This step is complete when every captured value has a source,
destination, and secret or public classification.

### 2. Map each journey

For every stage, write the path a human follows. Name the URL, page, control,
action, displayed value, and destination variable. Check current documentation
when the exact UI or command is unknown. Do not invent a path.

This step is complete when a stranger could follow every stage.

### 3. Author the wizard

Copy `template.sh` to the target path. Replace the example with one `stage` per
manual step in dependency order. Use `stage`, `say`, `step`, `open_url`, `ask`,
`ask_secret`, `write_env`, `set_secret`, `set_var`, `pause`, and `confirm`. Set
`TOTAL_STAGES` to the number of stages.

Open a URL before asking for its value. Use `ask_secret` for secrets. Persist
every value promised in step 1. Send only CI-required values to `set_secret`.
Require `confirm` immediately before irreversible, billable, public, or
production actions. Keep each stage focused because the script clears the
previous one from the terminal.

### 4. Verify and hand off

- Run `bash -n <script>` and `shellcheck <script>` when ShellCheck is available.
- Make the script executable.
- Do not run it end to end because it opens browsers and waits for a person.
  Trace every captured value to the destination established in step 1.
- Confirm each `set_secret` name matches the repository's CI reference.
- Tell the user how to run it. If it is permanent, link it from the relevant
  repository documentation.
