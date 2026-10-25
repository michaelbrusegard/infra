---
name: unslop
description: Cut AI tells from any writing while preserving meaning and the intended tone. Apply to user-facing prose, messages, comments, PR text, documentation, and decision logs.
---

# Unslop

Edit text to remove AI patterns and add human voice.

## Process

1. Scan for the patterns below.
2. Rewrite while preserving meaning and matching the intended tone.
3. Add soul.
4. Ask, "What makes this obviously AI-generated?" Fix the remaining tells.
5. Preserve any provenance line required by the global agent instructions.

## Add soul

Removing patterns is only half the job. Sterile, voiceless writing is just as
obvious.

- Have opinions. React to facts instead of neutrally listing pros and cons.
- Vary rhythm. Short sentences, then longer ones that take their time.
- Acknowledge complexity. "Impressive but also kind of unsettling" is better
  than "impressive."
- Use "I" when it fits. First person is not unprofessional.
- Let some mess in. Perfect structure looks machine-made.
- Be specific. Name the mechanism, detail, example, or number that matters.

## Patterns to detect and fix

### Content

1. **Puffery.** Cut phrases such as "pivotal moment", "testament to",
   "evolving landscape", "setting the stage for", and "indelible mark". State
   what happened.
2. **Name-dropping.** Do not list sources without context. Pick the relevant
   source and say what it contributed.
3. **Superficial `-ing` phrases.** Delete or substantiate "highlighting",
   "ensuring", "reflecting", "showcasing", and "fostering" clauses.
4. **Promotional language.** Replace "vibrant", "breathtaking",
   "groundbreaking", "renowned", and similar copy with neutral facts.
5. **Vague attributions.** Name the source behind "experts believe" or delete
   the claim.
6. **Formulaic challenges.** Replace "despite challenges, it continues to
   thrive" with the actual constraint and result.

### Language

7. **AI vocabulary.** Replace words such as additionally, crucial, delve,
   enhance, foster, intricate, landscape, pivotal, showcase, tapestry,
   testament, underscore, and vibrant with plain words.
8. **Fancy ways to say `is`.** Replace "serves as", "stands as", "boasts", and
   "features" with `is` or `has` when that is what they mean.
9. **`Not just X, but Y`.** State the point directly.
10. **Forced groups of three.** Use the natural number of items.
11. **Synonym cycling.** Pick one accurate term and repeat it.
12. **False ranges.** Do not write "from X to Y" unless X and Y form a real
    scale.

### Style

13. **Dash crutches.** Avoid em dashes and substitutes. Use a period or comma.
14. **Colon overuse.** Use colons before real lists or examples, not as a
    generic mid-sentence connector.
15. **Boldface overuse.** Do not bold every noun, acronym, or label.
16. **Inline-header lists.** Avoid bullets whose bold label merely repeats the
    sentence. A short lead-in is fine when the following detail is new.
17. **Title case headings.** Use sentence case.
18. **Decorative emoji.** Remove it from headings and bullets unless the chosen
    format depends on it.
19. **Curly quotes.** Use straight quotes.

### Communication artifacts

20. **Chatbot phrases.** Remove "I hope this helps", "let me know if",
    "certainly", and similar filler.
21. **Cutoff disclaimers.** Find the missing source or omit the unsupported
    claim.
22. **Sycophancy.** Respond directly instead of praising the question or
    reflexively agreeing.

### Filler

23. **Filler phrases.** Use "to" instead of "in order to" and "because"
    instead of "due to the fact that". Delete "it is important to note that".
24. **Excessive hedging.** Reduce stacked qualifiers to the one warranted level
    of uncertainty.
25. **Generic conclusions.** End with the specific result, decision, or next
    step.

### Jargon

26. **Abstract metaphor nouns.** Prefer the concrete word over substrate,
    wedge, vector, locus, nexus, primitive, harness, surface, bedrock,
    scaffolding, modality, paradigm, gold-plating, ratchet, endgame, north star,
    and flywheel when those words hide the actual mechanism.

### Plain speech

27. **Say what it does, not how it feels.** Name the instruction, fact,
    mechanism, or number. If the sentence could describe any project unchanged,
    it probably says nothing.
28. **Split dense sentences.** Prefer one idea per sentence when the reader
    would otherwise need to backtrack.
29. **Use active voice.** Name the actor when it matters. Passive voice is fine
    when the actor is unknown or irrelevant.
30. **Cut weak adverbs.** Use a stronger verb or a measured result.
31. **Prefer the plain word.** Use `use`, `help`, `many`, and `if` instead of
    `utilize`, `facilitate`, `numerous`, and `in the event that`.
