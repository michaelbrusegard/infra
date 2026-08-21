# CONTEXT.md format

## Structure

```md
# {Context name}

{One or two sentences describing what this context is and why it exists.}

## Language

**Order**:
{A one- or two-sentence definition.}
_Avoid_: Purchase, transaction

**Invoice**:
A request for payment sent to a customer after delivery.
_Avoid_: Bill, payment request
```

## Rules

- Be opinionated. Pick the best canonical term and put alternatives under
  `_Avoid_`.
- Keep definitions to one or two sentences. Define what a concept is, not what
  its implementation does.
- Include only terms specific to this domain. General programming concepts do
  not belong.
- Add subheadings when natural clusters emerge. Otherwise keep one flat list.

## Single and multiple contexts

A single-context repository uses one `CONTEXT.md` at its root.

A multi-context repository uses a root `CONTEXT-MAP.md`:

```md
# Context map

## Contexts

- [Ordering](./src/ordering/CONTEXT.md): receives and tracks customer orders
- [Billing](./src/billing/CONTEXT.md): generates invoices and processes payments

## Relationships

- **Ordering -> Billing**: Ordering emits `OrderPlaced`; Billing consumes it.
```

When `CONTEXT-MAP.md` exists, use it to resolve the active context. If only a
root `CONTEXT.md` exists, treat the repository as single-context. If neither
exists, create a root `CONTEXT.md` lazily when the first term is resolved.
