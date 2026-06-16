#!/usr/bin/env python3
from __future__ import annotations

import json
import statistics
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "sidecar"))

from PIL import Image

from screen_ocr_sidecar.worker import handle_request, load_ocr


def main() -> int:
    artifact_dir = ROOT / "artifacts" / "preprocess"
    artifact_dir.mkdir(parents=True, exist_ok=True)

    source_fixture = ROOT / "fixtures" / "ocr" / "mixed-ko-en-simple.png"
    large_image = artifact_dir / "large-mostly-empty.png"
    create_large_fixture(source_fixture, large_image)

    started = time.perf_counter()
    ocr = load_ocr()
    init_elapsed_ms = round((time.perf_counter() - started) * 1000, 3)

    # Warm once on the normal small fixture so model construction is not counted.
    handle_request({"id": "warmup", "image_path": str(source_fixture)}, ocr)

    baseline_samples = []
    preprocessed_samples = []
    baseline_text = ""
    preprocessed_text = ""
    preprocess_diagnostics = {}
    preprocess_metadata = {}

    for index in range(3):
        baseline = handle_request(
            {
                "id": f"baseline-{index}",
                "image_path": str(large_image),
                "preprocess": False,
            },
            ocr,
        )
        preprocessed = handle_request(
            {
                "id": f"preprocessed-{index}",
                "image_path": str(large_image),
                "preprocess": True,
            },
            ocr,
        )
        baseline_samples.append(float(baseline["request_elapsed_ms"]))
        preprocessed_samples.append(float(preprocessed["request_elapsed_ms"]))
        baseline_text = str(baseline.get("text", ""))
        preprocessed_text = str(preprocessed.get("text", ""))
        preprocess_diagnostics = dict(preprocessed.get("diagnostics", {}))
        preprocess_metadata = dict(preprocessed.get("metadata", {}))

    baseline_median = statistics.median(baseline_samples)
    preprocessed_median = statistics.median(preprocessed_samples)
    improvement_ms = baseline_median - preprocessed_median
    improvement_percent = (improvement_ms / baseline_median * 100) if baseline_median else 0.0

    result = {
        "created_at_epoch": time.time(),
        "status": "passed",
        "image_path": str(large_image),
        "init_elapsed_ms": init_elapsed_ms,
        "baseline_samples_ms": baseline_samples,
        "preprocessed_samples_ms": preprocessed_samples,
        "baseline_median_ms": round(baseline_median, 3),
        "preprocessed_median_ms": round(preprocessed_median, 3),
        "improvement_ms": round(improvement_ms, 3),
        "improvement_percent": round(improvement_percent, 3),
        "baseline_text": baseline_text,
        "preprocessed_text": preprocessed_text,
        "preprocess_diagnostics": preprocess_diagnostics,
        "preprocess_metadata": preprocess_metadata,
    }

    failures = []
    if preprocess_diagnostics.get("preprocess_applied") != 1:
        failures.append("preprocessing was not applied")
    if preprocessed_median >= baseline_median:
        failures.append("preprocessed OCR median did not improve")
    if "Hello" not in preprocessed_text:
        failures.append("preprocessed OCR did not retain expected English text")
    if failures:
        result["status"] = "failed"
        result["failures"] = failures

    output_path = artifact_dir / "latest-preprocess-benchmark.json"
    output_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["status"] == "passed" else 1


def create_large_fixture(source_fixture: Path, large_image: Path) -> None:
    with Image.open(source_fixture) as fixture:
        fixture = fixture.convert("RGB")
        image = Image.new("RGB", (2400, 1600), "white")
        image.paste(fixture, ((image.width - fixture.width) // 2, (image.height - fixture.height) // 2))
        image.save(large_image)


if __name__ == "__main__":
    raise SystemExit(main())
