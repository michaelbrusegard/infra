---
name: grill
description: Grill the user relentlessly about a plan, decision, or idea. Use only when the user explicitly asks to grill, interrogate, challenge, or pressure-test it.
---

# Grill

Interview the user relentlessly until you reach a shared understanding. Map the
subject as a **design tree**. Every decision branches into the decisions that
depend on it.

Work the tree in **rounds**. The **frontier** is every decision whose
prerequisites are settled, meaning the questions you can ask now without
guessing at answers you have not heard. Ask the whole frontier in one round.
Number every question and give your recommended answer. Then wait for the user
before computing the next frontier.

Format a round like this:

```md
❓ **Q1 - <question title>.** <Question body, choices, and relevant tradeoffs.>

➡️ <Recommended answer and why.>

---

❓ **Q2 - <question title>.** <Question body, choices, and relevant tradeoffs.>

➡️ <Recommended answer and why.>
```

Each answer reshapes the tree. Settled decisions push the frontier outward and
unblock questions that depend on them. A question whose answer depends on
another open question belongs to a later round.

Finding facts is the agent's job. Use the repository, available tools, and
authorized research rather than asking the user for information that can be
looked up. When the harness permits parallel research, do it without blocking
unrelated frontier questions. Decisions belong to the user. Put each decision
to them and wait.

The session ends when the frontier is empty. Every material branch has been
visited and nothing remains silently assumed. Summarize the resulting design
tree, then wait for the user to confirm shared understanding before acting on
it.
