#!/usr/bin/env python3
"""Scores classifier predictions against hand-labeled notes.

    python3 eval/score.py --gold eval/data/entries.jsonl --pred eval/out/heur.jsonl [--pred ...] [--errors]

Gold and prediction files are JSON Lines, joined on "id". Entries the labeler marked
"ambiguous" are left out of the main numbers and counted separately.

Exit status is 1 if any prediction file misses a threshold from docs/classifier-eval-plan.md.
"""
import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

BOOLEAN_LABELS = ["isTodo", "isNote", "isMultiItem", "hasLink"]

# From docs/classifier-eval-plan.md section 5. (metric, comparison, value)
TIER_A = [
    ("isTodo recall", ">=", 0.90),
    ("isTodo precision", ">=", 0.80),
    ("deadline date accuracy", ">=", 0.85),
    ("false-deadline rate", "<=", 0.05),
    ("hasLink precision", ">=", 1.0),
    ("hasLink recall", ">=", 1.0),
]
TIER_B = [
    ("isTodo recall", ">=", 0.75),
    ("isTodo precision", ">=", 0.70),
    ("deadline date accuracy", ">=", 0.75),
    ("false-deadline rate", "<=", 0.05),
    ("hasLink precision", ">=", 1.0),
    ("hasLink recall", ">=", 1.0),
]


def read_jsonl(path: Path) -> list[dict]:
    rows = []
    with path.open(encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as error:
                sys.exit(f"{path}:{number}: not valid JSON ({error})")
    return rows


def ratio(numerator: int, denominator: int):
    """None when there is nothing to measure, so an empty class never reads as 0% or 100%."""
    return numerator / denominator if denominator else None


def confusion(pairs: list[tuple[bool, bool]]) -> dict:
    tp = sum(1 for gold, pred in pairs if gold and pred)
    fp = sum(1 for gold, pred in pairs if not gold and pred)
    fn = sum(1 for gold, pred in pairs if gold and not pred)
    tn = sum(1 for gold, pred in pairs if not gold and not pred)
    precision = ratio(tp, tp + fp)
    recall = ratio(tp, tp + fn)
    f1 = None
    if precision is not None and recall is not None and precision + recall > 0:
        f1 = 2 * precision * recall / (precision + recall)
    return {"tp": tp, "fp": fp, "fn": fn, "tn": tn, "precision": precision, "recall": recall, "f1": f1}


def date_part(value):
    return value[:10] if value else None


def time_part(value):
    return value[11:16] if value and len(value) >= 16 else None


def percentile(values: list[float], fraction: float):
    if not values:
        return None
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round(fraction * (len(ordered) - 1))))
    return ordered[index]


def show(value, digits: int = 2) -> str:
    return "  n/a" if value is None else f"{value:.{digits}f}"


def score(gold_rows: list[dict], pred_rows: list[dict]) -> dict:
    predictions = {row["id"]: row for row in pred_rows}
    scored = [row for row in gold_rows if not row.get("ambiguous")]
    missing = [row["id"] for row in scored if row["id"] not in predictions]
    scored = [row for row in scored if row["id"] in predictions]

    metrics: dict = {}
    labels = {}
    for label in BOOLEAN_LABELS:
        pairs = [(bool(row.get(label)), bool(predictions[row["id"]].get(label))) for row in scored]
        labels[label] = confusion(pairs)
        metrics[f"{label} precision"] = labels[label]["precision"]
        metrics[f"{label} recall"] = labels[label]["recall"]

    with_deadline = [row for row in scored if row.get("deadline")]
    without_deadline = [row for row in scored if not row.get("deadline")]
    date_hits = sum(
        1 for row in with_deadline
        if date_part(predictions[row["id"]].get("deadline")) == date_part(row["deadline"])
    )
    timed = [row for row in with_deadline if time_part(row["deadline"])]
    time_hits = sum(
        1 for row in timed
        if predictions[row["id"]].get("deadline", "")[:16] == row["deadline"][:16]
    )
    false_deadlines = sum(1 for row in without_deadline if predictions[row["id"]].get("deadline"))
    metrics["deadline date accuracy"] = ratio(date_hits, len(with_deadline))
    metrics["deadline date+time accuracy"] = ratio(time_hits, len(timed))
    metrics["false-deadline rate"] = ratio(false_deadlines, len(without_deadline))

    latencies = [
        float(predictions[row["id"]]["latency_ms"])
        for row in scored
        if predictions[row["id"]].get("latency_ms") is not None
    ]

    by_participant = defaultdict(list)
    for row in scored:
        by_participant[row.get("participant", "?")].append(
            (bool(row.get("isTodo")), bool(predictions[row["id"]].get("isTodo")))
        )

    errors = []
    for row in scored:
        pred = predictions[row["id"]]
        wrong = [label for label in BOOLEAN_LABELS if bool(row.get(label)) != bool(pred.get(label))]
        if date_part(row.get("deadline")) != date_part(pred.get("deadline")):
            wrong.append("deadline")
        elif time_part(row.get("deadline")) and (pred.get("deadline") or "")[:16] != row["deadline"][:16]:
            wrong.append("deadline time")
        if wrong:
            errors.append({"id": row["id"], "wrong": wrong, "text": row.get("text", ""), "gold": row, "pred": pred})

    return {
        "scored": len(scored),
        "ambiguous": sum(1 for row in gold_rows if row.get("ambiguous")),
        "missing": missing,
        "model_failures": sum(1 for row in scored if predictions[row["id"]].get("error")),
        "labels": labels,
        "metrics": metrics,
        "deadline_counts": (len(with_deadline), len(timed), len(without_deadline)),
        "latency": (percentile(latencies, 0.5), percentile(latencies, 0.95)),
        "by_participant": {name: confusion(pairs) for name, pairs in sorted(by_participant.items())},
        "multi_item_share": ratio(sum(1 for row in scored if row.get("isMultiItem")), len(scored)),
        "errors": errors,
    }


def check(metrics: dict, thresholds: list) -> list[tuple[str, str, float, object, bool]]:
    results = []
    for name, comparison, target in thresholds:
        value = metrics.get(name)
        if value is None:
            passed = None  # nothing to measure
        elif comparison == ">=":
            passed = value >= target
        else:
            passed = value <= target
        results.append((name, comparison, target, value, passed))
    return results


def report(path: Path, result: dict, show_errors: bool) -> bool:
    classifier = path.stem
    tier_name, thresholds = ("Tier B", TIER_B) if classifier.startswith("heur") else ("Tier A", TIER_A)

    print(f"\n=== {path} ===")
    print(f"scored {result['scored']} entries ({result['ambiguous']} ambiguous left out)")
    if result["missing"]:
        print(f"WARNING: {len(result['missing'])} gold entries have no prediction: {', '.join(result['missing'][:5])}")
    if result["model_failures"]:
        print(f"note: the model failed on {result['model_failures']} entries; the rule-based answer was used")

    print(f"\n{'label':<14}{'prec':>7}{'recall':>8}{'f1':>7}   tp  fp  fn  tn")
    for label, c in result["labels"].items():
        print(f"{label:<14}{show(c['precision']):>7}{show(c['recall']):>8}{show(c['f1']):>7}"
              f"  {c['tp']:>3} {c['fp']:>3} {c['fn']:>3} {c['tn']:>3}")

    dated, timed, undated = result["deadline_counts"]
    m = result["metrics"]
    print(f"\ndeadline date accuracy       {show(m['deadline date accuracy'])}  (of {dated} entries with a deadline)")
    print(f"deadline date+time accuracy  {show(m['deadline date+time accuracy'])}  (of {timed} with a time)")
    print(f"false-deadline rate          {show(m['false-deadline rate'])}  (of {undated} entries without one)")

    p50, p95 = result["latency"]
    print(f"\nlatency ms: p50 {show(p50, 1)}  p95 {show(p95, 1)}")
    print(f"multi-item entries: {show(result['multi_item_share'])} of gold"
          + ("  (above 0.15: settle spec section 11.1 before prototyping)" if (result["multi_item_share"] or 0) > 0.15 else ""))

    if len(result["by_participant"]) > 1:
        print("\nisTodo by participant:")
        for name, c in result["by_participant"].items():
            print(f"  {name:<12} precision {show(c['precision'])}  recall {show(c['recall'])}  (n={c['tp'] + c['fp'] + c['fn'] + c['tn']})")

    print(f"\nThresholds ({tier_name}):")
    all_passed = True
    for name, comparison, target, value, passed in check(m, thresholds):
        if passed is None:
            verdict = "n/a "
        elif passed:
            verdict = "PASS"
        else:
            verdict = "FAIL"
            all_passed = False
        print(f"  {verdict}  {name:<26} {show(value)}  (needs {comparison} {target:.2f})")

    if show_errors:
        print(f"\nErrors ({len(result['errors'])}):")
        for error in result["errors"]:
            gold, pred = error["gold"], error["pred"]
            print(f"  [{error['id']}] wrong: {', '.join(error['wrong'])}")
            print(f"      text: {error['text']!r}")
            print(f"      gold: todo={bool(gold.get('isTodo'))} note={bool(gold.get('isNote'))} "
                  f"multi={bool(gold.get('isMultiItem'))} deadline={gold.get('deadline')}")
            print(f"      pred: todo={bool(pred.get('isTodo'))} note={bool(pred.get('isNote'))} "
                  f"multi={bool(pred.get('isMultiItem'))} deadline={pred.get('deadline')}")
    else:
        print(f"\n{len(result['errors'])} entries had at least one wrong field (rerun with --errors to list them)")
    return all_passed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--gold", required=True, type=Path, help="labeled entries (JSON Lines)")
    parser.add_argument("--pred", required=True, type=Path, action="append", help="predictions from cubby-eval; repeatable")
    parser.add_argument("--errors", action="store_true", help="list every entry with a wrong field (prints note text)")
    args = parser.parse_args()

    gold = read_jsonl(args.gold)
    if not gold:
        sys.exit(f"{args.gold}: no entries")

    everything_passed = True
    for path in args.pred:
        result = score(gold, read_jsonl(path))
        if result["scored"] == 0:
            print(f"\n=== {path} ===\nno predictions match the gold entries")
            everything_passed = False
            continue
        everything_passed = report(path, result, args.errors) and everything_passed
    return 0 if everything_passed else 1


if __name__ == "__main__":
    sys.exit(main())
