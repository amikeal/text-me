# text-me (working name)

An iPhone app for frictionless capture: one chat-style input, everything lands in a single timeline, and on-device AI classifies entries (to-dos, links, notes, deadlines) into filter views. The user never organizes. The app also resurfaces things on its own (deadline reminders, weekly digest). No backend; sync via the user's iCloud.

Inspired by the common habit of texting yourself as a scratchpad.

## Status

Pre-build. Validating the concept and classifier accuracy before writing app code.

## Docs

- [Product spec](docs/product-spec.md): problem, principles, UX, classification design, architecture, MVP scope, risks, open questions
- [Classifier eval plan](docs/classifier-eval-plan.md): how to test on-device classification against real self-notes before building UI

## Next steps

1. User research: review real self-text threads with 1–5 participants (spec §10)
2. Build labeled dataset and run the classifier eval (eval plan)
3. Go/no-go on prototype
