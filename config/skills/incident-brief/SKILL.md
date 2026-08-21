---
name: incident-brief
description: Turn incident evidence into a concise internal update, handoff, or post-incident brief. Use when the user asks to summarize an outage, prepare an incident update, write a handoff, or communicate impact, evidence, mitigation, and next steps.
---

# Incident Brief

Communicate what responders know and need next. Use `diagnose` first when the
evidence has not yet been gathered.

## Build the brief

1. Establish the audience, incident state, affected systems and users, start and
   end time, severity if assigned, and the desired decision or action.
2. Reconcile logs, metrics, deploys, tickets, and responder notes into a UTC
   timeline. Keep observed facts separate from hypotheses.
3. State impact concretely. Avoid reassuring language unsupported by data.
4. Describe mitigation and current state, including what has and has not been
   verified.
5. Name the leading cause with confidence only when evidence supports it.
6. Assign follow-ups only when an owner and expected outcome are known. Separate
   immediate containment, root-cause work, and prevention.
7. Remove secrets, credentials, private customer data, and unnecessary blame.

## Default structure

```md
Status: [investigating | mitigated | resolved]
Impact: [who and what]
Current state: [observable state]
Timeline: [material events in UTC]
Evidence: [facts and links]
Cause: [confirmed or leading hypothesis with confidence]
Actions: [containment and next steps with owners]
Unknowns: [remaining gaps]
```

Apply the conversational or durable-artifact provenance rule from the global
agent instructions based on where the brief will be published. Verify it before
publishing.
