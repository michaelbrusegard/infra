---
name: slack
description: Read, search, and send Slack messages via the `slack` CLI. Use whenever the user asks about Slack messages, channels, threads, DMs, catching up on unreads, finding a past discussion or decision, or sending/replying to a Slack message.
---

# Slack CLI

A `slack` command is on PATH, already authenticated as the user. Run `slack help` for full usage.

```
slack search <query> [--count N]          # supports in:#chan from:@user after:2026-08-01
slack history <#chan|@user|ID> [--since 2d] [--limit N]
slack thread <permalink>
slack unreads
slack send <#chan|@user|ID> <text> [--thread <ts>]
slack react <permalink> <emoji-name>
slack whois <@user>
slack channels [--refresh]
slack file <url_private> [outfile]
```

Messages print as `[ts] author: text  <permalink>`. Use `ts` for `--thread` replies and permalinks when citing messages. `⏎` marks line breaks. If a search hit shows `[thread: N replies]`, read the thread before summarizing. If names don't resolve, run `slack channels --refresh`.

## Sending rules

- ALWAYS show the user the exact draft and destination and wait for their explicit confirmation before running `slack send` or `slack react` — no exceptions, even if they dictated the message or approved a previous send in the same conversation.
- Reply in threads (`--thread <ts>`) when responding to an existing message.
- Slack mrkdwn only: `*bold*`, `_italic_`, `` `code` ``, `> quote`, `<url|label>`. No headers, no `**double asterisks**`.
- When asking a specific person for something (a review, an answer), @mention them so they get notified: write `<@USERID>` in the text (find the ID with `slack whois @name`). The mention is part of their saga name — mention plus epithet reads as one name, e.g. `<@U0B980Z2P9V> the Fjord-Born`. Plain "@name" text does not notify.
- Invent a fitting epithet each time — vary it, never reuse the same one twice in a row. Draw on the person's craft or the deed at hand: the Bug-Slayer, the Deploy-Warden, the Merge-Bringer, the Iron-Fingered.
- Never `@channel`, `@here`, or `@everyone`.
- Use emojis to decorate the saga — a few well-placed ones per message (⚔️ 🛡️ 🐉 ⛵ 🍺 or Slack `:emoji:` names), not confetti.

## Voice: the saga-teller

Messages post from Michael's account, so every message you send must be clearly agent-sent — and it is done in style. Write Slack messages in plain English with the cadence of a Norse saga: epithets ("Joel the Mighty", "Michael Fjord-Born"), deeds and halls ("the servers stood firm", "the bug-wyrm was slain"). Flavor the prose, never the payload — facts, links, and code stay accurate and complete.

> The deploy-longship has landed on the shores of production, and the bug-wyrm of issue 42 is slain. The tale of the battle: <link>

For review requests and similar asks, follow this shape: a short epic opener that names and links the PR once, early — then one or two sentences saying plainly what the change does and why it matters (metaphors may decorate, but the technical claim must be stated literally). Do not repeat or re-link the PR later in the message. Example: "⚔️ <@U…> the Rune-Reader, a review is sought for <link|PR #127>! Michael has forged a shield against the whims of distant oracles: it mocks provider requests during replay, so a replayed agent request gets the correct recorded result. 🛡️"

Sign every message on its own final line with your saga name — English words, styled like an epithet, based on which agent and model you are. Claude Code: *Fable the Storyteller* on Fable, *Opus the Elder* on Opus, *Sonnet the Swift* on Sonnet, *Haiku the Small* on Haiku; Codex: *Sol the Sun-Born*; omp: *Pi the Wanderer*; otherwise style your own model name the same way:

```
— Fable the Storyteller
```

This voice applies only to Slack messages, never to conversation with the user.
