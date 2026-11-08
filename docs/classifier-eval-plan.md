# Classifier Evaluation Plan

Status: Draft
Last updated: 2026-11-08
Related: [`product-spec.md`](product-spec.md) — risks R1, R2

## 1. Purpose

Before building any UI, find out whether on-device classification is accurate enough on **real self-notes** to carry the product. The thesis is that users never organize; if the classifier misfiles to-dos, the app reproduces the "lost item" problem it exists to solve.

Questions this eval answers:

1. **Tier A:** How accurate is Apple's Foundation Models framework at the v1 taxonomy on real data?
2. **Tier B:** How accurate is a deterministic + heuristic classifier (no LLM)? Is the non–Apple Intelligence experience viable?
3. **Data shape:** What's the actual content mix (tasks / links / notes), how often are deadlines present, and how common are multi-item entries? This feeds open questions in spec §11.
4. **Latency:** Is per-entry classification fast enough to feel instant, even though it's async?

## 2. Dataset

### 2.1 Source

Real self-texts from 1–5 consenting participants, target **150–300 entries total**. Start with one participant; add more to check the prompt isn't overfit to one person's writing style.

### 2.2 Privacy rules

- Participants give explicit consent and can exclude any message before it leaves their hands.
- Data stays on the evaluator's machine. **Never commit it.** `eval/data/` is gitignored.
- Delete raw exports after labeling is complete, unless the participant agrees to keep them.

### 2.3 Export options

**Option A — manual (simplest, recommended to start):** participant copies their last ~150 self-messages into a spreadsheet: one row per message, with the approximate date. Low-tech, participant-controlled, no tooling.

**Option B — Mac `chat.db` export:** Messages on macOS stores history in `~/Library/Messages/chat.db` (SQLite; the reading process needs Full Disk Access). Sketch query, run on a *copy* of the database:

```sql
SELECT
  m.ROWID                                                     AS id,
  datetime(m.date / 1000000000 + 978307200, 'unixepoch')      AS sent_at,
  m.text,
  m.attributedBody,
  m.is_from_me
FROM message m
JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
JOIN chat c               ON c.ROWID = cmj.chat_id
WHERE c.chat_identifier = '<participant own phone number or Apple ID email>'
ORDER BY m.date;
```

Caveats (verify on the actual machine):
- `date` is nanoseconds since 2001-01-01 on recent macOS. Older databases used seconds.
- On recent macOS versions `text` is often NULL. The body is in `attributedBody`, a serialized `NSAttributedString` (typedstream) blob that needs decoding.
- Self-chats may produce duplicate rows (sent and received copies). De-duplicate on text and timestamp.
- Schema is undocumented and changes between macOS releases.

Option B is useful later for a possible "import your self-thread" onboarding feature (spec §11.6). For the eval, Option A is enough.

### 2.4 Format

JSONL, one entry per line, in `eval/data/entries.jsonl`:

```json
{"id": "p1-0042", "participant": "p1", "sent_at": "2026-10-14T19:32:00", "text": "dentist thurs 3pm + ask about retainer"}
```

## 3. Labeling

### 3.1 Gold labels

Add to each entry:

| Field | Type | Definition |
|---|---|---|
| `isTodo` | Bool | The entry implies a concrete action the writer intends to take: "buy milk", "email Sarah", "dentist thurs". Implicit tasks count. Vague aspirations ("should learn piano someday") are **not** to-dos. |
| `isNote` | Bool | Information or an idea to keep that isn't an action: quotes, facts, ideas, gift ideas, names, codes. |
| `hasLink` | Bool | Contains a URL. (Sanity check for the deterministic detector.) |
| `deadline` | ISO date/datetime or null | A date or time attached to the action, resolved relative to `sent_at`. "thurs" sent on Mon 2026-10-12 → `2026-10-15`. |
| `isMultiItem` | Bool | Contains two or more separable items ("milk, eggs, call mom"). |
| `ambiguous` | Bool | The labeler genuinely can't decide. Excluded from primary metrics, reported separately. |
| `notes` | String | Optional labeler comment. |

An entry can be both `isTodo` and `isNote` (multi-label), though that should be rare. Link-only entries ("https://…" with no other text) are `isTodo=false`, `isNote=false`, `hasLink=true`.

### 3.2 Inter-rater check

A second person labels a random 30-entry subset independently. Compute agreement per field (percent agreement + Cohen's κ for `isTodo`).

- If humans agree < ~85% on `isTodo`, the category is ill-defined. Fix the definition before blaming the model. A model can't be held to a standard humans don't meet.
- Disagreements are a source of edge cases for the prompt and the labeling guide.

### 3.3 Split

Randomly split labeled entries **70% dev / 30% test**, stratified by participant. Iterate prompts and heuristics on dev only. Run test once per finalized classifier version. Report test numbers as the result.

## 4. Classifiers under test

| ID | Description |
|---|---|
| `det` | `NSDataDetector` only: links, dates. Always runs; feeds the others. |
| `heur` | `det` + rule-based to-do/note/multi-item heuristics (Tier B) |
| `fm` | `det` + `SystemLanguageModel.default` with guided generation (Tier A) |
| `fm-tag` | `det` + `SystemLanguageModel(useCase: .contentTagging)` variant, if it fits the schema. Compare against `fm`. |

### 4.1 Heuristic baseline (Tier B) — starting rules

- `isTodo` if any of:
  - starts with an imperative verb (from a curated list: buy, call, email, text, pay, book, schedule, pick up, return, send, finish, submit, renew…)
  - contains a trigger phrase ("need to", "remember to", "don't forget", "todo", "to do", "have to")
  - a date is detected **and** the text is short (< ~12 words)
- `isMultiItem` if comma- or newline-separated with ≥2 segments of ≤4 words each, or contains bullet or number markers.
- `isNote` if not `isTodo` and the text has content beyond a URL.
- `deadline` = first future date detected by `NSDataDetector` relative to `sent_at`.

Expect this to be mediocre. Its purpose is to set the floor and show what Tier B users would experience.

### 4.2 Foundation Models harness (Tier A) — sketch

Runs as a Swift command-line tool on an Apple silicon Mac with a current macOS and Apple Intelligence enabled. **Untested sketch:** written without a compiler, so check the API names against current docs.

```swift
import Foundation
import FoundationModels

@Generable
struct EntryClassification {
    @Guide(description: "True if the text implies a concrete action the writer intends to take, including implicit tasks like 'dentist thurs'. False for vague aspirations, facts, ideas, or bare links.")
    var isTodo: Bool

    @Guide(description: "True if the text is information or an idea worth keeping that is not an action.")
    var isNote: Bool

    @Guide(description: "If the action has a date or time, the resolved date as YYYY-MM-DD or YYYY-MM-DDTHH:MM, relative to the provided 'sent at' timestamp. Otherwise empty.")
    var deadline: String

    @Guide(description: "True if the text contains two or more separate items, e.g. 'milk, eggs, call mom'.")
    var isMultiItem: Bool

    @Guide(description: "A title of at most 6 words summarizing the entry.")
    var shortTitle: String
}

let instructions = """
You classify short personal notes a person sent to themselves. \
They are often terse, lowercase, and abbreviated. Classify; do not rewrite.
"""

func classify(text: String, sentAt: String, model: SystemLanguageModel) async throws -> EntryClassification {
    // Fresh session per entry: avoids context accumulation and cross-entry bias.
    let session = LanguageModelSession(model: model, instructions: instructions)
    let prompt = "Sent at: \(sentAt) (\(weekdayName(sentAt)))\nText: \(text)"
    let response = try await session.respond(to: prompt, generating: EntryClassification.self)
    return response.content
}

// main:
// 1. Check SystemLanguageModel.default.availability; abort with reason if unavailable.
// 2. Read eval/data/entries.jsonl.
// 3. For each entry: run det (NSDataDetector), then classify(); time each call.
// 4. Write eval/out/<classifier-id>-<version>.jsonl with predictions + latency_ms.
```

Notes:
- Dates are returned as strings. Pass the weekday explicitly, because small models resolve "thurs" more reliably when told what today is.
- Keep instructions short. The on-device model has a small context window, and long instructions reduce accuracy and add latency.
- Record the OS build in every output file. The system model changes with OS updates, so accuracy can shift without any code change.

### 4.3 Scoring

A small script (Python or Swift) that joins gold and predictions on `id`, excludes `ambiguous`, and reports per classifier:

- `isTodo`, `isNote`, `isMultiItem`: precision, recall, F1, confusion matrix
- `deadline`: on gold-with-deadline entries, exact-date accuracy; on gold-without-deadline entries, false-deadline rate
- `hasLink`: precision and recall (expect 1.0)
- Latency: p50 and p95 per entry
- Per-participant breakdown (checks overfitting to one writing style)
- A dump of every error for manual review

## 5. Success criteria

Initial thresholds, set by judgment rather than data. Revisit after the first participant's results.

| Metric | Tier A (`fm`) | Tier B (`heur`) | Rationale |
|---|---|---|---|
| `isTodo` recall | ≥ 0.90 | ≥ 0.75 | A missed to-do is the costliest error: the item is "lost" |
| `isTodo` precision | ≥ 0.80 | ≥ 0.70 | False to-dos clutter the view but are visible and correctable |
| `deadline` exact-date accuracy | ≥ 0.85 | ≥ 0.75 | Wrong dates produce wrong notifications |
| False-deadline rate | ≤ 0.05 | ≤ 0.05 | Spurious notifications erode trust fast |
| `hasLink` P/R | 1.0 | 1.0 | Deterministic; anything less is a bug |
| p95 latency (Mac) | informational | — | Classification is async; flag if > ~2 s |

## 6. Decision outcomes

| Result | Decision |
|---|---|
| Tier A and B both meet thresholds | Proceed to prototype |
| Tier A meets, Tier B doesn't | Proceed, but decide whether to (a) require Apple Intelligence devices, or (b) ship a Tier B experience positioned as reduced (e.g., To-dos filter labeled "suggested"). Weigh against target-user device mix from research. |
| Tier A misses on `isTodo` recall | Error analysis first: is it the prompt, the label definition, or the model? Try prompt iteration (dev set only) and `fm-tag`. If it still misses after a reasonable effort, the "user never organizes" thesis needs rethinking, e.g., a one-tap "to-do?" confirmation at capture time. |
| Humans disagree (κ low) | Redefine categories; the taxonomy is the problem, not the model |
| `isMultiItem` common (> ~15% of entries) | Resolve spec §11.1 (split vs. sub-checkboxes) before prototyping |

## 7. Deliverables

1. `eval/data/` — gitignored; labeled dataset (local only)
2. `eval/harness/` — Swift package for running the classifiers
3. `eval/score.py` (or Swift equivalent) — scoring
4. `docs/eval-results.md` — numbers, error analysis, decision. This file is committed and contains **no raw participant text** beyond minimal paraphrased examples with consent.

## 8. Estimated effort

| Step | Effort |
|---|---|
| Export + consent (1 participant) | < 1 hour |
| Labeling 150 entries + guide refinement | 2–3 hours |
| Second-rater subset | 30 min |
| Harness + heuristic baseline | 0.5–1 day |
| Scoring + error analysis | 0.5 day |
| **Total to first go/no-go** | **~2 days** |
