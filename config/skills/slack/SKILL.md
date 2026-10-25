---
name: slack
description: Read, search, summarize, draft, and send Slack messages with the authenticated `slack` CLI. Use whenever the user mentions Slack or pastes a Slack permalink, or asks about a channel, thread, DM, group DM, unreads, alerts, a bot message, a file or screenshot, a canvas, a Slack List, a reaction, a mention, a past discussion or decision, or posting, replying, scheduling, editing, or uploading to Slack.
---

# Slack

The `slack` command is on `PATH`, authenticated as Michael with a user token.
Run `slack help` for the command list and `slack help <command>` (or
`<command> --help`) for flags. Do not guess flags.

Most used:

```text
slack thread <permalink>                 whole thread, even from a reply link
slack history <#chan|@user> --since 1d   oldest first; --all, --replies, --until
slack search '<query>' [--count N]       in:#chan from:@user after:YYYY-MM-DD ...
slack unreads [--channel C] [--limit N]
slack file <F-ID|permalink>              text prints; other files save to a path
slack user <name|email>                  prints the <@U...> mention to use
slack send <dest> --file F --dry-run     then the same without --dry-run
```

## Reading

- Output is one message per line: `[ts time] author: text [markers]  <permalink>`.
  `⏎` is a line break. `--long` prints multi-line bodies.
- Add `--json` to any read command for normalized JSON (rendered `text`,
  `author`, `files`, `reactions`, `reply_count`, `permalink`). Prefer it over
  parsing text.
- Bot and alert content (CloudWatch, Amazon Q, Linear, and others) comes from
  blocks and attachments, and it is already in `text`. Files show as
  `[file F… "name" mimetype url]`. Fetch them with `slack file <F-ID>`. For
  images, read the saved path. Canvases: `slack canvas read <ID>`.
- A reply permalink (`?thread_ts=`) opens the whole thread. `»` (JSON
  `"linked": true`) marks the message the link pointed at. Read the thread
  before you summarize a message that has replies.
- Names resolve fuzzily and case-insensitively. When a result is ambiguous,
  the CLI lists the candidates; pick one by ID.
- `slack unreads` omits unread thread replies. Slack has no public API for
  them. Do not use `--mark` unless Michael asks to mark messages read.
- For anything without a command, use `slack api <method> key=value ...`. It
  prints the JSON response. Never read the token file, and never call Slack with
  curl. `slack api` can also write. Use write methods only as the send rules
  below allow, and try `--dry-run` first.
- On `missing_scope`, tell Michael which scope the error names. He must add it
  and reinstall the slack-cli app from `packages/slack-cli/manifest.json`. Do
  not work around it.

When summarizing:

1. Narrow the channel, people, and time window before broad searches.
2. Separate decisions, proposals, open questions, and your own inference.
3. Include permalinks for claims Michael may want to check.
4. Leave out unrelated private messages and secrets.

## Drafting

Use Slack mrkdwn: `*bold*`, `_italic_`, backticks, `> quote`, `<url|label>`.
Do not use `**`, Markdown headings, or `[label](url)`. To notify someone, use
`<@USERID>` from `slack user <name>`; plain `@name` notifies nobody. Follow
Michael's writing style from the global instructions.

Attribution follows the global conversational provenance rule. End the message
with this footer:

```text
<message>

---
MODEL-SLUG · responding on behalf of Michael
```

- MODEL-SLUG is the exact model ID that your runtime exposes. Examples are the
  model ID in your system prompt, or Pi's `PI_MODEL`. Drop any gateway or
  provider prefix: `cliproxyapi/claude-opus-5-5` becomes `claude-opus-5-5`.
  Never guess a slug. If the runtime exposes none, use `UNKNOWN-MODEL`.
- Leave the footer off only when Michael asks for that message to have no
  attribution.
- When Michael wants a draft to send himself, give him the text and do not send
  it.

## Sending safely

Writes include `send`, `schedule`, `edit`, `delete`, `react`, `upload`,
`create-channel`, `open`, `invite`, canvas and list writes, `unreads --mark`,
and write methods through `slack api`.

- Only an explicit request to perform that exact action authorizes a write. A
  request to draft is not authorization.
- If the destination, thread, or content is materially ambiguous, show the
  complete draft, with its footer, and resolve the ambiguity first.
- Reply in the thread when you are responding to an existing message. Use
  `--thread <permalink>`; a reply link posts into its parent thread. Add
  `--broadcast` only when Michael asks for the reply to go to the channel too.
- Never use `@here`, `@channel`, `@everyone`, or a usergroup mention unless
  Michael explicitly confirms that exact notification. The CLI refuses the
  first three without `--allow-broadcast`.
- Write multi-line messages to a file and pass `--file`. That avoids quoting
  accidents.
- Run with `--dry-run` first. It sends nothing and prints the exact payload,
  destination, thread, resolved mentions, and warnings, such as a missing
  footer or `**`. Check them, then run the same command without `--dry-run`.
- After sending, report the permalink that the CLI prints.
