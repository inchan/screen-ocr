#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import statistics
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VENV_PYTHON = ROOT / ".venv-ocr" / "bin" / "python"

if VENV_PYTHON.exists() and Path(sys.executable).resolve() != VENV_PYTHON.resolve():
    os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), *sys.argv])

sys.path.insert(0, str(ROOT / "sidecar"))

from screen_ocr_sidecar.metrics import character_error_rate
from screen_ocr_sidecar.ocr import create_default_ocr, recognize_image

MANIFEST_PATH = ROOT / "fixtures" / "ocr" / "manifest.json"
OUTPUT_DIR = ROOT / "artifacts" / "ocr"


def main() -> int:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    repeats = int(os.environ.get("SCREEN_OCR_BENCHMARK_REPEATS", "5"))

    runs = []
    init_started = time.perf_counter()
    ocr_instance = create_default_ocr()
    initialization_elapsed_ms = round((time.perf_counter() - init_started) * 1000, 2)

    def cached_ocr_factory():
        return ocr_instance

    for fixture in manifest["fixtures"]:
        image_path = ROOT / fixture["path"]
        documents = []
        elapsed_values = []
        for _ in range(repeats):
            started = time.perf_counter()
            document = recognize_image(image_path, ocr_factory=cached_ocr_factory)
            elapsed_values.append(round((time.perf_counter() - started) * 1000, 2))
            documents.append(document)

        document = documents[-1]
        cer = character_error_rate(fixture["expected_text"], document["text"])

        runs.append(
            {
                "fixture_id": fixture["id"],
                "image_path": fixture["path"],
                "expected_text": fixture["expected_text"],
                "actual_text": document["text"],
                "line_count": document["line_count"],
                "character_error_rate": round(cer, 4),
                "max_character_error_rate": fixture["max_character_error_rate"],
                "passed": cer <= fixture["max_character_error_rate"],
                "repeat_count": repeats,
                "elapsed_ms_values": elapsed_values,
                "median_warm_elapsed_ms": round(statistics.median(elapsed_values), 2),
                "lines": document["lines"],
            }
        )

    median_values = [run["median_warm_elapsed_ms"] for run in runs]
    character_error_rates = [run["character_error_rate"] for run in runs]
    report = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "fixture_count": len(runs),
        "passed_count": sum(1 for run in runs if run["passed"]),
        "initialization_elapsed_ms": initialization_elapsed_ms,
        "repeat_count": repeats,
        "median_warm_elapsed_ms": statistics.median(median_values) if median_values else 0,
        "median_character_error_rate": statistics.median(character_error_rates) if character_error_rates else 0,
        "mean_character_error_rate": round(statistics.mean(character_error_rates), 4) if character_error_rates else 0,
        "max_observed_character_error_rate": max(character_error_rates) if character_error_rates else 0,
        "runs": runs,
    }

    output_path = OUTPUT_DIR / "latest-benchmark.json"
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))

    return 0 if report["passed_count"] == report["fixture_count"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
