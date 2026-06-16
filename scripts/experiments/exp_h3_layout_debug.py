#!/usr/bin/env python3
"""Reproduce the jumbled-line-order report on a real capture.

Runs the production split path on the given image at two detector caps and dumps
every line with its box geometry (y_center / x_left / height) in final output
order, so the row-clustering failure in _layout_text is visible, and so the 1152
cap can be compared against the old 1536 on real small retina text.

Usage: .venv-ocr/bin/python scripts/experiments/exp_h3_layout_debug.py /tmp/repro-jumbled.png
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VENV_PYTHON = ROOT / ".venv-ocr" / "bin" / "python"
if VENV_PYTHON.exists() and Path(sys.executable).resolve() != VENV_PYTHON.resolve():
    os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), *sys.argv])

sys.path.insert(0, str(ROOT / "sidecar"))


def main() -> int:
    from screen_ocr_sidecar import worker
    from screen_ocr_sidecar.ocr import _box_metrics, recognize_image_parallel

    image_path = sys.argv[1]
    engine = worker.load_ocr()

    for side in (1152, 1536):
        options = {"text_det_limit_side_len": side, "text_det_limit_type": "max"}
        document = recognize_image_parallel(
            image_path,
            detector=engine.detector,
            rec_pool=engine.rec_pool,
            predict_options=options,
        )
        dump = []
        for line in document["lines"]:
            metrics = _box_metrics(line.get("box")) or {}
            dump.append(
                {
                    "text": line["text"][:46],
                    "y": round(metrics.get("y_center", -1), 1),
                    "x": round(metrics.get("x_left", -1), 1),
                    "h": round(metrics.get("height", -1), 1),
                }
            )
        out = ROOT / "artifacts" / "stage-bench" / f"layout-debug-{side}.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(
            json.dumps({"line_count": document["line_count"], "text": document["text"], "lines": dump},
                       ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"=== side {side}: {document['line_count']} boxes -> {out.relative_to(ROOT)}")

    engine.rec_pool.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
