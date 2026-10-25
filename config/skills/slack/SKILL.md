---
name: slack
description: Read, search, summarize, draft, and send Slack messages with the authenticated `slack` CLI. Use whenever the user asks about Slack channels, threads, DMs, unreads, a past discussion or decision, or a Slack message or reaction.
---

# Slack

A `slack` command is on `PATH` and authenticated as the user. Run `slack help`
when a flag or subcommand is unclear.

```text
slack search <query> [--count N]
slack history <#chan|@user|ID> [--since 2d] [--limit N]
slack thread <permalink>
slack unreads
slack send <#chan|@user|ID> <text> [--thread <ts>]
slack react <permalink> <emoji-name>
slack whois <@user>
slack channels [--refresh]
slack file <url_private> [outfile]
```

Search supports Slack filters such as `in:#channel`, `from:@user`, and
`after:2026-08-01`. Output has the form `[ts] author: text <permalink>`; `⏎`
marks a line break. Read the full thread when a result reports replies. Refresh
channels if a name does not resolve.

## Read and summarize

1. Narrow the channel, people, and time window before broad searches.
2. Read linked threads rather than treating the parent message as the complete
   discussion.
3. Distinguish decisions, proposals, unresolved questions, and your inference.
4. Include permalinks for claims the user may need to verify.
5. Do not expose unrelated private messages or secrets in summaries.

## Draft and format

Follow the writing style and conversational provenance rules in the global
agent instructions. Treat the provenance header as part of the Slack message.

Use Slack mrkdwn: `*bold*`, `_italic_`, backticks for code, `> quote`, and
`<url|label>`. Do not use Markdown headings or double-asterisk bold.

When asking a specific person for something, resolve their user ID with
`slack whois` and mention `<@USERID>`. Never notify `@channel`, `@here`, or
`@everyone` unless Michael explicitly asks and confirms that exact notification.

## Send safely

- An explicit request to send a message or add a reaction authorizes that exact
  action. A request to draft does not.
- If the destination, thread, or intended content is materially ambiguous, show
  the complete attributed draft and resolve the ambiguity before sending.
- Reply with `--thread <ts>` when responding to an existing message.
- Immediately before sending, verify the destination, thread, mentions, links,
  and required provenance.
- Report the resulting permalink after a successful send.
