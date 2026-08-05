---
name: slack
description: Read, search, and send Slack messages via the `slack` CLI. Use whenever the user asks about Slack messages, channels, threads, DMs, catching up on unreads, finding a past discussion or decision, or sending/replying to a Slack message.
---

# Slack CLI

A `slack` command is on PATH. Auth is already configured (user token); you act as the user. Run `slack help` for full usage.

## Commands

```
slack search <query> [--count N]                 # message search, supports in:#chan from:@user after:2026-08-01
slack history <#chan|@user|ID> [--since 2d] [--limit N]
slack thread <permalink>                         # or: slack thread <channel> <ts>
slack unreads                                    # unread messages across channels/DMs
slack send <#chan|@user|ID> <text> [--thread <ts>]
slack react <permalink> <emoji-name>
slack whois <@user>
slack channels [--refresh]
slack file <url_private> [outfile]               # download an attachment
```

Messages print as `[ts] author: text  <permalink>`. Use the `ts` for `--thread` replies and the permalink when citing messages to the user. `⏎` marks line breaks within a message.

## Workflows

- **Find a discussion/decision**: `slack search`, narrowing with `in:#channel`, `from:@user`, `after:`/`before:` operators inside the query. If a hit has `[thread: N replies]`, read the full thread before summarizing — the decision is usually in the replies.
- **Catch up**: `slack unreads`, then summarize per channel with permalinks so the user can jump in. It only covers conversations the user is a member of.
- **Read a pasted link**: any `https://<team>.slack.com/archives/...` permalink goes straight into `slack thread <link>`.
- **Names not resolving**: caches are refreshed daily; run `slack channels --refresh` after workspace changes.

## Sending rules

- Always show the user the exact draft text and destination and get their confirmation before running `slack send`, unless they already dictated the exact message in this conversation.
- Reply in threads (`--thread <ts>`) rather than posting to the channel when responding to an existing message.
- Format with Slack mrkdwn: `*bold*`, `_italic_`, `` `code` ``, `> quote`, `<url|label>`. No markdown headers or `**double asterisks**`.
- Never use `@channel`, `@here`, or `@everyone`.
