#!/usr/bin/env python3
"""Hypothesis experiments (single process, no pool):

H-R1  recognition batch_size: the rec predictor defaults to batch_size=1, so the
      pool workers infer crop-by-crop. Measure rec time over the dense fixture's
      crops at batch_size 1 / 4 / 8 / all, and compare outputs for equality.
H-D1  detector cpu_threads: default is 10 (PADDLE_PDX_CPU_NUM_THREADS); the M2 Pro
      has 6 perf cores. Measure detect at threads 10 / 6 / 4.
H-D2  det input scale: limit_side_len 1536 vs 1280 vs 1152. Record time + box count
      (accuracy checked later through the full-path snapshot guard).
"""
from __future__ import annotations

import contextlib
import json
import os
import statistics
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VENV_PYTHON = ROOT / ".venv-ocr" / "bin" / "python"
if VENV_PYTHON.exists() and Path(sys.executable).resolve() != VENV_PYTHON.resolve():
    os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), *sys.argv])

sys.path.insert(0, str(ROOT / "sidecar"))

REPEATS = 5


def median_time(fn) -> float:
    values = []
    for _ in range(REPEATS):
        t0 = time.perf_counter()
        fn()
        values.append(time.perf_counter() - t0)
    return statistics.median(values) * 1000


def main() -> int:
    import cv2
    import numpy as np
    from paddlex import create_model
    from paddlex.inference.pipelines.components.common.crop_image_regions import CropByPolys

    from screen_ocr_sidecar.ocr import DET_MODEL_NAME, REC_MODEL_NAME

    image = cv2.imread(str(ROOT / "fixtures" / "stage-bench" / "dense-doc.png"))
    det_kwargs = {"limit_side_len": 1536, "limit_type": "max"}

    out: dict = {}

    with contextlib.redirect_stdout(sys.stderr):
        detector = create_model(DET_MODEL_NAME, device="cpu")
        det_result = list(detector.predict(image, **det_kwargs))
        data = det_result[0].json.get("res", det_result[0].json)
        polys = list(data.get("dt_polys", []))
        crops = list(CropByPolys(det_box_type="quad")(image, np.array(polys)))
        print(f"crops: {len(crops)}", file=sys.stderr)

        # --- H-R1: rec batch size (single process, OMP default) ---
        rec = create_model(REC_MODEL_NAME, device="cpu")
        rec.predict([np.zeros((48, 96, 3), dtype=np.uint8)])  # warm

        def run_rec(batch: int):
            return [
                (o.json.get("res", o.json)["rec_text"], o.json.get("res", o.json)["rec_score"])
                for o in rec.predict(list(crops), batch_size=batch)
            ]

        texts: dict[int, list] = {}
        out["rec_batch_ms"] = {}
        for batch in (1, 4, 8, len(crops)):
            texts[batch] = run_rec(batch)  # warm + capture output
            out["rec_batch_ms"][batch] = round(median_time(lambda b=batch: run_rec(b)), 1)
        out["rec_text_equal_b1_vs_b8"] = [t for t, _ in texts[1]] == [t for t, _ in texts[8]]
        out["rec_text_equal_b1_vs_ball"] = [t for t, _ in texts[1]] == [t for t, _ in texts[len(crops)]]
        out["rec_score_max_delta_b1_vs_ball"] = max(
            abs(a - b) for (_, a), (_, b) in zip(texts[1], texts[len(crops)])
        )

        # --- H-D1: detector cpu_threads ---
        out["det_threads_ms"] = {}
        for threads in (10, 6, 4):
            det = create_model(DET_MODEL_NAME, device="cpu", kernel_option={"cpu_threads": threads})
            det.predict(image, **det_kwargs)  # warm
            out["det_threads_ms"][threads] = round(
                median_time(lambda d=det: list(d.predict(image, **det_kwargs))), 1
            )

        # --- H-D2: det input scale (default threads) ---
        out["det_scale"] = {}
        for side in (1536, 1280, 1152):
            kwargs = {"limit_side_len": side, "limit_type": "max"}
            detector.predict(image, **kwargs)  # warm
            ms = median_time(lambda k=kwargs: list(detector.predict(image, **k)))
            result = list(detector.predict(image, **kwargs))
            boxes = len(result[0].json.get("res", result[0].json).get("dt_polys", []))
            out["det_scale"][side] = {"ms": round(ms, 1), "boxes": boxes}

    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
