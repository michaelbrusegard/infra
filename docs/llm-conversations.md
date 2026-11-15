# LLM conversations: one canonical format

Status: ready to roll out as in [Rollout](#rollout). Merging creates the
canonical tables and a suspended job; nothing is normalized until the
backfill runs.

All LLM history currently sits in two raw shapes: the proxy archive
(`llm.requests`, `llm.request_items`, `llm.usage`) since 2026-11-09, and a
one-off dump of agent session logs (`llm.transcripts`) from 2026-06-10 to
2026-11-09. This proposes one canonical format for both. It serves two uses:
learning from my own LLM use (prompts, how agents worked, tools, models, costs,
failures), and exporting conversations as chat or SFT data with tool calls and
results.

## Decision

- **The proxy's raw capture is the permanent source of truth.**
  `llm.requests` and its content-addressed `llm.request_items`, and
  `llm.usage`, are never deleted and get no TTL. Storage grows with the
  capture, and the PVC is grown when needed; the raw rows are not rewritten
  to save space, such as by moving images out of items.
- **The canonical tables are a derived, rebuildable view.** `llm.sessions`,
  `llm.messages`, `llm.calls` and `llm.events` hold one clean format for all
  history, which the normalizer job keeps current. They never copy the raw
  capture: a proxy call names its `llm.requests` row, and a proxy message the
  item it was read from. When the normalizer improves, the proxy's rows are
  dropped and rebuilt from raw (see [Rebuild](#rebuild)).
- **The transcript import is normalized once, verified, and then dropped**,
  with `llm.historical_usage`. Transcript rows therefore hold their own
  content: messages with their blocks, sessions, calls with their usage, and
  for Claude Code calls since 2026-10-26 the system prompt and tools from its
  request logs, stored as items. What the import leaves out is listed in
  [What the transcript import keeps](#what-the-transcript-import-keeps) and
  approved as a loss. After the drop, the transcript period cannot be
  rebuilt unless an export is restored.
- **The dashboard's usage history moves to the canonical calls.**
  `llm.usage_metrics` reads pre-proxy history from transcript calls instead
  of `llm.historical_usage`, which counts Codex about 6.8% too high, as soon
  as the transcript import is complete.
- **Deferred**, since the proxy's view can be rebuilt with them later:
  recording the client headers that tell typed prompts from injected
  context, and the Codex base instructions in `session_meta`.

## Recommendation in short

- Four tables, `llm.sessions`, `llm.messages`, `llm.calls` and `llm.events`.
  Raw JSON stays where the proxy archived it, in `llm.requests` and the
  content-addressed `llm.request_items`. The only items the normalizer writes
  are the system prompts and tools of transcript calls, which no other table
  will hold after the drop.
- Messages form a **tree per session**. A node's ID covers its parent, so the
  context a proxy request resends every turn maps onto existing nodes. Codex's
  delta requests (`previous_response_id`) chain onto the previous response.
  Compaction starts a new root, and retries or edits branch.
- Proxy nodes are keyed by **content, ignoring transport fields where the
  protocols put them**, so a model's output and its resent copy are one node.
  Without this, Claude Code's moving `cache_control` markers split the tree
  at 50 of 52 turns in a live session. A node written again keeps the row of
  the call that produced it, whatever order calls are normalized in.
- A proxy message **references its exact source JSON**: an input by the hash
  of the request item it was read from, an output by its call, whose
  `llm.requests` row holds the response body. The extracted columns are a
  queryable view, so an extractor bug loses nothing on the proxy's side: a
  rebuild fixes it.
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
  refused rather than exported with tools missing. Only the call's own
  outputs are training targets; earlier turns are context.

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

The DDL is part of the production schema, ClickHouse's `schema.sql` in
[`apps/clickhouse/configmap.yaml`](../gitops/espresso/apps/clickhouse/configmap.yaml),
which ClickHouse runs on every start; every statement is idempotent.

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
| `blocks` | `Array(Tuple(type, source_type, text, tool_name, tool_namespace, tool_call_id, tool_input, is_error, media))`. `type` is one of text, thinking, tool_call, tool_result, image, file, compaction, fallback (Anthropic's record of another model taking over a refused reply, as JSON), other (a type the extractor does not know, which verification fails on); `source_type` keeps the dialect's own name. `tool_namespace` is the namespace a Responses API call names, such as an MCP server's. Image and file data, signatures and encrypted reasoning are not extracted. |
| `format` | The source dialect: anthropic, openai-responses, openai-chat, claude-code, codex, pi or opencode. |
| `item` | For a proxy input, the `llm.request_items` hash of the request part it was read from, or 0 when the request's envelope held it. A proxy output has none: its call's `llm.requests` row holds the response it was assembled from. |
| `host`, `path`, `line`, `part` | For a transcript message, where it came from: the file and the line's ID in it. `part` is empty for a whole line, and otherwise names what inside the line the message was built from: a Codex compaction's replacement history index, or the entry a Pi compaction sends again. After the drop these are provenance, not references. |
| `version` | Ranks the rows written for one node; `ReplacingMergeTree(version)` keeps the highest. See [Identity](#identity-and-deduplication). |

**`llm.calls`**: one row per model call, with only canonical columns. It
holds the call and session, `response_id`, `started_at` and `completed_at`,
`origin`, `client`, `source_format`, the responding `model`, `input_id` (the
last input message; its ancestors are the rest of the context) and
`output_ids`. Token counts are split the way `llm.usage_metrics` splits
them: uncached input, cache read, cache write, cache write by lifetime (5
minutes and 1 hour, which Anthropic prices differently), output and
reasoning. A proxy call names its raw row by `request_id`; its request and
response bodies, trace, status, error and user agent are read by joining
`llm.requests` (and `llm.request_bodies` for whole bodies). A transcript
call names its file by `host` and `path`, and `context` holds the system
prompt and tools Claude Code's request log recorded for it, as
`(field, position, hash)` parts into `llm.request_items`, split the way
`request_parts` are.

**`llm.events`**: how transcript sessions went, where no message or call
records it: Claude Code's API errors (`api_error`) and refusal fallbacks
(`model_refusal_fallback`), and Codex's interrupted turns (`turn_aborted`)
and rollbacks (`thread_rolled_back`). Each row has a session, time, file
(`host` and `path`), line, type and a `detail`: the error, the notice, why
the turn stopped, or how many turns were rolled back. Files that share a
session, such as one synced to two hosts, share line numbers and times, so
the file is part of the key. The proxy's failures are in `llm.requests`.

**`llm.call_history`**: a view of the transcript calls with usage in
`llm.historical_usage`'s columns, which `llm.usage_metrics` reads instead
of it once **`llm.transcript_import`** has the row the backfill writes when
the transcript import is complete (see [Usage history](#usage-history)).

**`llm.request_items`** stays as is: the proxy's items, plus the per-call
context of transcript calls and the tools of Codex's `additional_tools`
items, which proxy calls name in their context.

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
  stay in its `llm.requests` row.
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
overlapping batches collapse, and context items deduplicate by content hash.
That holds for identical inputs and rules only. A rerun with changed
extraction rules writes nodes under other keys beside the old ones, and
transcript rows from changed inputs, such as more files or proxy calls, do
not replace the old ones reliably (see [Overlap](#overlap-with-the-proxy)),
so either rebuilds the affected rows: delete them first, as in
[Rebuild](#rebuild).

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
   duplicate the conversation. Codex's `additional_tools` input items are
   context too: the call's `context` names their tools, after the request's
   own, rather than the tree holding them.
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

Each file is normalized on its own, and **every line is accounted for
once**: a message, an event, folded into a call, session or the tree, or a
dropped kind (see
[What the transcript import keeps](#what-the-transcript-import-keeps)). The
only thing files share is which of them holds each reply's call, which a
first pass over all files decides (see [Overlap](#overlap-with-the-proxy)).
The session ID is mapped
into CLIProxy's scheme: `claude:<session>`, `claude:<parent>:agent:<agent>`,
`codex:<thread>`, `codex:<parent>:agent:<agent path>`, `pi:<session>` and
`opencode:<session>`.

- **claude-code**: `user` and `assistant` lines, and attachments with rendered
  content, become messages. The parent is the nearest message ancestor, so
  attachments and system lines in the chain are skipped. A compaction boundary
  starts a new root, and the summary's blocks are `compaction`. Assistant
  lines group into one call by `requestId`, with the last line's usage, and
  the call takes the system prompt and tools of the request log its replies
  name. `ai-title` sets the title. A repeated entry keeps its first line.
- **codex**: `response_item` lines are messages chained in file order.
  Assistant items between two inputs form one call, and its usage comes from
  the next `token_usage_record`, or `token_count` in older logs. A
  `token_usage_record` ends its response, so assistant items after it start
  another call, and a second record with another response ID and no
  assistant items since, as a remote compaction writes before its
  `compacted` line (122 live), is a call of its own without outputs rather
  than the previous call's usage. Grouping by inputs alone merges these,
  and gives 146 live item keys two response IDs. In older logs a
  `token_count` does the same, except at a cumulative point the file
  already counted: Codex repeats a point, even inside the next response,
  and a repeat is no call's usage. Newer logs repeat each record in a
  count, at a point that drifts from the record's after a compaction, so
  where a file has records its counts are no usage. A sub-agent's file
  copies its parent's `session_meta` and history, with the counts but not
  always the items before them, so a call that a count gives its usage
  also matches its copies by the last `session_meta` ID and the point.
  Each distinct point thus counts once, as `llm.historical_usage` counts
  it, except that the importer counts the drifted repeats again (12,963
  live). The model
  comes from `turn_context`. A `compacted` line's `replacement_history`
  items become a new root chain, each with the line and its index as
  `part`. `agent_message` items, the messages a sub-agent and its parent
  send each other, are input messages with their header text (sender, task
  and message type; the payload is encrypted). `additional_tools` items are
  tool definitions Codex sends with every later call, so each call after
  one takes its tools as context, as Claude Code calls take their request
  logs; a compaction's replacement history replaces them with its own.
- **pi**: `message` entries are messages, and a `branch_summary` is a user
  message with a `compaction` block, in place. A `compaction` rebuilds what
  Pi sends from then on: the summary, then the entries from
  `firstKeptEntryId` to the compaction. The summary starts a new root, and
  copies of the kept messages follow it as context sent again, with
  `output = false`, the compaction's line, and the entry ID as `part`. Later
  entries continue from the last copy, and the original branch stays as it
  was. Each assistant message is one call, and so is each compaction: Pi
  summarizes with a call of the model in use (the last `model_change` or
  reply), which records its usage but no response ID. All 409 live
  compactions carry usage, 51,531,037 tokens. The call has no outputs, like a
  Codex remote compaction, and its input is the entry it summarized from.
- **opencode**: messages are ordered by time. Older part records attach their
  content to their message. A sub-agent's session record names its parent
  (`parent_id`, 142 of 228 live sessions), which becomes
  `opencode:<parent>`. A user message's `system` (121 live), the system
  prompt OpenCode sends with its turn, is the context of the calls answering
  it.

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

**Each reply is one call.** A reply is identified by its response ID, or
for Codex by the provider's ID of its first output item: a tool call's
`call_id`, or the item's `id`. 842 of 1,978 live Codex files are older logs
without response IDs, and a Codex sub-agent's copy of its parent's history
keeps the items' IDs but never the usage records that carry response IDs:
no response ID is in two live files, while 29k item IDs are. A copy whose
item the original file maps to a response ID gets that ID. A transcript
reply that the proxy returned, in any session, is the proxy's call.
Otherwise one file holds it. A Codex file that records the call's usage
holds it over any that does not, because only the file that made the call
writes its usage record: a copy holding it would count the call with no
tokens and no response ID. The call keeps the response ID any file maps
its item to. Otherwise, since a sub-agent or fork copies the replies it
starts from, where the files record that
ancestry, by their parent session, an ancestor's file holds the call over
its descendants', even when a skewed clock or timestamps of equal precision
put the copy first, and whatever the paths: path order is not ancestry
order in live Codex files. Between files of different lineages, the
lineage that recorded the reply earliest holds it, and within a lineage
level, the file with the earliest line, then the first by host, path and
session. Sibling forks holding a reply none of them wrote, or one file
synced to two hosts, tie and fall to the first. Where ancestry is not
recorded, such as a Claude Code session forked into a new session ID, or a
Codex agent spawned by another sub-agent, whose parent thread ID is not
that sub-agent's session ID, the earliest file is a surrogate owner: the
call counts once, but possibly in the copy's session, and for Codex only
when no file records its usage. Replies with no ID
at all, such as OpenCode's, or Codex replies whose items carry none, like
text-only messages from June 2026, cannot be matched to a copy, so each file
keeps its own call; no live OpenCode session is in two files. Item IDs
should be unique to the call that produced them, but where files map one
item key to more than one response ID, the key matches none of its calls:
each is matched by its own response ID, so they stay distinct calls, and a
copy without a response ID keeps a call of its own. `normalize-conversations`
prints every such key with its response IDs, and the
[collision audit](#collision-audit) lists them from `llm.transcripts`.
Only lines the file keeps count, not the proxy's (see the handover below),
so a reply the proxy returned is in no file's election, and one it never
returned stays with the file that made it. In every other file the reply is a copy. It
stays a message in that file's tree, because the model was sent it, but as
input (`output = false`, no model or call) like Pi's compaction copies, and
it adds no call.

So a file's rows depend only on the file, the replies of all files, and the
proxy's calls. The import is one complete pass: `normalize-conversations`
reads every transcript line, records each file's replies, then normalizes
the files, in any order. Run over the same lines and proxy calls, it writes
the same rows, which collapse. Rows from different inputs or rules do not
replace each other reliably, because a wrong output row outranks the
corrected input row and a wrong call is never removed, so such a rerun goes
into tables without transcript rows: delete the transcript calls and
sessions (`origin = 'transcript'`), the messages with a `path`, and all
events first. That needs the transcript lines, so only before the drop or
from a restored export.

**A handover at the session's first proxied call, verified by reply.**
Transcript lines from before it become messages and calls as usual. A line
from then on is the proxy's (`proxied` in the coverage) only when the reply
it leads to, its own or the next one the file records, is one the proxy
returned, by response ID from `llm.calls`: the proxy has that call with its
exact bodies. Any other line stays the file's: a turn the proxy never
captured, such as one of a session that left the proxy again, or a prompt
after the last proxied reply. Turns from before the proxy, and branches
compacted away before it, stay canonical messages, and no call or token is
counted twice. Only 3,714 transcript lines fall after the proxy started at
all; in the four Codex files the proxy took over, all 236 replies after the
handover are in `llm.requests`.

The proxy's first call resends the context from before it, so that context
is in both trees: as transcript nodes at their own times, and as the proxy
call's input nodes. The two are not merged, because matching transcript
lines to API messages needs fuzzy matching (Claude Code splits replies per
block) for little gain. Calls and tokens need nothing, since each call has
one owner; counting prompts or messages should dedupe by content per
session, as the prompts example does. Usage already uses a fixed handover,
which stays when its history moves to the transcript calls (see
[Usage history](#usage-history)).

### Collision audit

This lists the Codex item keys that `llm.transcripts` maps to more than one
response ID, grouping each file's output items into calls as the normalizer
does. It extracts only the fields it needs, in small blocks on one thread,
and orders each file's lines as one array rather than with window
functions, whose sort took 2 GiB: on the live table it reads the 1.3M Codex
lines in 10 seconds with a 330 MiB peak, and finds no collisions.

```sql
-- example: collisions
WITH
    lines AS (
        SELECT file, n,
            -- Output items are 1, and anything else 0: a response's usage
            -- record ends it.
            multiIf(e.type != 'response_item', 0,
                t IN ('reasoning', 'function_call', 'custom_tool_call')
                    OR (t = 'message' OR (t = '' AND e.payload.role != '')) AND e.payload.role = 'assistant'
                    OR t LIKE '%\_call', 1,
                0) AS output,
            if(output = 1, if(e.payload.call_id != '', e.payload.call_id, e.payload.id), '') AS item,
            e.type = 'token_usage_record' AS usage,
            if(usage, e.payload.response_id, '') AS response_id
        FROM (
            SELECT cityHash64(host, path, session) AS file, toUInt64OrZero(id) AS n,
                JSONExtract(line, 'Tuple(type String, payload Tuple(type String, role String, call_id String, id String, response_id String))') AS e,
                e.payload.type AS t
            FROM llm.transcripts
            WHERE source = 'codex'
                AND JSONExtractString(line, 'type') IN ('response_item', 'compacted', 'token_usage_record')
        )
    ),
    -- Each file's lines in order, numbered by call: an output item after
    -- anything else starts one.
    calls AS (
        SELECT file, line.1 AS n, line.3 AS item, line.4 AS usage, line.5 AS response_id, call
        FROM (
            SELECT file, arraySort(groupArray((n, output, item, usage, response_id))) AS ordered,
                arrayMap(l -> l.2, ordered) AS outputs
            FROM lines
            GROUP BY file
        )
        ARRAY JOIN ordered AS line,
            arrayCumSum(arrayMap((o, previous) -> o = 1 AND previous = 0,
                outputs, arrayPushFront(arrayPopBack(outputs), 0))) AS call
    ),
    -- A call's first usage record is its own. Later ones with another
    -- response ID are responses without items, such as compactions.
    keyed AS (
        SELECT argMinIf(item, n, item != '') AS item, argMinIf(response_id, n, usage) AS response
        FROM calls
        WHERE call > 0
        GROUP BY file, call
        HAVING item != '' AND response != ''
    )
SELECT 'item:' || item AS key, arraySort(groupUniqArray(response)) AS response_ids
FROM keyed
GROUP BY item
HAVING length(response_ids) > 1
ORDER BY key
SETTINGS max_threads = 1, max_block_size = 256, preferred_block_size_bytes = 1048576,
    max_execution_time = 600
```

## What the transcript import keeps

`llm.transcripts` is dropped once the import is verified, so the import
accounts for every line. Each line is counted once, by what became of it
and where its content is now, in the `coverage.tsv` the normalizer writes
(source, kind, disposition, destination, lines):

- **message** (`llm.messages`): the line is a message row, which names it by
  `host`, `path` and `line`, with its role, time, model, blocks and tree
  position.
- **event** (`llm.events`): the line is an event row with its detail.
- **call** (`llm.calls.usage`, `.model` or `.context`): the line is folded
  into a call this file writes: usage records and Codex token counts into
  its usage, turn settings into its model, Claude Code's request logs and
  Codex's additional tools into its context. What became of the call decides
  the line's disposition, so a line no written call holds is never counted
  as one.
- **copy** (the same columns): the line is folded into a call that another
  file holds, a copied reply's. A context line's items must be in a written
  call's context, which the import checks over all files.
- **session** (`llm.sessions`) or **structure** (`llm.messages.part`,
  `.parent_id` or `.blocks`): the line is folded into a session (titles,
  metadata) or the tree (Codex compacted histories, compaction boundaries,
  OpenCode part records, whose content is in their messages' blocks).
- **repeat** (`llm.messages` or `llm.calls.usage`): an entry written again,
  whose first line is the message, or a Codex token count that repeats a
  point counted already, echoes a usage record, or has no usage.
- **proxied** (`llm.calls`): the proxy returned the reply the line leads
  to, and holds its call.
- **dropped** (no destination): a kind listed below.

The import fails rather than count a line it cannot place: an unknown kind
or block, a folded line no call takes, an OpenCode part whose message is
not written, or a copy's context that no written call holds.

Inside the lines it keeps or folds, the import drops image and file data
(blocks keep the media type), thinking signatures and encrypted reasoning,
Claude Code's `wireToolInputs`, `apiBlockIndex` and client metadata such as
`gitBranch`, `version` and `entrypoint`, Codex message IDs and statuses, the
Codex base instructions in `session_meta` and the turn settings in
`turn_context` other than the model, the request parameters of Claude Code's
request logs (betas, effort, `max_tokens`), the usage details no column
holds, and the exact JSON of each line, including the order and spelling of
its keys. It also drops the encrypted payloads of Codex agent messages
and OpenCode's step markers and patch records (snapshot hashes and the
files an edit touched; the tool parts hold the edits).

A kind of line that is in none of these lists, or a block of a type the
extractor does not know, fails the import instead of being dropped or kept
as a type alone: the normalizer reports each with its count and writes
nothing to insert.

The kinds it drops, with their live counts on 2026-11-14 (all 2.2M lines,
before the proxy took any session over). These losses are approved:

| Source | Kind | Lines | MiB | Why it can go |
| --- | --- | ---: | ---: | --- |
| `claude-code` | `api-request-blob` | 48,172 | 226.1 | The message bodies of logged requests a reply names. The same messages are user, assistant and attachment lines; only the exact per-request message lists go. The blobs of requests no reply names are kept, below. |
| `claude-code` | `attachment:deferred_tools_record` | 30,800 | 20.4 | Which tools were deferred; the tools are in the call's context. Not shown to the model. |
| `claude-code` | `last-prompt` | 23,154 | 6.4 | Client state: the prompt box's last text. |
| `claude-code` | `atis-latch` | 22,872 | 1.8 | Client state. |
| `claude-code` | `queue-operation` | 13,706 | 10.4 | Prompts queued while busy; sent prompts are user messages. |
| `claude-code` | `mode` | 9,902 | 0.8 | Client state. |
| `claude-code` | `pr-link` | 6,649 | 1.4 | UI link to a pull request. |
| `claude-code` | `attachment:prompt_snapshot` | 1,969 | 77.6 | Snapshots of the prompt box. Not shown to the model. |
| `claude-code` | `cost-state` | 820 | 0.4 | The client's cost counter; calls carry usage. |
| `claude-code` | `attachment:command_permissions` | 507 | 0.2 | Permission settings. Not shown to the model. |
| `claude-code` | `result` | 135 | 1.8 | SDK result summaries; the reply is a message. |
| `claude-code` | `started` | 128 | 0.0 | Progress. |
| `claude-code` | `attachment:thinking_drop` | 97 | 0.1 | Not shown to the model. |
| `claude-code` | `attachment:structured_output` | 97 | 1.2 | Not shown to the model. |
| `claude-code` | `attachment:session_context` | 62 | 0.0 | Those without rendered content (the other 926 are messages). |
| `claude-code` | `fork-context-ref` | 21 | 0.0 | Client state. |
| `claude-code` | `system:informational` | 14 | 0.0 | UI notices. |
| `claude-code` | `launched` | 14 | 0.0 | Progress. |
| `claude-code` | `permission-mode` | 6 | 0.0 | Client state. |
| `claude-code` | `file-history-snapshot` | 5 | 0.0 | Undo history. |
| `claude-code` | `system:local_command` | 2 | 0.0 | UI notices. |
| `claude-code` | `attachment:credential_org` | 1 | 0.0 | Account metadata. |
| `claude-code` | `system:turn_duration` | 1 | 0.0 | Timing; calls have times. |
| `codex` | `event_msg:item_completed` | 172,907 | 1,174.6 | Copies of response items. |
| `codex` | `event_msg:agent_message` | 43,453 | 22.5 | Copies of assistant messages. |
| `codex` | `event_msg:mcp_tool_call_end` | 19,042 | 90.3 | Copies of tool results, which are response items. |
| `codex` | `event_msg:patch_apply_end` | 13,102 | 43.9 | Copies of tool results. |
| `codex` | `event_msg:task_started` | 11,768 | 3.3 | Progress. |
| `codex` | `event_msg:thread_settings_applied` | 10,395 | 16.5 | Settings; the model is in `turn_context`. |
| `codex` | `event_msg:task_complete` | 9,184 | 12.0 | Progress. |
| `codex` | `event_msg:user_message` | 7,573 | 8.8 | Copies of user messages. |
| `codex` | `event_msg:sub_agent_activity` | 5,459 | 1.5 | Progress; sub-agents have their own files. |
| `codex` | `world_state` | 4,287 | 40.9 | Environment snapshots for the UI. |
| `codex` | `event_msg:web_search_end` | 2,140 | 1.1 | Copies of web search calls. |
| `codex` | `inter_agent_communication_metadata` | 1,677 | 0.2 | Routing metadata of sub-agent messages. |
| `codex` | `event_msg:context_compacted` | 1,168 | 0.1 | Progress; the `compacted` line holds the new context. |
| `codex` | `turn_context` | ≤ 2,391 | 0.0 | Settings of a turn that made no call, such as an interrupted one. The others give their calls the model. |
| `opencode` | `message:idle` | 63 | 0.0 | Status. |
| `pi` | `thinking_level_change` | 811 | 0.1 | Settings. |
| `pi` | `model_change` | 803 | 0.1 | Settings; each reply names its model. |
| `pi` | `context_edit` | 51 | 0.0 | Client edits to the context, which the following messages reflect. |

That is 463,017 lines (1.7 GiB, a fifth of the bytes, two thirds of it
Codex's copies of response items). By kind, the other lines are 1,248,579
messages (6.3 GiB), 510,140 folded into calls, sessions and the tree, and
3,170 events. Each kind of Claude Code attachment is a message when its line
carries rendered content, as all lines of the kinds not listed do.

### Extraction audit

Every record kind and every block type in the live import, on 2026-11-14,
and what the extractor makes of it. Types marked new were kept as a type
alone before this audit.

| Source | Type | Live | Extracted as |
| --- | --- | ---: | --- |
| codex | `response_item:reasoning` | 175,698 | thinking (summary and content text; encrypted content dropped) |
| codex | `response_item:custom_tool_call`, `function_call` | 142,056, 57,562 | tool call |
| codex | `response_item:custom_tool_call_output`, `function_call_output` | 142,126, 57,540 | tool result (`input_text`, string, `input_image`) |
| codex | `response_item:message` | 81,628 | message (`output_text`, `input_text`, `input_image`) |
| codex | `response_item:agent_message` (new) | 1,793 | input message with its header text; `encrypted_content` dropped |
| codex | `response_item:additional_tools` (new) | 927 | tools context of every later call; the proxy's call when the proxy took the session over before the next call |
| codex | `response_item:web_search_call`, `tool_search_call` | 361, 83 | hosted tool call |
| codex | `response_item:tool_search_output` | 83 | tool result, its `tools` (definitions, namespaces included) as JSON text |
| codex | `compacted` history items | 52,487 | `message` and `compaction` nodes; `agent_message` (125) and `additional_tools` (88) as above |
| claude-code | `assistant` blocks | 153,252 lines | `tool_use`, `thinking`, `text` |
| proxy (Anthropic) | `web_search_result` in a `web_search_tool_result`, `fallback` | 838, 25 | the result's title and URL as text (page content is encrypted); a `fallback` block |
| claude-code | `user` blocks | 87,981 lines | `tool_result`, string, `text`, `image`; inside results `text`, `image` and `tool_reference` (new, 1,322: the tool's name) |
| claude-code | `attachment:*` with `rendered` | 30 kinds | message of the rendered text |
| pi | `message` blocks | 306,680 lines | `text`, `toolCall`, `thinking`, `image`, string |
| opencode | parts, inline and as records | 50,546 | `text`, `reasoning`, `tool`, `file`, `compaction`; `step-start`, `step-finish` and `patch` carry no content |

Every other record kind is a message, folded into a call, session or the
tree, an event, or a dropped kind in the table above.

Claude Code has logged its requests since 2026-10-26: an `api-request` per
call, naming a deduplicated `api-request-shape` with the system prompt and
tools, and `api-request-blob` lines with message bodies. Each reply names its
request (`requestRef`), so its call takes the shape's system prompt and tools
as context items, one per system block and tool, as the archive splits
request bodies. 134,405 of 137,230 replies with a `requestRef` find their
request in their own file. A reply that several files hold takes its
request log from any of them, since the first pass over all files records
every log: of the 47 live Claude Code replies in more than one file, the
file that holds the call lacks the log for 28, which a sub-agent's or a
sibling fork's copy has. The file that holds the call stays the same. Those
calls export as tool-using training examples.

952 live requests are named by no reply in any file: requests that failed
or were interrupted, mostly of the main thread (837) and of sub-agents.
Nothing else holds what they sent, so each is a call without outputs, with
the request's ID as `call_id`, its model, and the time it was logged. Its
input is the conversation as the file had it then, and its context holds
the shape's system prompt and tools and, as `messages` parts at their
positions in the request, the messages Claude Code logged as blobs: the
first `keep` messages of its `base` request and its own `tail`, each named
by a hash. Claude Code logs a message as a blob only when it is not one of
the file's own lines (161,125 of 243,141 tail references name no blob, as
all blobs resolve within their file), so the other positions are messages
of the tree. The blobs these requests hold are counted as `call`; the
others are dropped.

The hash is the SHA-256 of the message as the API received it, `{role,
content}` as JSON with sorted keys and no whitespace, so the import
resolves every other position to the file's message lines, and fails on
any it cannot, or on a base request the file lacks. On 2026-11-14 this
resolved all 6,249 tail references of the 952 requests, 200,835 with
their base requests' messages, and left none: 2,257 tail references are
blobs, 2,636 a line's message as written, 205 a line whose string content
went as a single text block (Claude Code sends the last message so, to
mark it for the cache), 1,037 a reply whose streamed blocks are a line
each, as one message, and 114 consecutive user lines as one message, such
as a turn's tool results and a prompt queued after them, since the API
takes no two user messages in a row. None of the requests falls after the
proxy took its session over.

### Usage history

`llm.historical_usage` was imported from the same lines with rules of its
own, and counts Codex's drifted repeats of token counts again (12,963 live,
about 6.8% of Codex history). The transcript calls count each response once,
so they replace it: `llm.call_history` presents them in
`llm.historical_usage`'s columns, and `llm.usage_metrics` reads its history
from `llm.call_history` once `llm.transcript_import` has a row, and from
the old import until then. The backfill writes that row last, after the
import's insert and checks: inserts are not atomic across tables or
retries, so an import that fails part way can leave some of its calls,
which would otherwise replace the history with part of it. It reads the
old import through
`llm.old_import_usage`, a `Merge` table over `llm.historical_usage` that
is empty while no such table exists: ClickHouse resolves every table a
query names, even in a branch whose condition is false, so a view naming
`llm.historical_usage` would fail from its drop on. The cutover is in the
production schema, so it needs no change at the time:

- Until the transcript import is complete, the dashboard shows the old
  import's history, as it does today, even if a failed run left calls.
- Once the backfill's checks pass and it marks the import complete, it
  shows the transcript calls'. If the import is deleted later, with its
  row in `llm.transcript_import`, it shows the old import's again.
- After the drop, the history stays, at once and after restarts:
  `schema.sql` creates no `llm.transcripts` again, and the empty
  `llm.historical_usage` it creates on the next start is never read, since
  the import is complete. `verify.sql` reads the old import the same way,
  and reports no old import rows after the drop.

Its fixed handover (`requested_at < min(llm.usage.requested_at)`) stays.
The rows follow the importer's rules: the provider from the model's prefix
(`unknown` otherwise, where the importer used the provider the line named),
Claude's thinking tokens as reasoning, Pi compactions
under the model in use (the importer recorded them as `(unknown)`), OpenCode's reasoning added to output
unless its recorded total excludes it, cache writes by lifetime, and calls
with no tokens left out. Origins stay `history:<client>`. The tests run the
production schema before and after the import, after a restart, right after
the drop, and after the next restart.

## Ongoing capture

**Recommended: the plugin keeps writing the raw capture, and a normalizer job
derives the canonical rows.**

- Codex delta requests need the previous response's output. The plugin sees
  it, but loses it on restart. A job can always read it back from ClickHouse.
- The capture stays the permanent log. When the extraction improves, or a
  client changes its format, the canonical rows are rebuilt from it. If the
  plugin wrote only canonical rows, an extractor bug would lose data for good.
- The plugin stays small and off the critical path. Assembling streams and
  walking trees per request is work it should not do while proxying.

The job runs the same Go package as a CronJob, for example every 10 minutes.
Each run:

1. Selects the requests that are not in `llm.calls` yet, an hour at a
   time from the oldest hour that has any, which
   [`missing.sql`](../packages/cliproxy-plugins/normalize-conversations/missing.sql)
   lists, with
   [`requests.sql`](../packages/cliproxy-plugins/normalize-conversations/requests.sql).
   Requests land when they complete, so a watermark on start times would skip
   every request that outlived the gap; selecting what is missing picks them
   up whenever they land, and catches up after a stop or outage of any
   length. The current hour's window is open (`before` is far in the
   future). Only the items the normalizer reads are sent, conversation
   messages and client metadata, each once per window, with the first
   request that uses it, and the normalizer keeps them for the window. An
   hour bounds them to the CronJob's memory: the busiest live hour held
   140 MiB of items and 250 MiB of bodies, the busiest day 840 MiB and
   2.2 GiB. A run starts no window after 5 minutes, and the next run goes
   on from the oldest window left. Steps 2 to 4 run for each window, which
   is inserted before the next reads its state.
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
Deterministic IDs make reruns over the same input harmless.

The job is the `llm-normalizer` CronJob in
[`apps/clickhouse/llm-normalizer.yaml`](../gitops/espresso/apps/clickhouse/llm-normalizer.yaml),
every 10 minutes, next to ClickHouse. The plugin image's CI builds
`normalize-conversations` into `/normalizer` of the image, with
[`normalize.sh`](../packages/cliproxy-plugins/normalize-conversations/normalize.sh)
and the queries, and promotes it into the CronJob and the backfill Job as it
does into CLIProxyAPI. An init container copies `/normalizer` next to
`clickhouse-client` in the ClickHouse server image, and `normalize.sh cron`
runs the four steps over the native protocol. ClickHouse's network policy
admits only the normalizer's pods to the native port, and they reach
nothing else. They connect as `llm_normalizer`, with the password of the
`clickhouse-llm-normalizer` secret, which ClickHouse reads too: CLIProxy's
and Grafana's pods reach the HTTP port, and without it could use the user
to read the raw history. It has SELECT on the
sources (`llm.requests`, `llm.request_items`, `llm.usage`, and until they
are dropped `llm.transcripts` and `llm.historical_usage`, which it reads
through `llm.old_import_usage`), SELECT and INSERT
on `llm.sessions`, `llm.messages`, `llm.calls`, `llm.events` and
`llm.transcript_import`, SELECT on `system.mutations`, and INSERT
on `llm.request_items`; it cannot read the dashboard's view, write the raw
capture, delete, or drop. The CronJob starts suspended, so it waits for the
backfill.

### Backfill

The backfill runs in the cluster as a one-off `llm-backfill-` Job, on
ClickHouse's node, with a 40 GiB local scratch volume (`openebs-hostpath`)
that goes with the pod. Nothing crosses the workstation's link but the
Job's log. The Job's manifest,
[`llm-backfill-job.yaml`](../gitops/espresso/apps/clickhouse/llm-backfill-job.yaml),
is not in the Kustomization, so Flux never applies it;
[`llm-backfill.sh`](../gitops/espresso/apps/clickhouse/llm-backfill.sh)
creates it under a name of its own, waits until its conditions say it
completed or failed, and saves its log. A finished Job is kept for a week,
so a rerun never meets it. `normalize.sh backfill` first waits for deletes
in `llm` that ClickHouse is still applying, such as a recovery's, then
runs, in order, because which transcript file holds a reply's call depends
on the proxy's calls:

1. **The proxy**, from its first request, in start order, so `llm.calls`
   holds every proxied call: the job's steps an hour at a time, with no
   time limit, each hour inserted before the next reads its state. A day's
   requests and items exceed the server's memory in one join (the first
   backfill attempt failed at 4 GiB), and an hour bounds the items the
   server joins at once: joined in full,
   the items of every request would be 68 GiB rather than 2.6 GiB, and each
   run sends an item once. The last hour reaches into the future; its
   requests from the last 10 minutes are held back for the job.
2. **The transcripts**, once, in one pass, and only into tables without
   transcript calls: the proxy's calls from
   [`proxied.sql`](../packages/cliproxy-plugins/normalize-conversations/proxied.sql),
   then the lines from
   [`transcripts.sql`](../packages/cliproxy-plugins/normalize-conversations/transcripts.sql)
   in parts of whole files of about 256 MiB that
   [`files.sql`](../packages/cliproxy-plugins/normalize-conversations/files.sql)
   lists, which the table's key finds, so each query sorts only its part.
   The parts go gzip-compressed into one file, which
   `normalize-conversations -in` reads twice without a decompressed copy.
   The largest dropped kinds arrive as their type alone. If the normalizer
   reports a coverage error, or its coverage counts other than
   `llm.transcripts`' lines, nothing is inserted; otherwise the five files,
   `llm.request_items` included, are, and the log has `coverage.tsv`.
3. **The checks** of
   [`verify.sql`](../packages/cliproxy-plugins/normalize-conversations/verify.sql):
   the proxy's references both ways, unique response IDs, no transcript call
   the proxy returned, context items and message items present, tree
   integrity, and calls and tokens per client against the old import. A
   check that finds a violation fails the Job; the reports are for
   [Before dropping the transcripts](#before-dropping-the-transcripts).

The transcript input is about 7.5 GiB of lines uncompressed, about 2 GiB on
the scratch volume, plus the rows to insert. The server's work per query is
bounded by a day of requests or a part of files, on one thread.

### Rollout

1. **Merge** the change. Flux applies the schema (the canonical tables and
   `llm.call_history`, created on ClickHouse's restart), the normalizer's
   user, port and network policy, and the suspended CronJob. The dashboard
   keeps showing the old import's history.
2. **Wait for the image.** The plugin image's CI builds the normalizer and
   commits `chore(cliproxy): update plugin image`, which names the new
   image in the CLIProxyAPI installer, the CronJob and the Job. Pull it.
3. **Run the backfill** from the repo root, in the dev shell:
   `gitops/espresso/apps/clickhouse/llm-backfill.sh`. The scratch volume
   is not reserved: the Job writes about 14 GiB (2 GiB of compressed
   lines, 8 GiB of rows, and up to 3 GiB for a day of proxy requests) to
   `/var/local/openebs`, the node's own disk, so before each attempt the
   script checks that the persistent disk of ClickHouse's node, which the
   kubelet reports as its image filesystem, has 20 GiB and a million
   inodes free, and refuses otherwise. The node filesystem is the tmpfs
   root, so its figure does not count. On 2026-11-14 ClickHouse ran on
   espresso-2, which had 41 GiB of 118 free, and room for the Job's 2 CPUs
   and 6 GiB at most (34% of its CPU and 18% of its memory were
   requested); espresso-1 had 25 GiB free. A finished attempt keeps its
   pod, and with it its scratch, until its Job is deleted, so each run
   first deletes earlier finished attempts, whose logs it already saved,
   and refuses to start beside one still running. The script exits
   non-zero when the Job fails, with the log in `<job name>.log`. To retry,
   run it again: each run is a new Job. A failed run inserted nothing of the
   transcripts if it failed before their insert; otherwise delete the
   transcript rows as in [Rebuild](#rebuild) first, since the Job refuses
   to import twice. The Job waits for those deletes to finish before it
   inserts anything. The proxy's days are safe to run again. The
   dashboard reads the transcript calls' history once the Job's checks
   pass, when it marks the import complete in `llm.transcript_import`.
4. **Resume the job**: set `suspend: false` in `llm-normalizer.yaml` and
   push. It picks up every request the backfill left, however late it
   landed or long the job waited.
5. **Verify** with the log and
   [Before dropping the transcripts](#before-dropping-the-transcripts), then
   drop the old import there. A later run of the checks alone is
   `normalize.sh verify` in a copy of the Job.

## Rebuild

The proxy's canonical rows are derived and can be regenerated at any time,
for example after an extractor fix:

1. Stop the job.
2. Delete the proxy's rows: `ALTER TABLE llm.calls DELETE WHERE origin =
   'proxy'`, the same for `llm.sessions`, and `ALTER TABLE llm.messages DELETE
   WHERE path = ''`. Or, if the schema changes, drop and recreate the four
   tables and restore the transcript rows from their export (below).
3. Run step 1 of the backfill: `normalize.sh` in a copy of the backfill
   Job whose command runs the proxy's days, or the Job itself while the
   transcript rows are absent.
4. Start the job again.

The transcript period cannot be rebuilt from raw once `llm.transcripts` is
dropped. Its canonical rows are then the only record, and a rebuild must keep
them, `origin = 'transcript'` and messages with a `path`, or restore them
from the optional export to `freddo` (see the checklist). If the export of
`llm.transcripts` itself is kept, restoring it and rerunning step 2 of the
backfill rebuilds them too. To redo the transcript import before the drop,
delete its rows first: `ALTER TABLE llm.calls DELETE WHERE origin =
'transcript'`, the same for `llm.sessions`, `ALTER TABLE llm.messages DELETE
WHERE path != ''`, `ALTER TABLE llm.events DELETE WHERE 1`, and `TRUNCATE
TABLE llm.transcript_import`, as the `default` user through `kubectl
exec`. ClickHouse applies the deletes in
the background; `SETTINGS mutations_sync = 1` after each makes it return
once they are done, and the backfill waits for any still going. Their items are content-addressed,
so the rerun's collapse with them. A proxy rebuild changes which transcript calls
are copies only if it changes the proxy's sessions or response IDs; if it
does, rerun the transcript pass from the export as well.

## Verification

The backfill starts as an additive trial: it only inserts into the canonical
tables and `llm.request_items`. Every difference found is listed and
explained, not just counted.

- **Unchanged raw capture.** `llm.requests` and `llm.transcripts`, and the
  proxy's items in `llm.request_items`, are unchanged throughout: their row
  counts and `sum(cityHash64(*))` match before the trial, after each step, and
  at the end.
- **Proxy references, both ways.** Every `llm.requests` row is exactly one
  proxy call, and every proxy call's `request_id` names one. Every message
  `item` is a part of the request its call names, and in
  `llm.request_items`, and every proxy output's call exists.
- **Transcript coverage.** `coverage.tsv` counts every `llm.transcripts` row
  once, its totals match the table's per source, every row but the dropped
  ones names a destination, and the rows there hold it: usage lines are
  calls with usage, request logs calls with context, proxied lines replies
  in `llm.calls`. The lines messages
  (`part = ''`) and events name are exactly as many as it counts as messages
  and events, all distinct and all in `llm.transcripts`. Every dropped kind is
  in the [table](#what-the-transcript-import-keeps), with about the counts it
  lists. Messages with a `part`, and transcript calls, name existing lines
  and files. Every transcript call's `context` hash is in
  `llm.request_items`.
- **Invocation identity.** No response ID belongs to more than one call, no
  transcript call has a response ID the proxy returned, the
  [collision audit](#collision-audit) returns no rows, and the normalizer
  reports no collisions. Calls whose source records a response ID, model or
  usage have them.
- **Calls and tokens.** Proxy calls reconcile with `llm.usage` by
  `trace_id`, through their `llm.requests` rows, in calls and each token
  kind, per day, client and model. Transcript calls reconcile with
  `llm.historical_usage` per day, client and model, except where the importer
  counted differently: Codex's drifted repeats, which it counted again (about
  6.8% of Codex tokens), and lines the importer skipped, such as records
  without a timestamp. Every remaining difference is explained.
- **Tree integrity.** Every message's parent is in its session, or it is a
  root, and no chain loops. Every call's input and outputs exist, its
  outputs are output messages of its session, and no message is the output
  of two calls.
- **Exports.** A sample of calls of every client and source format exports
  to both dialects, and the training check passes or names its reason. Claude
  Code calls with a request log export with their tools.
- **Repeatability and recovery.** Normalizing the same input again, in
  another file order or split into other runs, gives identical rows, and a
  job run interrupted and run again leaves no extra rows after `FINAL`. A
  rebuild of the proxy's rows, as above, gives the same rows.
- **Resources.** The scratch volume stays within the estimates above,
  every query stays within the server's memory, the job finishes well inside
  its interval, and storage grows as estimated in [Sizes](#sizes).

### Before dropping the transcripts

1. **Coverage**: the transcript coverage check above passes, and the dropped
   kinds and counts match the table.
2. **Tokens**: the transcript calls reconcile with `llm.historical_usage` as
   above, and `llm.usage_metrics`, which reads `llm.call_history` once the
   import is complete, gives the expected history per day, client and
   model on the dashboard.
3. **Spot checks per agent**: for Claude Code, Codex, Pi and OpenCode, read a
   few conversations with the conversation query against the transcript
   files, including a compaction, a sub-agent and a session the proxy took
   over, and export a call of each, a Claude Code call with its tools
   among them.
4. **Optional export to `freddo`**: `llm.transcripts` and
   `llm.historical_usage` as compressed JSON lines (about 3 GiB), so the
   transcript period can be rebuilt later. Without it, the canonical rows are
   the only record.
5. **Drop** `llm.transcripts` and `llm.historical_usage`. The dashboard
   already reads the transcript calls, and no view names either table, so
   nothing needs a restart; see [Usage history](#usage-history).

## Sizes

Estimates are from the profiling above and live samples (73 requests, and
1,194 transcript lines from 12 files across all four sources). Loaded into
ClickHouse, the sample's `llm.messages` compressed 4.1x.

| Part | On disk |
| --- | --- |
| Proxy messages: rows plus extracted text, about 10% of item bytes because images dominate, about 250 MiB uncompressed so far | ~70 MiB, then ~12 MiB a day |
| Proxy calls: canonical columns only, about 200 bytes a call | ~5 MiB, then under 1 MiB a day |
| Transcript messages: extracted text is about half of the 6.3 GiB of message lines | ~0.9 GiB |
| Transcript calls, sessions and events | ~50 MiB |
| Transcript call context: 1,466 request shapes (59.5 MiB of lines), one item per system block and tool, deduplicated | ~10 MiB |

Nothing in the canonical tables copies the raw capture, so they add about
1 GiB in total, and about 12 MiB a day.

- **During the trial**: the raw capture plus the canonical tables, about
  6.5 GiB against 5.4 GiB now.
- **After the drop** of `llm.transcripts` (3.06 GiB) and
  `llm.historical_usage`: about 3.4 GiB.
- **Growth**: the proxy's capture, about 420 MiB a day (290 MiB of items,
  130 MiB of responses), plus 12 MiB of canonical rows. About 69 GiB of the
  75 GiB volume is free, which lasts four to five months; the PVC is grown
  before then.

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
-- A tool call ID is one invocation, so copies of the call or its result in
-- other files or later requests count once.
WITH
    tool_calls AS (
        SELECT b.tool_call_id AS id, any(b.tool_name) AS tool, any(model) AS model
        FROM llm.messages FINAL ARRAY JOIN blocks AS b
        WHERE output AND b.type = 'tool_call' AND b.tool_call_id != ''
        GROUP BY id),
    results AS (
        SELECT b.tool_call_id AS id, max(b.is_error) AS failed
        FROM llm.messages FINAL ARRAY JOIN blocks AS b
        WHERE b.type = 'tool_result' AND b.tool_call_id != ''
        GROUP BY id)
SELECT model, tool, count() AS uses, countIf(failed) AS failures
FROM tool_calls INNER JOIN results USING (id)
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
-- prices them. Usage links to a call's llm.requests row by trace_id. A
-- websocket trace carries many calls, so joining on trace_id alone would
-- count each upstream attempt once per call. Each attempt belongs to one
-- call of its trace instead: the latest to start whose span holds it, or
-- else the first to start within 50 ms after it. The view has no attempt
-- ID, but the owner depends only on the trace and time. Unpriced attempts
-- are NULL and left out of the sum.
WITH
    calls AS (
        SELECT c.call_id AS call_id, c.session_id AS session_id, c.model AS model,
            r.trace_id AS trace_id, r.started_at AS started_at, r.completed_at AS completed_at
        FROM (SELECT call_id, session_id, model, request_id FROM llm.calls FINAL WHERE origin = 'proxy') AS c
        INNER JOIN (SELECT request_id, trace_id, started_at, completed_at FROM llm.requests) AS r
            ON r.request_id = c.request_id),
    owners AS (
        SELECT u.trace_id AS trace_id, u.requested_at AS requested_at,
            argMin(c.call_id, (c.started_at > u.requested_at,
                abs(dateDiff('millisecond', c.started_at, u.requested_at)), c.call_id)) AS call_id
        FROM (SELECT DISTINCT trace_id, requested_at FROM llm.usage_metrics WHERE origin = 'live') AS u
        INNER JOIN calls AS c ON c.trace_id = u.trace_id
        WHERE u.requested_at BETWEEN c.started_at - INTERVAL 50 MILLISECOND AND c.completed_at
        GROUP BY trace_id, requested_at)
SELECT c.session_id AS session, c.model AS model, count() AS attempts,
    sum(u.estimated_cost_usd) AS cost_usd
FROM llm.usage_metrics AS u
INNER JOIN owners AS o ON o.trace_id = u.trace_id AND o.requested_at = u.requested_at
INNER JOIN calls AS c ON c.call_id = o.call_id
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
-- and the conversation it saw and produced. The context comes from a proxy
-- call's llm.requests row and the call's context. Context rows
-- have a field, a call row marks the call, and call_output marks the
-- call's own outputs, which the export checks.
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
    request AS (
        SELECT request_envelope, request_parts, response_body FROM llm.requests
        WHERE request_id = (SELECT request_id FROM llm.calls FINAL WHERE call_id = {call:String})
    ),
    context AS (
        -- Split into items, or small enough to stay in the envelope.
        SELECT part.field AS field, part.position AS position, any(i.item) AS value
        FROM (SELECT request_parts AS parts FROM request
            UNION ALL SELECT context FROM llm.calls FINAL WHERE call_id = {call:String})
        ARRAY JOIN parts AS part
        INNER JOIN llm.request_items AS i ON i.hash = part.hash
        WHERE part.field IN ('system', 'instructions', 'tools')
        GROUP BY field, position
        UNION ALL
        SELECT field, -1, JSONExtractRaw(request_envelope, field)
        FROM request
        ARRAY JOIN ['system', 'instructions', 'tools'] AS field
        WHERE JSONHas(request_envelope, field)
        UNION ALL
        -- What a Responses API response echoed as in effect, which the
        -- export prefers: Codex sends no tools over websockets, and a delta
        -- request sends no instructions or tools at all.
        SELECT 'response', 0, response_body FROM request
    )
SELECT * FROM (
    -- Marks the rows as a call's, so the export checks it as a training
    -- example even when it has no context and no outputs.
    SELECT 'call' AS field, 0 AS position, '' AS value, 0 AS seq, 0 AS id, '' AS role, false AS output,
        '' AS model, [] AS blocks, false AS call_output
    UNION ALL
    SELECT field, position, value, 0, 0, '', false, '', [], false
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
  a top-level tool. That check applies to the exported call's own outputs.
  Earlier tool calls were made under definitions that may have changed
  since, such as an MCP server renamed between turns, so one that matches
  none of this call's tools keeps its own name, `namespace__name` or bare,
  and never fails the export, even when no current tool has its name, so two
  removed tools named alike stay apart. Such a bare name can coincide with a tool the
  call defines in a namespace; it is context, not a target.
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

A call export is checked as a training example first, which the call
query's `call` row asks for, whether or not the call has context or
outputs, and fails with the
reason instead of printing one when the call produced nothing an export
keeps, such as a failed call that returned nothing, or when its output calls
a tool its context does not define, such as a failed delta call with output
but no echo, or a transcript call whose transcript records no tools. It
also fails when a call to a JSON-schema tool has arguments that are no JSON
object, such as `{"path":` from an interrupted stream; the canonical rows
keep what streamed. Only the call's own outputs, by `output_ids`, are
checked. Earlier turns are context, even when they end the path: a failed
delta call that sent nothing new ends at the output of the call it
continues, and is refused.

Only those outputs are training targets. In the OpenAI export of a call,
every other assistant message has `weight: 0`, so fine-tuning learns
nothing from earlier turns, such as an earlier interrupted tool call.
Anthropic Messages has no weights: the call's outputs end its path, and the
export starts them in a message of their own even right after assistant
context, which the API would merge itself, so the last message is exactly
the call's output and the only one to train on. A conversation export
weights nothing.

What training exports can cover is limited by what the sources record:

- **After a handover**, transcript lines whose replies the proxy returned
  are the proxy's, which exports them from its raw capture.
- **Images** are left out of both exports, so an example whose context had
  an image teaches a reply to context the model saw more of.
- **Hosted tools** are left out with their results, so text the model wrote
  from a search result stands without the result.
- **Transcripts record no tool definitions or system prompts**, except
  Claude Code's request logs since 2026-10-26 and Codex's `additional_tools`
  items since 2026-10-25, which calls take as context.
  Any other transcript call that calls a tool is refused, and one that
  answers in text exports without its real context.

```sql
-- example: raw
-- The raw source behind each proxy message of a session, which holds
-- images, signatures, encrypted reasoning, and anything else the blocks
-- leave out: the request item an input was read from, or the response body
-- of the call that produced an output. Transcript messages have only their
-- blocks once llm.transcripts is dropped.
WITH messages AS (SELECT * FROM llm.messages FINAL WHERE session_id = {session:String} AND path = '')
SELECT m.seq AS seq, m.role AS role, multiIf(m.item != 0, i.item, m.output, r.response_body, '') AS raw
FROM messages AS m
LEFT JOIN (SELECT hash, any(item) AS item FROM llm.request_items
    WHERE hash IN (SELECT item FROM messages) GROUP BY hash) AS i ON i.hash = m.item
LEFT JOIN (SELECT request_id, response_body FROM llm.requests
    WHERE request_id IN (SELECT call_id FROM messages WHERE output)) AS r ON r.request_id = m.call_id
ORDER BY seq
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

- **References versus copies.** Copying the raw capture into the canonical
  tables would let the raw tables expire, but the raw capture is kept for
  good, so copies would only double it (130 MiB a day for responses alone).
  Proxy rows reference it, and are rebuilt from it.
- **Transcripts: extracted content versus raw lines.** Keeping each line's
  raw JSON as an item would keep the transcript period rebuildable, at about
  3 GiB, the size of `llm.transcripts` itself. The decision is to keep what
  the extraction holds, list what goes, and optionally keep a compressed
  export outside the cluster.
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
  the CLI the job runs, and the input and state queries.
- [`gitops/espresso/tests/llm-conversations.py`](../gitops/espresso/tests/llm-conversations.py):
  loads the fixtures into a real ClickHouse running the production schema,
  then normalizes them the way the job would, in runs with requests landing
  late and usage landing after its requests, and runs the backfill Job's
  `normalize.sh` in the ClickHouse image as `llm_normalizer`. It checks the proxy's references both
  ways, the transcript coverage against the dropped kinds listed above, that
  the raw capture is unchanged, that the second run continues the first
  without writing its nodes again, the usage history cutover, and that
  Grafana permissions are unchanged, and runs every example above.

```sh
cd packages/cliproxy-plugins && go test -race ./...
nix develop --command python3 gitops/espresso/tests/llm-conversations.py < /dev/null
nix develop --command python3 gitops/espresso/tests/ai-usage.py < /dev/null
```

## Settled questions

- **No TTL on raw.** `llm.requests` and `llm.request_items` are kept for good,
  and the canonical tables copy neither.
- **Storage.** It grows with the proxy's capture, and the PVC is grown when
  needed. Images are not moved out of items, since that would change the raw
  rows.
- **Typed prompts** (client headers that tell typed text from injected
  context) are deferred; the proxy's canonical rows can be rebuilt with them.
- **Claude Code's request logs** are mapped into their calls' context, since
  the transcripts are dropped. The Codex base instructions in `session_meta`
  are not mapped yet, and go with the drop unless that changes first.
- **The backfill runs in the cluster**, as a Job next to ClickHouse, as in
  [Backfill](#backfill); the workstation's link carries only its log.
- **The transcript import is dropped after verification**, with
  `llm.historical_usage`, as in
  [Before dropping the transcripts](#before-dropping-the-transcripts).
