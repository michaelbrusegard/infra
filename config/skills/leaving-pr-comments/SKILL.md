---
name: leaving-pr-comments
description: Use whenever leaving comments on GitHub.
---

# Leaving PR Comments

End every agent-authored comment left on the user's behalf with the
conversational provenance footer from the global agent instructions:

```md
Actual comment starts here.

---
<model-slug> · responding on behalf of <user>
```

Use the exact model slug the runtime exposes, and the user's name. If the
runtime does not expose a model, use `UNKNOWN-MODEL`. Do not guess.

Skip the footer when the user asked for that comment to have no attribution,
or asked to post text verbatim without it.

Before posting, check the entire comment, including quoted text and
attachments, for secrets and private details.

Keep exactly one footer, at the very bottom. Do not add a heading, signature,
or second attribution.

Apply this format to top-level PR comments, inline review comments, replies to
bots or reviewers, and written explanations used before resolving or
dismissing feedback. Do not add it to PR descriptions, which use the
description provenance line, or to commit messages.

Write the comment itself in a direct style:

- Lead with the conclusion.
- Cite the relevant code, behavior, check, or reproduction.
- Keep it concise and avoid filler, canned thanks, or status narration.
- Distinguish verified facts from judgment.

Preview the final Markdown before posting so the rule and blank lines render as
shown. After posting, verify that GitHub returned the comment or review URL.
Resolve a review thread only after its response was posted successfully.
