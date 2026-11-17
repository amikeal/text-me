# Classifier evaluation

Tools for the plan in [`docs/classifier-eval-plan.md`](../docs/classifier-eval-plan.md): measure how well
Cubby sorts real notes before trusting it.

The harness runs the same `CubbyCore` code the app ships, so the numbers describe the real product.

## 1. Prepare data

Put labeled notes in `eval/data/entries.jsonl`, one JSON object per line. `eval/data/` and `eval/out/`
are ignored by git: **never commit real notes.** See `eval/sample/entries.sample.jsonl` for the
format (those 16 entries are made up, for trying the tools).

| Field | Meaning |
|---|---|
| `id`, `participant` | Any stable identifiers |
| `sent_at` | When the note was written, local time: `2026-10-14T19:32:00` |
| `text` | The note, verbatim |
| `isTodo`, `isNote`, `hasLink`, `isMultiItem` | Gold labels (true/false) |
| `deadline` | `YYYY-MM-DD`, or `YYYY-MM-DDTHH:MM` when a time was given, or `null` |
| `ambiguous` | `true` if the labeler couldn't decide; excluded from the main numbers |

## 2. Run the classifiers (on a Mac)

```sh
cd eval/harness
swift run cubby-eval heur   ../data/entries.jsonl ../out/heur.jsonl     # built-in rules (any Mac)
swift run cubby-eval fm     ../data/entries.jsonl ../out/fm.jsonl       # Apple Intelligence
swift run cubby-eval fm-tag ../data/entries.jsonl ../out/fm-tag.jsonl   # content-tagging model
```

`fm` and `fm-tag` need an Apple silicon Mac on macOS 26 or later with Apple Intelligence turned on.

## 3. Score

```sh
python3 eval/score.py --gold eval/data/entries.jsonl --pred eval/out/heur.jsonl --pred eval/out/fm.jsonl
python3 eval/score.py --gold eval/data/entries.jsonl --pred eval/out/fm.jsonl --errors   # list every miss
```

The scorer prints precision, recall and F1 per label, deadline accuracy, the false-deadline rate,
latency, a per-participant breakdown, and a pass/fail against the thresholds in the plan
(`heur` is held to the Tier B thresholds, `fm` and `fm-tag` to Tier A). It exits non-zero if any
threshold is missed.

`--errors` prints note text. Keep that output out of anything you commit or share.
