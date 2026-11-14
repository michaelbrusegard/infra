# LLM conversations: one canonical format

Status: proposal with a tested prototype. Nothing here is deployed, and no
existing table changes.

All LLM history currently sits in two raw shapes: the proxy archive
(`llm.requests`, `llm.request_items`, `llm.usage`) since 2026-11-09, and a
one-off dump of agent session logs (`llm.transcripts`) from 2026-06-10 to
2026-11-09. This proposes one canonical format for both. It serves two uses:
learning from my own LLM use (prompts, how agents worked, tools, models, costs,
failures), and exporting conversations as chat or SFT data with tool calls and
results.

The rule that shapes everything: **the canonical form must be lossless**. Every
source record must be recoverable from it, so the source tables could be
dropped later without losing anything.

## Recommendation in short

- Four tables, `llm.sessions`, `llm.messages`, `llm.calls` and `llm.events`,
  plus the existing content-addressed `llm.request_items` as the store for all
  raw JSON.
- Messages form a **tree per session**. A node's ID covers its parent, so the
  context a proxy request resends every turn maps onto existing nodes. Codex's
  delta requests (`previous_response_id`) chain onto the previous response.
  Compaction starts a new root, and retries or edits branch.
- Proxy nodes are keyed by **content, ignoring transport noise**, so a model's
  output and its resent copy are one node. Without this, Claude Code's moving
  `cache_control` markers split the tree at 50 of 52 turns in a live session.
- Every message and event references its **exact source JSON** by hash, and
  proxy calls keep the request envelope, parts and response body verbatim. The
  extracted columns are a queryable view and never the only copy, so an
  extractor bug cannot lose data.
- **Session IDs follow CLIProxy's scheme** (`claude:<id>`,
  `claude:<id>:agent:<agent>`, `codex:<thread>`, …), and transcripts are
  mapped into it too. A session captured by both sources then has a single ID,
  and the proxy owns its messages.
- A **normalizer job** derives the canonical rows from the raw capture. The
  plugin keeps writing the raw capture unchanged. Normalizing in the plugin is
  rejected for now (see [Ongoing capture](#ongoing-capture)).

## What the data looks like

Profiled read-only on 2026-11-14.

| Table               | Rows  | On disk  | Uncompressed |
| ------------------- | ----- | -------- | ------------ |
| `llm.requests`      | 60.7k | 689 MiB  | 8.8 GiB      |
| `llm.request_items` | 218k  | 1.55 GiB | 2.5 GiB      |
| `llm.transcripts`   | 2.2M  | 3.06 GiB | 9.2 GiB      |
| `llm.usage`         | 60.7k | 24 MiB   | 100 MiB      |

The proxy writes about 420 MiB a day to disk (290 MiB of items, 130 MiB of
responses). The PVC is 75 GiB.

### Proxy requests

- **`claude`** (21.4k requests, 227 sessions): almost all from Claude Code,
  via the T3 Code agent SDK. `system`, `tools` and `messages` are split into
  items. Message blocks are `tool_use`, `tool_result`, `thinking`, `text`,
  images in user and tool results (1,796 items), and `server_tool_use`. Claude
  Code also sends `role: system` messages inside `messages`. Each request
  resends the whole conversation, but **Claude Code moves `cache_control`
  markers and switches content between a string and a text-block array between
  turns**, so the same message is often stored as two items. One header session
  holds the main thread, its sub-agents (up to 98 distinct first messages in a
  session), title generation and compaction calls. The agent ID is not in the
  request: CLIProxy's `llm.usage.session_id` has it
  (`claude:<sid>:agent:<agent>`) and is 1:1 with the request by `trace_id` for
  Claude.
- **`openai-response`** (38.2k): Codex through T3 Code, Codex Desktop,
  `codex_exec`, plus scripts. **None has a `session_id`**; the thread is in
  `prompt_cache_key` and `client_metadata` (`session_id` is the root thread,
  `thread_id` the current one, and `x-codex-turn-metadata.agent_name` names
  sub-agents, for example `/root/design_review`). **About 74% of requests are
  websocket deltas**: `previous_response_id` plus only the new input items.
  The conversation exists only as a chain through earlier requests and
  responses. Responses are SSE, or JSON lines for websocket streams, and
  `response.created`, `in_progress` and `completed` each echo the full
  instructions and tools (about 36 KiB per event). Warm-up requests
  (`generate: false`, empty input) produce no output but start chains. 47
  bodies hit the 32 MiB limit and are stored whole as invalid JSON.
- **`openai`** chat completions (1.1k): hindsight (567, sessionless memory
  calls), OpenCode (429, with a header session), pi (105, sessionless).
  CLIProxy derives `lcp:v1:<hash>` sessions in `llm.usage` for sessionless
  calls.
- Usage links by `trace_id`, not `request_id`, whose namespaces differ. A
  websocket trace carries many requests, so the link is unambiguous only when
  the trace has one usage session.
- Item bytes are dominated by **base64 images: 1.8 of 2.5 GiB**. Only 2,884 of
  4,599 data-URL images are distinct.

### Transcripts

| Source      | Lines | Notes |
| ----------- | ----- | ----- |
| codex       | 1.33M | Linear rollouts. `response_item` (messages, reasoning, tool calls and outputs) is the conversation. `event_msg` duplicates much of it (`item_completed` is 1.15 GiB). `token_usage_record` or `token_count` gives usage, `turn_context` the model, `compacted` carries the `replacement_history` that becomes the new context, and `session_meta.source.subagent.thread_spawn` links sub-agents. |
| claude-code | 0.52M | A tree by `uuid` and `parentUuid`. Assistant replies are one line per streamed block, grouped by `requestId`. `attachment` lines hold `rendered` context the model saw (environment, reminders, CLAUDE.md, as `system` or `user`). A `compact_boundary` system line starts a new root (`logicalParentUuid` keeps the link), and `isCompactSummary` marks the summary. Since 2026-10-26 Claude Code also logs its own content-addressed API requests (`api-request`, `api-request-blob`, `api-request-shape`). The 126k lines without timestamps are metadata such as `last-prompt`, `ai-title`, `mode` and request blobs. Sub-agents and workflow agents are separate files under `<session>/subagents/`. |
| pi          | 0.31M | A tree by `id` and `parentId`. Messages are `user`, `assistant` (with `responseId`, `usage`, `model`), `toolResult` (`isError`) and `system`. `compaction` entries carry a summary. |
| opencode    | 58k   | Exported from SQLite. Older sessions store `message` and `part` records separately (`text`, `reasoning`, `tool` with call and result state, `file`, step markers); newer ones inline the content. |

Only 3,714 transcript lines fall after the proxy started; six Claude Code
sessions and a handful of Codex and Pi sessions appear in both.

## Schema

The DDL is in
[`normalize-conversations/schema.sql`](../packages/cliproxy-plugins/normalize-conversations/schema.sql).

**`llm.sessions`**: one row per session and origin. It holds `session_id`,
`parent_session_id`, `client` (claude-code, codex, pi, opencode, hindsight,
other), `origin` (proxy or transcript), `host`, `path`, `title` and `cwd`.
Start and end times are aggregates over messages and calls, so they never need
updating.

**`llm.messages`**: one row per node of a session's conversation tree.

| Column | Meaning |
| --- | --- |
| `session_id`, `id`, `parent_id`, `seq` | Tree position. `parent_id = 0` at a root; `seq` is the depth. |
| `ts` | When the message was first seen: the transcript time, or the proxy call's start (inputs) or completion (outputs). |
| `role` | `system`, `developer`, `user`, `assistant` or `tool`. A message made only of tool results is `tool` in every dialect. |
| `output`, `model`, `call_id` | Whether a model produced it, which model, and in which call. Inputs name the call that first sent them. |
| `blocks` | `Array(Tuple(type, source_type, text, tool_name, tool_call_id, tool_input, is_error, media))`. `type` is one of text, thinking, tool_call, tool_result, image, file, compaction, other; `source_type` keeps the dialect's own name. Image and file data, signatures and encrypted reasoning are not copied here. |
| `format`, `item`, `line` | The raw dialect (anthropic, openai-responses, openai-chat, claude-code, codex, pi, opencode), the hash of the exact source JSON in `llm.request_items`, and the transcript line. |

**`llm.calls`**: one row per model call. It holds the call and session,
`trace_id` (joins `llm.usage`), `response_id`, times, origin, client, model,
`input_id` (the last input message; its ancestors are the rest of the context)
and `output_ids`. Token counts are split the way `llm.usage_metrics` splits
them: uncached input, cache read, cache write, output and reasoning. Proxy
calls also keep every `llm.requests` column verbatim, including
`request_envelope`, `request_parts` and `response_body`.

**`llm.events`**: every transcript line that is not a message, such as token
counts, turn settings, titles, queue operations, Claude Code's request logs and
OpenCode part records. Each row has a session, time, line, type and item hash.

**`llm.request_items`** stays as is and becomes the store for all raw JSON:
proxy items, assembled response messages, and transcript lines. Renaming it is
cosmetic and not proposed.

## Identity and deduplication

`id = sha256(parent_id ‖ key)[:16]`, and roots derive from the session ID. The
key is:

- **Proxy messages**: the message's content, normalized. Anthropic and chat
  messages are keyed by role and content (plus tool calls for chat), with
  `cache_control` and `logprobs` removed and string content treated as one
  text block. Responses items drop `id` and `status`. A response's assembled
  message keys the same as the copy the client sends back, so they are one
  node. The node keeps the first bytes seen, normally the response's, with
  ID, model and usage. Every call's own bytes stay in its `request_parts`.
  On a live sample (two Claude Code sessions, 50 turns), 50 of 50 resent
  prefixes and 50 of 50 replies matched; without normalization the tree
  forked at 50 turns.
- **Transcript messages**: the source's own entry ID (uuid, Pi ID, OpenCode
  message ID, Codex line). Codex compaction items use `line#index`.

Because IDs are deterministic, rerunning the normalizer over the same input
produces the same rows. All tables are `ReplacingMergeTree`, so reruns and
overlapping batches collapse. Raw items deduplicate by content hash, as they
do today.

## Building conversations from the proxy

Requests are processed in start order, with a little state per session.

1. **Session.** Use `llm.usage.session_id` when the trace has exactly one
   session, which covers every Claude call and tells sub-agents apart.
   Otherwise derive the same form: Codex from `client_metadata` (`codex:<root>`
   or `codex:<root>:agent:<name>`), then the header session, then
   `proxy:<hash of first message>` for anything sessionless.
2. **Context.** With `previous_response_id`, start from the leaf after that
   response; otherwise start at the root. Then append each `messages` or
   `input` item as a node. Full-resend clients walk their existing nodes and
   add only the new tail. `system`, `instructions` and `tools` are per-call
   context: they stay in the call's parts and are not tree nodes, so a changed
   system prompt (Claude Code puts the date and git status in it) does not
   duplicate the conversation.
3. **Outputs.** Assemble the response into messages: Anthropic SSE into the
   final message, Responses into the `output_item.done` items (interrupted
   items from their deltas), chat chunks into one assistant message. Append
   them under the input leaf, and remember the response ID's leaf for the next
   delta request.
4. **Gaps.** A `previous_response_id` that was never archived starts at a
   `missing_context` marker root rather than guessing.

Compaction needs no special case. After Claude Code or Codex compacts, the
request starts with the summary or `compaction` item, so the conversation gets
a new root in the same session; Codex delta chains continue through it. The
old branch stays intact.

Sessionless chat calls (hindsight, pi) group by their first message. All
hindsight calls share one system prompt, so they become one session with a
branch per call, which is accurate.

Truncated bodies keep their single raw part and have no messages.

## Transcripts

Each file is normalized on its own, and **every line becomes exactly one
message or event that references the line verbatim**. The session ID is mapped
into CLIProxy's scheme: `claude:<session>`, `claude:<parent>:agent:<agent>`,
`codex:<thread>`, `codex:<parent>:agent:<agent path>`, `pi:<session>` and
`opencode:<session>`.

- **claude-code**: `user` and `assistant` lines, and attachments with rendered
  content, become messages. The parent is the nearest message ancestor, so
  attachments and system lines in the chain are skipped. A compaction boundary
  starts a new root, and the summary's blocks are `compaction`. Assistant
  lines group into one call by `requestId`, with the last line's usage.
  `ai-title` sets the title.
- **codex**: `response_item` lines are messages chained in file order.
  Assistant items between two inputs form one call, and its usage comes from
  the next `token_usage_record`, or `token_count` in older logs. The model
  comes from `turn_context`. A `compacted` line is kept as an event, and its
  `replacement_history` items become a new root chain.
- **pi**: `message` entries are messages, and `compaction` and
  `branch_summary` become user messages with a `compaction` block. Each
  assistant message is one call.
- **opencode**: messages are ordered by time. Older part records attach their
  content to the message and are also kept as `part` events, so the raw lines
  stay one-to-one.

### Overlap with the proxy

**One owner per session.** If the proxy captured a session, its transcript
lines are kept only as events and produce no messages or calls. Nothing is
counted twice, and nothing is dropped.

The alternative is a handover at the first proxied call. It would keep
per-message transcript timestamps for the pre-proxy part of about 15
sessions, but it needs fuzzy matching between transcript lines and API
messages (Claude Code splits replies per block), for little gain. Usage
already uses a fixed handover; `llm.historical_usage` stays the dashboard's
source for history.

## Losslessness

| Source | Where it survives |
| --- | --- |
| `llm.requests` row | `llm.calls`, every column verbatim. `request_envelope` plus `request_parts` rebuild the body exactly as `llm.request_bodies` does. |
| request item | `llm.request_items`, unchanged and referenced from calls. |
| response body | `llm.calls.response_body`, verbatim. Assembled outputs are added as items. |
| `llm.transcripts` row | One message or event whose item is the exact line. `line` is the row's `id`; the session row holds `source`, `host` and `path`. The file-name `session` column is derivable from `path`. |
| `llm.usage`, `llm.historical_usage` | Unchanged. They feed Grafana, and `llm.calls` links to usage by `trace_id`. |

The prototype tests this both ways:

- Calls rebuild every request body (by JSON value) and every response body
  (by byte).
- Every transcript line is referenced exactly once with identical bytes, in Go
  and again in ClickHouse via `SHA256(line)`.
- Every content string in a raw item (text, thinking, arguments, tool input
  and output, summaries, rendered attachments) appears in an extracted block,
  and every extracted string comes from the raw item. Deliberately breaking an
  extractor fails the tests.

What canonical rows do not try to model, but keep verbatim, includes stream
chunk boundaries, rate-limit and timing events, and Claude Code's own request
logs.

## Ongoing capture

**Recommended: the plugin keeps writing the raw capture, and a normalizer job
derives the canonical rows.**

- Codex delta requests need the previous response's output. The plugin sees
  it, but loses it on restart. A job can always read it back from ClickHouse.
- The capture stays the lossless log. When the extraction improves, or a
  client changes its format, the canonical rows can be rebuilt from it. If the
  plugin wrote only canonical rows, an extractor bug would lose data for good.
- The plugin stays small and off the critical path. Assembling streams and
  walking trees per request is work it should not do while proxying.

The job runs the same Go package as a CronJob, for example every 10 minutes.
It reads requests in the window `[watermark, now() - 2 min)` with
[`requests.sql`](../packages/cliproxy-plugins/normalize-conversations/requests.sql)
and inserts the rows. Its state is the node index and the response-to-leaf map
for open sessions, rebuilt each run from `llm.messages` and `llm.calls` for the
sessions in the window. The watermark is `max(started_at)` in `llm.calls`;
deterministic IDs make reruns harmless. It needs a ClickHouse user with SELECT
on the sources and INSERT on the new tables. The transcripts run once, after
the proxy backfill, with
[`transcripts.sql`](../packages/cliproxy-plugins/normalize-conversations/transcripts.sql)
and the proxy's sessions as `-proxied`.

`llm.calls` holds every `llm.requests` column, so once the job has run
cleanly for a while, `llm.requests` can become staging with a short TTL, such
as 14 days. Rebuilds then read `llm.calls` and the items. Until then both are
kept, at about 130 MiB a day extra.

## Sizes

Estimates are from the profiling above and live samples (73 requests, and
1,194 transcript lines from 12 files across all four sources). Loaded into
ClickHouse, the sample's `llm.messages` compressed 4.1x.

| Part | On disk |
| --- | --- |
| Proxy messages: rows plus extracted text, about 10% of item bytes because images dominate, about 250 MiB uncompressed so far | ~70 MiB, then ~12 MiB a day |
| Transcript messages: extracted text is about half of message-line bytes, and message lines are about 75% of all lines | ~0.9 GiB |
| Transcript lines moved into `llm.request_items`, at today's 2.9x ratio | ~3 GiB |
| `llm.calls`, the same columns as `llm.requests` | 689 MiB, then ~130 MiB a day |

- **End state**, with `llm.transcripts` dropped and `llm.requests` reduced to
  short-lived staging: about 6.5 GiB, against 5.4 GiB now.
- **Migration peak**, with both copies: about 10 GiB.
- **Growth**: about 430 MiB a day once requests are staging, or 560 MiB if
  `llm.requests` is also kept forever, because calls copy it. About 69 GiB of
  the 75 GiB volume is free, which lasts four to five months, so storage needs
  a decision either way.

### Optional optimizations

Not proposed now.

- **Content-address images.** About 40% of image bytes repeat across messages,
  so moving data URLs into their own items would save around 100 MiB a day.
  Items would then no longer be verbatim message bytes, and rebuilding them
  needs a substitution step.
- **Compact response streams.** Drop delta events whose final item reproduces
  them, and `instructions` and `tools` echoes that equal the request's. That
  would cut most of the 130 MiB a day of responses, but chunk boundaries would
  be lost, and they are information, if not much.

## Queries

```sql
-- example: prompts
-- What I asked in the last week. Injected context (<system-reminder>,
-- <environment_context>, AGENTS.md) is also user-role text; skipping text
-- that starts with a tag is a heuristic.
SELECT ts, session_id, b.text AS prompt
FROM llm.messages FINAL
ARRAY JOIN blocks AS b
WHERE role = 'user' AND b.type = 'text' AND NOT startsWith(b.text, '<')
    AND ts >= now() - INTERVAL 7 DAY
ORDER BY ts DESC
LIMIT 100
```

```sql
-- example: tool-failures
-- Tool use and failures per model and tool. Anthropic, Pi, and OpenCode
-- results carry an error flag; Codex reports exit codes in the output text.
WITH
    tool_calls AS (
        SELECT session_id, b.tool_call_id AS id, b.tool_name AS tool, model
        FROM llm.messages FINAL ARRAY JOIN blocks AS b
        WHERE output AND b.type = 'tool_call'),
    results AS (
        SELECT session_id, b.tool_call_id AS id, max(b.is_error) AS failed
        FROM llm.messages FINAL ARRAY JOIN blocks AS b
        WHERE b.type = 'tool_result'
        GROUP BY session_id, id)
SELECT model, tool, count() AS uses, countIf(failed) AS failures
FROM tool_calls INNER JOIN results USING (session_id, id)
GROUP BY model, tool
ORDER BY failures DESC, uses DESC
LIMIT 50
```

```sql
-- example: tokens
-- Calls and tokens per day, client, and model. Costs: join proxy calls to
-- llm.usage_metrics on trace_id, as the dashboard prices them.
SELECT toDate(started_at) AS day, client, model, count() AS calls,
    sum(uncached_input_tokens + cache_read_tokens + cache_write_tokens) AS input_tokens,
    sum(output_tokens) AS output_tokens
FROM llm.calls FINAL
GROUP BY day, client, model
ORDER BY day, input_tokens DESC
```

```sql
-- example: conversation
-- A session's conversation, root to its latest message. For the exact
-- context and reply of one call, start from its last output_ids instead.
WITH RECURSIVE path AS (
    SELECT id, parent_id, seq, role, output, model, blocks
    FROM llm.messages FINAL
    WHERE session_id = {session:String}
        AND id = (SELECT argMax(id, (ts, seq)) FROM llm.messages FINAL WHERE session_id = {session:String})
    UNION ALL
    SELECT m.id, m.parent_id, m.seq, m.role, m.output, m.model, m.blocks
    FROM llm.messages AS m FINAL
    INNER JOIN path AS p ON m.id = p.parent_id
    WHERE m.session_id = {session:String}
)
SELECT seq, role, output, model, blocks FROM path ORDER BY seq
FORMAT JSONEachRow
```

Pipe that into `normalize-conversations -export openai` (or `anthropic`) for
training data. It merges consecutive assistant items into one turn, pairs tool
calls with results, and puts reasoning in `reasoning_content` or `thinking`
blocks. Images are left out of the export; their data is in the raw items.

```sql
-- example: raw
-- The exact source JSON behind each message: images, signatures, encrypted
-- reasoning, and anything else the blocks leave out.
SELECT m.seq, m.role, i.item
FROM llm.messages AS m FINAL
INNER JOIN llm.request_items AS i ON i.hash = m.item
WHERE m.session_id = {session:String}
ORDER BY m.seq
LIMIT 1 BY m.id
```

```sql
-- example: subagents
-- Sub-agent sessions under their parents, with their size.
SELECT s.parent_session_id AS parent, s.session_id AS agent, count() AS messages
FROM llm.sessions AS s FINAL
INNER JOIN llm.messages AS m FINAL ON m.session_id = s.session_id
WHERE s.parent_session_id != ''
GROUP BY parent, agent
ORDER BY parent, agent
```

## Trade-offs considered

- **Full raw versus residual `extra`.** Storing each message's raw JSON costs
  the extracted text twice. Storing only the fields not extracted would avoid
  that, but reconstruction would then depend on the extractor being right.
  For proxy messages the raw item already exists, so full raw costs nothing
  extra there. **Recommended: full raw.**
- **Tree versus one linear thread per session.** Retries, compaction,
  sub-agents in one header session, and Codex delta chains all branch, so a
  linear list would have to pick one branch and drop or duplicate the rest. A
  tree costs one recursive query to read a conversation, and with the
  content-keyed nodes, live sessions came out linear anyway.
- **Blocks inline versus a separate table.** Inline arrays keep one row per
  message and need `ARRAY JOIN` for block-level queries. A blocks table
  would need joins for nearly everything.
- **System prompt and tools as nodes versus per-call context.** As nodes, they
  would fork the tree whenever the date or git status in the prompt changes.
  They stay in the call's parts.

## Prototype

- [`packages/cliproxy-plugins/conversations`](../packages/cliproxy-plugins/conversations):
  dialect extraction (`blocks.go`), proxy request and response assembly
  (`proxy.go`), transcripts (`transcripts.go`), and the exporters
  (`export.go`). The tests use hand-written, redacted fixtures in the shapes
  profiled from live data, covering every source format.
- [`packages/cliproxy-plugins/normalize-conversations`](../packages/cliproxy-plugins/normalize-conversations):
  the CLI the job would run, the DDL, and the input queries.
- [`gitops/espresso/tests/llm-conversations.py`](../gitops/espresso/tests/llm-conversations.py):
  loads the fixtures into a real ClickHouse running the deployed schema, then
  normalizes them through the input queries and CLI. It checks the lossless
  round trips and that Grafana permissions are unchanged, and runs every
  example above.

```sh
cd packages/cliproxy-plugins && go test ./...
nix develop --command python3 gitops/espresso/tests/llm-conversations.py < /dev/null
```

## Open questions

1. **Staging TTL for `llm.requests`.** `llm.calls` holds the same columns,
   so keeping both forever costs about 130 MiB a day. Recommended: a 14-day
   TTL once the job has run cleanly for a few weeks. Or keep both forever?
2. **Storage.** At about 430 MiB a day, the free space lasts four to five
   months. Grow the PVC, content-address images (about −100 MiB a day),
   compact response streams, or accept it and revisit?
3. **Typed prompts.** The proxy cannot tell text I typed from injected
   context. Should the plugin record more of the client's request headers,
   such as Claude Code's agent ID and prompt markers, so this does not depend
   on `llm.usage` and heuristics?
4. **Claude Code's own request logs** (`api-request*`, about 110k lines) are
   kept as events. Are they worth mapping to calls for the transcript era?
   They would give exact system prompts and tools from before the proxy.
5. **Backfill order.** Run the transcripts once, then the proxy from
   2026-11-09, then the job. Is a one-off run from a workstation over a
   port-forward acceptable, as for the usage backfill?
