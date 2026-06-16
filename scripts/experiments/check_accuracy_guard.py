#!/usr/bin/env python3
"""Accuracy guard for performance work, run through the *production* worker path.

Runs every fixture in fixtures/ocr/manifest.json through worker.handle_request
(the split detect → pooled-recognize path the app actually uses) and reports
per-fixture CER. Save a baseline once, then compare candidate runs against it:

  .venv-ocr/bin/python scripts/experiments/check_accuracy_guard.py --label acc-baseline
  .venv-ocr/bin/python scripts/experiments/check_accuracy_guard.py --label candidate --compare acc-baseline

A candidate passes only if no fixture's CER got worse than the baseline.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VENV_PYTHON = ROOT / ".venv-ocr" / "bin" / "python"
if VENV_PYTHON.exists() and Path(sys.executable).resolve() != VENV_PYTHON.resolve():
    os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), *sys.argv])

sys.path.insert(0, str(ROOT / "sidecar"))

ARTIFACT_DIR = ROOT / "artifacts" / "stage-bench"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", default="acc-run")
    parser.add_argument("--compare", default=None, help="baseline label to compare against")
    args = parser.parse_args()

    from screen_ocr_sidecar import worker
    from screen_ocr_sidecar.metrics import character_error_rate

    manifest = json.loads((ROOT / "fixtures" / "ocr" / "manifest.json").read_text(encoding="utf-8"))
    engine = worker.load_ocr()

    results: dict[str, dict] = {}
    for fixture in manifest["fixtures"]:
        payload = {"id": fixture["id"], "image_path": str(ROOT / fixture["path"])}
        response = worker.handle_request(payload, engine)
        if not response.get("ok"):
            print(f"FAIL {fixture['id']}: {response.get('error')}", file=sys.stderr)
            return 1
        cer = character_error_rate(fixture["expected_text"], response["text"])
        results[fixture["id"]] = {"cer": round(cer, 4), "text": response["text"]}

    engine.rec_pool.close()

    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    out = ARTIFACT_DIR / f"{args.label}.json"
    out.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"=== accuracy guard [{args.label}] ===")
    for fixture_id, entry in results.items():
        print(f"  {fixture_id:<24} cer={entry['cer']}")

    if args.compare:
        baseline = json.loads((ARTIFACT_DIR / f"{args.compare}.json").read_text(encoding="utf-8"))
        worse = {
            fixture_id: (baseline[fixture_id]["cer"], entry["cer"])
            for fixture_id, entry in results.items()
            if entry["cer"] > baseline[fixture_id]["cer"]
        }
        if worse:
            print("\nREGRESSED vs", args.compare)
            for fixture_id, (before, after) in worse.items():
                print(f"  {fixture_id}: {before} -> {after}")
            return 1
        print(f"\nPASS: no fixture regressed vs {args.compare}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
