#!/usr/bin/env python3
"""Measure the production worker path (handle_request) on a real capture image.

Prints worker init time, warm e2e medians, and the diag stage decomposition so a
real-world slow capture can be attributed to cold start vs. warm pipeline stages.

Usage:
  .venv-ocr/bin/python scripts/experiments/bench_real_capture.py IMAGE [--repeats 3] [--label real]
"""
from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VENV_PYTHON = ROOT / ".venv-ocr" / "bin" / "python"
if VENV_PYTHON.exists() and Path(sys.executable).resolve() != VENV_PYTHON.resolve():
    os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), *sys.argv])

sys.path.insert(0, str(ROOT / "sidecar"))
sys.path.insert(0, str(ROOT / "scripts" / "experiments"))

ARTIFACT_DIR = ROOT / "artifacts" / "stage-bench"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--label", default="real-capture")
    args = parser.parse_args()

    from bench_stage import diag_run

    from screen_ocr_sidecar import worker

    t0 = time.perf_counter()
    engine = worker.load_ocr()
    init_s = time.perf_counter() - t0

    payload = {"id": "bench-real", "image_path": str(args.image)}
    # Warmup request (first-touch effects).
    first = worker.handle_request(payload, engine)
    first_ms = first.get("request_elapsed_ms")

    e2e: list[float] = []
    text = ""
    line_count = 0
    for _ in range(args.repeats):
        t0 = time.perf_counter()
        response = worker.handle_request(payload, engine)
        e2e.append(time.perf_counter() - t0)
        if not response.get("ok"):
            print(f"FAIL: {response.get('error')}", file=sys.stderr)
            return 1
        text = response["text"]
        line_count = response["line_count"]

    diags = [diag_run(args.image, engine) for _ in range(args.repeats)]
    diag_median = {
        key: round(statistics.median(d[key] for d in diags) * 1000, 1)
        for key in diags[0]
        if key != "crop_count"
    }

    engine.rec_pool.close()

    report = {
        "label": args.label,
        "image": str(args.image),
        "init_s": round(init_s, 3),
        "first_request_ms": first_ms,
        "e2e_median_ms": round(statistics.median(e2e) * 1000, 1),
        "e2e_all_ms": [round(v * 1000, 1) for v in e2e],
        "line_count": line_count,
        "diag_median_ms": diag_median,
        "crop_count": int(diags[0]["crop_count"]),
        "rec_workers": engine.rec_pool.workers,
        "text": text,
    }
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    out = ARTIFACT_DIR / f"{args.label}.json"
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"\n=== real capture bench [{args.label}] init={init_s:.1f}s workers={engine.rec_pool.workers} ===")
    print(f"first request (post-init warmup): {first_ms}ms")
    print(f"e2e median {report['e2e_median_ms']}ms  (all: {report['e2e_all_ms']})  lines={line_count}")
    total = sum(diag_median.values())
    for key, value in diag_median.items():
        print(f"  {key:<10} {value:>8.1f}ms  ({value / total * 100:4.1f}%)")
    print(f"  crops={report['crop_count']}")
    print(f"saved -> {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
