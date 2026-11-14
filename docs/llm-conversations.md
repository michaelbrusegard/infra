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
- Proxy nodes are keyed by **content, ignoring transport fields where the
  protocols put them**, so a model's output and its resent copy are one node.
  Without this, Claude Code's moving `cache_control` markers split the tree
  at 50 of 52 turns in a live session. A node written again keeps the row of
  the call that produced it, whatever order calls are normalized in.
- Every message and event references its **exact source JSON** by hash, and
  proxy calls keep the request envelope, parts and response body verbatim. The
  extracted columns are a queryable view and never the only copy, so an
  extractor bug cannot lose data.
- **Session IDs follow CLIProxy's scheme** (`claude:<id>`,
  `claude:<id>:agent:<agent>`, `codex:<thread>`, …), and transcripts are
  mapped into it too. A transcript whose replies the proxy returned, by
  response ID, all in one session of the same client and parent, takes that
  session, which also covers sessionless clients such as Pi. A session
  captured by both sources then has a single ID. The proxy owns it from its
  first proxied call, and the transcript keeps everything before. A reply
  that another source already holds, such as the parent's reply a forked
  sub-agent starts from, is context there and never a second call.
- A **normalizer job** derives the canonical rows from the raw capture. Each
  run picks up every request not normalized yet, however late it landed, and
  restores the state of the sessions it touches. The plugin keeps writing the
  raw capture unchanged. Normalizing in the plugin is rejected for now (see
  [Ongoing capture](#ongoing-capture)).
- **Training exports take one call**: its system prompt or instructions and
  tools, which are per-call context, plus the conversation it saw and
  produced. Responses API calls take them from the response's echo, since
  Codex often sends no tools and delta requests send neither. A call that
  produced nothing, or whose output calls tools its context lacks, is
  refused rather than exported with tools missing.

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
- The plugin writes a request when it completes. 180 requests ran longer than
  2 minutes, the longest 15 minutes, so requests land out of start order.
- Usage links by `trace_id`, not `request_id`, whose namespaces differ.
  `llm.usage` has a row per upstream attempt, and a websocket trace carries
  many requests: 1,920 traces hold 26.4k requests. They run one after
  another (none overlap), and each of their 26.4k usage rows falls inside
  exactly one request's span, never before it starts. So **an attempt
  belongs to the call in its trace whose span holds it**; a retry adds a
  second attempt to the same call. The queries allow 50 ms of clock slack,
  but only for attempts no span holds, and pick one call per attempt: with
  slack alone, an attempt at the start of a call that ends 10 ms before the
  next one starts would match both.
- Item bytes are dominated by **base64 images: 1.8 of 2.5 GiB**. Only 2,884 of
  4,599 data-URL images are distinct.

### Transcripts

| Source      | Lines | Notes |
| ----------- | ----- | ----- |
| codex       | 1.33M | Linear rollouts. `response_item` (messages, reasoning, tool calls and outputs) is the conversation. `event_msg` duplicates much of it (`item_completed` is 1.15 GiB). `token_usage_record` or `token_count` gives usage, `turn_context` the model, `compacted` carries the `replacement_history` that becomes the new context, and `session_meta.source.subagent.thread_spawn` links sub-agents. |
| claude-code | 0.52M | A tree by `uuid` and `parentUuid`. Resumed sessions write some entries again: 795 `uuid` and parent pairs repeat within a file, 574 with different bytes, such as an added `slug`. Assistant replies are one line per streamed block, grouped by `requestId`. `attachment` lines hold `rendered` context the model saw (environment, reminders, CLAUDE.md, as `system` or `user`). A `compact_boundary` system line starts a new root (`logicalParentUuid` keeps the link), and `isCompactSummary` marks the summary. Since 2026-10-26 Claude Code also logs its own content-addressed API requests (`api-request`, `api-request-blob`, `api-request-shape`). The 126k lines without timestamps are metadata such as `last-prompt`, `ai-title`, `mode` and request blobs. Sub-agents and workflow agents are separate files under `<session>/subagents/`. |
| pi          | 0.31M | A tree by `id` and `parentId`. Messages are `user`, `assistant` (with `responseId`, `usage`, `model`), `toolResult` (`isError`) and `system`. `compaction` entries carry a summary and `firstKeptEntryId` (all 409), the first entry Pi keeps sending after the summary. |
| opencode    | 58k   | Exported from SQLite. Older sessions store `message` and `part` records separately (`text`, `reasoning`, `tool` with call and result state, `file`, step markers); newer ones inline the content. |

Only 3,714 transcript lines fall after the proxy started; six Claude Code
sessions and a handful of Codex and Pi sessions appear in both.

## Schema

The DDL is in
[`normalize-conversations/schema.sql`](../packages/cliproxy-plugins/normalize-conversations/schema.sql).

**`llm.sessions`**: one row per session and source: the proxy, or each
transcript file, by `host` and `path`, since several files can continue one
session. It holds `session_id`, `parent_session_id`, `client` (claude-code,
codex, pi, opencode, hindsight, other), `origin` (proxy or transcript),
`host`, `path`, `title` and `cwd`. Start and end times are aggregates over
messages and calls, so they never need updating.

**`llm.messages`**: one row per node of a session's conversation tree.

| Column | Meaning |
| --- | --- |
| `session_id`, `id`, `parent_id`, `seq` | Tree position. `parent_id = 0` at a root; `seq` is the depth. |
| `ts` | When the message was first seen: the transcript time, or the proxy call's start (inputs) or completion (outputs). |
| `role` | `system`, `developer`, `user`, `assistant` or `tool`. A message made only of tool results is `tool` in every dialect. |
| `output`, `model`, `call_id` | Whether a model produced it, which model, and in which call. Inputs name the call that first sent them. |
| `blocks` | `Array(Tuple(type, source_type, text, tool_name, tool_namespace, tool_call_id, tool_input, is_error, media))`. `type` is one of text, thinking, tool_call, tool_result, image, file, compaction, other; `source_type` keeps the dialect's own name. `tool_namespace` is the namespace a Responses API call names, such as an MCP server's. Image and file data, signatures and encrypted reasoning are not copied here. |
| `format`, `item`, `line`, `host`, `path` | The raw dialect (anthropic, openai-responses, openai-chat, claude-code, codex, pi, opencode), the hash of the exact source JSON in `llm.request_items`, and for transcripts the line and its file's host and path. Messages built from inside a line, Codex compaction items and the context Pi sends again, have the line `<line>#<item>`. |
| `version` | Ranks the rows written for one node; `ReplacingMergeTree(version)` keeps the highest. See [Identity](#identity-and-deduplication). |

**`llm.calls`**: one row per model call. It holds the call and session,
`trace_id` (joins `llm.usage`), `response_id`, times, origin, client, model,
`input_id` (the last input message; its ancestors are the rest of the context)
and `output_ids`. Token counts are split the way `llm.usage_metrics` splits
them: uncached input, cache read, cache write, output and reasoning. Proxy
calls also keep every `llm.requests` column verbatim, including
`request_envelope`, `request_parts` and `response_body`. Three are renamed
because the canonical columns use their names: `request_id` is `call_id`,
and the header `session_id` and the archived `model` are
`source_session_id` and `source_model`. `session_id` is the canonical
session and `model` the model the response reported.

**`llm.events`**: every transcript line that is not a message, such as token
counts, turn settings, titles, queue operations, Claude Code's request logs,
OpenCode part records, repeated entries (`repeat`), and lines after the
proxy took a session over. Each row has a session, time, file (`host` and
`path`), line, type and item hash. Files that share a session, such as one
synced to two hosts, share line numbers and times, so the file is part of
the key.

**`llm.request_items`** stays as is and becomes the store for all raw JSON:
proxy items, assembled response messages, and transcript lines. Renaming it is
cosmetic and not proposed.

## Identity and deduplication

`id = sha256(parent_id ‖ key)[:16]`, and roots derive from the session ID. The
key is:

- **Proxy messages**: the message's content, normalized. Anthropic and chat
  messages are keyed by role and content (plus tool calls for chat), and
  string content is treated as one text block. Responses items drop `id` and
  `status`. `cache_control` and `logprobs` are removed only where the
  protocols put them, on content blocks and the blocks a tool result nests;
  inside a tool's input or a hosted tool's action they are content, so
  different calls stay different nodes. A response's assembled message keys
  the same as the copy the client sends back, so they are one node. The node
  keeps the response's row, with ID, model and usage. Every call's own bytes
  stay in its `request_parts`.
  On a live sample (two Claude Code sessions, 50 turns), 50 of 50 resent
  prefixes and 50 of 50 replies matched; without normalization the tree
  forked at 50 turns.
- **Transcript messages**: the source's own entry ID (uuid, Pi ID, OpenCode
  message ID, Codex line), within its file: the key includes the file's host
  and path, so files that share a session, such as one file synced to two
  hosts, never share nodes. Codex compaction items use `line#index`. An
  entry written again under the same parent is the same node: its first line
  is the message, and each repeat is a `repeat` event referencing its own
  line.

Because IDs are deterministic, rerunning the normalizer over the same input
produces the same rows. All tables are `ReplacingMergeTree`, so reruns and
overlapping batches collapse. Raw items deduplicate by content hash, as they
do today.

A proxy node can still be written more than once: a run without a session's
state, or a request that started earlier but landed later, sends it again.
Each row's `version` ranks a model's output above any copy sent back as
input, then the earliest sighting first, and `llm.messages` keeps the
highest. So the call, model and time that produced a message survive any
order of normalization, and the rows agree on everything else, because the
ID fixes the node's path.

## Building conversations from the proxy

Requests are processed in start order, with a little state per session.

1. **Session.** Use the `llm.usage` session of the call's attempts, linked by
   trace and span as above, which covers every Claude call and tells
   sub-agents apart. Otherwise derive the same form: Codex from `client_metadata` (`codex:<root>`
   or `codex:<root>:agent:<name>`), then the header session, then
   `proxy:<hash of first message>` for anything sessionless. The plugin
   writes a request when it completes, before CLIProxy writes its usage, and
   a run never revisits a normalized request, so a request without usage
   that completed within the hold is held back. Placed early, a Claude
   sub-agent's call would stay in its parent's header session for good. The
   hold runs from completion, not start: a 15-minute call would otherwise
   land already outside a 10-minute hold. On 2026-11-13, 29 of 9,167
   requests never got usage; such requests wait out the hold and then use
   the derived session.
2. **Context.** With `previous_response_id`, start from the leaf after that
   response; otherwise start at the root. Then append each `messages` or
   `input` item as a node. Full-resend clients walk their existing nodes and
   add only the new tail. `system`, `instructions` and `tools` are per-call
   context: they stay in the call's parts and are not tree nodes, so a changed
   system prompt (Claude Code puts the date and git status in it) does not
   duplicate the conversation.
3. **Outputs.** Assemble the response into messages: Anthropic SSE into the
   final message, Responses into the `output_item.done` items, chat chunks
   into one assistant message. Interrupted streams keep what streamed,
   including tool arguments whose block never stopped. Append
   them under the input leaf, and remember the response ID's leaf for the next
   delta request.
4. **Gaps.** A `previous_response_id` that was never archived starts at a
   `missing_context` marker root rather than guessing. While such a request
   is recent (10 minutes by default) the job holds it back instead, in case
   the response has not landed yet.

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
message or event that references the line verbatim**. The only thing files
share is which of them holds each reply's call, which a first pass over all
files decides (see [Overlap](#overlap-with-the-proxy)). The session ID is mapped
into CLIProxy's scheme: `claude:<session>`, `claude:<parent>:agent:<agent>`,
`codex:<thread>`, `codex:<parent>:agent:<agent path>`, `pi:<session>` and
`opencode:<session>`.

- **claude-code**: `user` and `assistant` lines, and attachments with rendered
  content, become messages. The parent is the nearest message ancestor, so
  attachments and system lines in the chain are skipped. A compaction boundary
  starts a new root, and the summary's blocks are `compaction`. Assistant
  lines group into one call by `requestId`, with the last line's usage.
  `ai-title` sets the title. Repeated entries become `repeat` events.
- **codex**: `response_item` lines are messages chained in file order.
  Assistant items between two inputs form one call, and its usage comes from
  the next `token_usage_record`, or `token_count` in older logs. The model
  comes from `turn_context`. A `compacted` line is kept as an event, and its
  `replacement_history` items become a new root chain, with lines
  `<line>#<index>`.
- **pi**: `message` entries are messages, and a `branch_summary` is a user
  message with a `compaction` block, in place. A `compaction` rebuilds what
  Pi sends from then on: the summary, then the entries from
  `firstKeptEntryId` to the compaction. The summary starts a new root, and
  copies of the kept messages follow it as context sent again, with
  `output = false` and the line `<compaction line>#<entry id>`. Later
  entries continue from the last copy, and the original branch stays as it
  was. Each assistant message is one call.
- **opencode**: messages are ordered by time. Older part records attach their
  content to the message and are also kept as `part` events, so the raw lines
  stay one-to-one.

### Overlap with the proxy

**A shared session, by reply.** Both sources record each reply's response
ID (Claude Code's message `id`, Codex's `token_usage_record`, Pi's
`responseId`), so a transcript whose replies the proxy also returned can
take the session of those proxy calls. This matters for Pi: its calls
through the proxy carry no session, so CLIProxy names them `lcp:v1:<hash>`,
which a transcript cannot derive, and in live data all three Pi sessions
that both captured shared replies (37) only by response ID. Claude Code and
Codex session IDs already agree; in live data all 236 shared Codex replies
were in the same session, and Claude Code and OpenCode transcripts end
before the proxy captured their sessions.

A reply alone does not make a session the same, though. A forked sub-agent's
file starts with a copy of its parent's history: in live data, 47 Claude Code
replies appear in more than one file, 13 in a session and its sub-agents and
34 in sibling forks. So a transcript takes the proxy's session only when
every reply the proxy returned was returned in that one session, and the
session has the transcript's client and parent session (none, or the same
one). Otherwise, or without a shared reply, the transcript keeps its own
session ID.

**Each reply is one call.** A transcript reply that the proxy returned, in
any session, is the proxy's call. Otherwise the file whose line recording
the reply is earliest holds the call, and ties go to the first by host,
path and session. A forked file copies its parent's replies after the parent
wrote them, so the parent keeps them, whatever the paths: path order is not
ancestry order in live Codex files. Sibling forks holding a reply none of
them wrote, or one file synced to two hosts, tie and fall to the first. In
every other file the reply is a copy. It stays a message in that file's
tree, because the model was sent it, but as input (`output = false`, no
model or call) like Pi's compaction copies, and it adds no call.

So a file's rows depend only on the file, the replies of all files, and the
proxy's calls. The import is one complete pass: `normalize-conversations`
reads every transcript line, records each file's replies, then normalizes
the files, in any order. Run over the same lines and proxy calls, it writes
the same rows, which collapse. Rows from different inputs or rules do not
replace each other reliably, because a wrong output row outranks the
corrected input row and a wrong call is never removed, so such a rerun goes
into tables without transcript rows: delete the transcript calls and
sessions (`origin = 'transcript'`), the messages with a `path`, and all
events first.

**A handover at the session's first proxied call.** Transcript lines from
before it become messages and calls as usual, and lines from then on are
kept only as events, because the proxy has those calls with their exact
bodies. Turns from before the proxy, and branches compacted away before it,
stay canonical messages, and no call or token is counted twice. Lines after
the handover stay as events either way, so a session that left the proxy
again would lose nothing, only the extracted view of those turns.

The proxy's first call resends the context from before it, so that context
is in both trees: as transcript nodes at their own times, and as the proxy
call's input nodes. The two are not merged, because matching transcript
lines to API messages needs fuzzy matching (Claude Code splits replies per
block) for little gain. Calls and tokens need nothing, since each call has
one owner; counting prompts or messages should dedupe by content per
session, as the prompts example does. Usage already uses a fixed handover;
`llm.historical_usage` stays the dashboard's source for history.

## Losslessness

| Source | Where it survives |
| --- | --- |
| `llm.requests` row | `llm.calls`, every column verbatim, with `request_id`, `session_id` and `model` as `call_id`, `source_session_id` and `source_model`. `request_envelope` plus `request_parts` rebuild the body exactly as `llm.request_bodies` does. |
| request item | `llm.request_items`, unchanged and referenced from calls. |
| response body | `llm.calls.response_body`, verbatim. Assembled outputs are added as items. |
| `llm.transcripts` row | One message or event whose item is the exact line, repeats included, with the row's `host`, `path` and `id` (as `line`). The file's session row, by `session_id`, `host` and `path`, holds `source` as `client`. The file-name `session` column is the path's file name without `.jsonl`, or for OpenCode, whose database holds many sessions, the session ID without `opencode:`; live data has no exceptions. |
| `llm.usage`, `llm.historical_usage` | Unchanged. They feed Grafana, and `llm.calls` links to usage by `trace_id`. |

The prototype tests this both ways:

- Calls rebuild every request body (by JSON value) and every response body
  (by byte), and in ClickHouse match `llm.requests` on every column of the
  deployed schema, compared both ways with `EXCEPT`.
- Every `llm.transcripts` row rebuilds from exactly one message or event, by
  file and line with identical bytes, and no other row is left over, in Go
  and again in ClickHouse, compared both ways with `EXCEPT`. The fixtures
  include a file synced to two hosts.
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
Each run:

1. Selects the requests of the last day that are not in `llm.calls` yet,
   with
   [`requests.sql`](../packages/cliproxy-plugins/normalize-conversations/requests.sql).
   Requests land when they complete, so a watermark on start times would skip
   every request that outlived the gap; selecting what is missing picks them
   up whenever they land. The day only bounds the scan, and must exceed the
   longest request and any outage.
2. Lists the sessions those requests touch with
   `normalize-conversations -requests -sessions`.
3. Reads those sessions' nodes and response leaves from `llm.messages` and
   `llm.calls` with
   [`state.sql`](../packages/cliproxy-plugins/normalize-conversations/state.sql).
4. Normalizes with `-state` and inserts the rows.

With the state restored, full-resend requests extend their trees without
writing them again, and delta requests continue responses from earlier
runs. Recent requests whose usage or previous response has not landed are
held back (see Session and Gaps), and `version` keeps the right row if a
node is written again anyway.
Deterministic IDs make reruns harmless. The job needs a ClickHouse user with
SELECT on the sources and INSERT on the new tables. The transcripts run
once, in one pass over all of them, after the proxy backfill, with
[`transcripts.sql`](../packages/cliproxy-plugins/normalize-conversations/transcripts.sql)
and the proxy's calls, each with its session, the session's parent and
client, its response ID and start, as `-proxied`. The normalizer reads its
input twice, through a copy in its output directory, so that needs room for
the transcripts once more (about 9 GiB).

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
-- that starts with a tag is a heuristic. Retries, compactions, and the
-- proxy's first call in a session a transcript also holds send a prompt
-- again, so each counts once per session, when it was first seen.
SELECT min(ts) AS first_seen, session_id, b.text AS prompt
FROM llm.messages FINAL
ARRAY JOIN blocks AS b
WHERE role = 'user' AND b.type = 'text' AND NOT startsWith(b.text, '<')
GROUP BY session_id, prompt
HAVING first_seen >= now() - INTERVAL 7 DAY
ORDER BY first_seen DESC
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
-- Calls and tokens per day, client, and model, as the responses reported
-- them. For costs, see the cost example.
SELECT toDate(started_at) AS day, client, model, count() AS calls,
    sum(uncached_input_tokens + cache_read_tokens + cache_write_tokens) AS input_tokens,
    sum(output_tokens) AS output_tokens
FROM llm.calls FINAL
GROUP BY day, client, model
ORDER BY day, input_tokens DESC
```

```sql
-- example: cost
-- Estimated cost per session and model of proxy calls, as the dashboard
-- prices them. A websocket trace carries many calls, so joining on
-- trace_id alone would count each upstream attempt once per call. Each
-- attempt belongs to one call of its trace instead: the latest to start
-- whose span holds it, or else the first to start within 50 ms after it.
-- The view has no attempt ID, but the owner depends only on the trace and
-- time. Unpriced attempts are NULL and left out of the sum.
WITH owners AS (
    SELECT u.trace_id AS trace_id, u.requested_at AS requested_at,
        argMin(c.call_id, (c.started_at > u.requested_at,
            abs(dateDiff('millisecond', c.started_at, u.requested_at)), c.call_id)) AS call_id
    FROM (SELECT DISTINCT trace_id, requested_at FROM llm.usage_metrics WHERE origin = 'live') AS u
    INNER JOIN (SELECT call_id, trace_id, started_at, completed_at FROM llm.calls FINAL WHERE origin = 'proxy') AS c
        ON c.trace_id = u.trace_id
    WHERE u.requested_at BETWEEN c.started_at - INTERVAL 50 MILLISECOND AND c.completed_at
    GROUP BY trace_id, requested_at)
SELECT c.session_id AS session, c.model AS model, count() AS attempts,
    sum(u.estimated_cost_usd) AS cost_usd
FROM llm.usage_metrics AS u
INNER JOIN owners AS o ON o.trace_id = u.trace_id AND o.requested_at = u.requested_at
INNER JOIN (SELECT call_id, session_id, model FROM llm.calls FINAL) AS c ON c.call_id = o.call_id
GROUP BY session, model
ORDER BY cost_usd DESC
LIMIT 50
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

```sql
-- example: call
-- One call as training data: the system prompt or instructions and the
-- tools it ran with, which are per-call context outside the message tree,
-- and the conversation it saw and produced. Context rows have a field, and
-- call_output marks the call's own outputs, which the export checks.
WITH RECURSIVE
    path AS (
        SELECT id, parent_id, seq, role, output, model, blocks
        FROM llm.messages FINAL
        WHERE session_id = (SELECT session_id FROM llm.calls FINAL WHERE call_id = {call:String})
            AND id = (SELECT if(empty(output_ids), input_id, output_ids[-1])
                FROM llm.calls FINAL WHERE call_id = {call:String})
        UNION ALL
        SELECT m.id, m.parent_id, m.seq, m.role, m.output, m.model, m.blocks
        FROM llm.messages AS m FINAL
        INNER JOIN path AS p ON m.id = p.parent_id
        WHERE m.session_id = (SELECT session_id FROM llm.calls FINAL WHERE call_id = {call:String})
    ),
    context AS (
        -- Split into items, or small enough to stay in the envelope.
        SELECT part.field AS field, part.position AS position, any(i.item) AS value
        FROM (SELECT request_parts FROM llm.calls FINAL WHERE call_id = {call:String})
        ARRAY JOIN request_parts AS part
        INNER JOIN llm.request_items AS i ON i.hash = part.hash
        WHERE part.field IN ('system', 'instructions', 'tools')
        GROUP BY field, position
        UNION ALL
        SELECT field, -1, JSONExtractRaw(request_envelope, field)
        FROM llm.calls FINAL
        ARRAY JOIN ['system', 'instructions', 'tools'] AS field
        WHERE call_id = {call:String} AND JSONHas(request_envelope, field)
        UNION ALL
        -- What a Responses API response echoed as in effect, which the
        -- export prefers: Codex sends no tools over websockets, and a delta
        -- request sends no instructions or tools at all.
        SELECT 'response', 0, response_body FROM llm.calls FINAL WHERE call_id = {call:String}
    )
SELECT * FROM (
    SELECT field, position, value, 0 AS seq, 0 AS id, '' AS role, false AS output, '' AS model, [] AS blocks,
        false AS call_output
    FROM context
    UNION ALL
    SELECT '', 0, '', seq, id, role, output, model, blocks,
        id IN (SELECT arrayJoin(output_ids) FROM llm.calls FINAL WHERE call_id = {call:String})
    FROM path)
ORDER BY field = '', field, position, seq
FORMAT JSONEachRow
```

Pipe either into `normalize-conversations -export openai` (or `anthropic`)
for training data; use the call query for training, since a conversation
alone lacks the system prompt and tools. The export takes the instructions
and tools a Responses API response echoed, where it echoed them, and the
request's otherwise. On 2026-11-14, 3,420 of 4,063 successful Responses
calls had their tools only in the echo; responses CLIProxy translates from
other providers echo nothing, and failed calls often have no echo and no
output. The export puts the system prompt first, flattens the echo's tool
namespaces, and converts tool definitions between dialects. It keeps text,
reasoning, tool calls and results in the order they happened, merges
consecutive assistant items into one turn until a tool result ends it, and
puts reasoning in `reasoning_content` or `thinking` blocks. Tool arguments
and definitions keep their JSON numbers exactly as written. Images are left
out; their data is in the raw items.

Definitions and calls always convert the same way:

- **Namespaces.** Flattened tools keep their bare names, which is what a
  call names, unless two namespaces define the same name: then those tools
  and the calls to them, which name their namespace, become
  `namespace__name`, the way MCP tools are named elsewhere. The echo puts
  top-level tools in a `functions` namespace that calls never name, so it
  counts as none. A call matches a tool by namespace and name, so a call
  whose namespace defines no such tool, even if another namespace does, or
  a tool defined twice differently, fails the export rather than take
  another tool's schema. In live data every call without a namespace names
  a top-level tool.
- **Freeform custom tools**, such as Codex's `exec`, take raw text: they stay
  custom tools in Chat Completions, and become tools taking the text as
  `input` in Anthropic Messages, which has no freeform tools and loses their
  grammar.
- **Hosted tools**, such as Responses `web_search` and `tool_search` or
  Anthropic's server tools, are left out of both exports, each call together
  with its result and its definition. Chat Completions has no hosted tools,
  and Anthropic's hosted results are opaque, often encrypted, and only in
  the raw items, so neither export could write them back faithfully. The
  text the model wrote from a result stays.

A call export is checked as a training example first, and fails with the
reason instead of printing one when the call produced nothing an export
keeps, such as a failed call that returned nothing, or when its output calls
a tool its context does not define, such as a failed delta call with output
but no echo, or a transcript call, whose transcript records no tools. It
also fails when a call to a JSON-schema tool has arguments that are no JSON
object, such as `{"path":` from an interrupted stream; the canonical rows
keep what streamed. Only the call's own outputs, by `output_ids`, are
checked. Earlier turns are context, even when they end the path: a failed
delta call that sent nothing new ends at the output of the call it
continues, and is refused.

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
-- A session has a row per source, so they are deduplicated first.
SELECT s.parent_session_id AS parent, s.session_id AS agent, count() AS messages
FROM (SELECT DISTINCT session_id, parent_session_id FROM llm.sessions FINAL
    WHERE parent_session_id != '') AS s
INNER JOIN llm.messages AS m FINAL ON m.session_id = s.session_id
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
  the CLI the job would run, the DDL, and the input and state queries.
- [`gitops/espresso/tests/llm-conversations.py`](../gitops/espresso/tests/llm-conversations.py):
  loads the fixtures into a real ClickHouse running the deployed schema, then
  normalizes them the way the job would, in runs with requests landing late
  and usage landing after its requests. It checks the lossless round trips, that the second run continues
  the first without writing its nodes again, and that Grafana permissions are
  unchanged, and runs every example above.

```sh
cd packages/cliproxy-plugins && go test -race ./...
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
