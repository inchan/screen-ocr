#!/usr/bin/env python3
"""Validate the adaptive detector cap on the real 5086x2168 jumbled-order capture:
default options must now match the 1536-cap text quality (no clipped leading chars)
while ordinary fixtures keep the fast 1152 behavior. Also times detection.
"""
from __future__ import annotations

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


def main() -> int:
    from screen_ocr_sidecar import worker

    image_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/repro-jumbled.png"
    engine = worker.load_ocr()

    payload = {"id": "adaptive", "image_path": image_path}
    worker.handle_request(payload, engine)  # warmup
    values = []
    text = ""
    for _ in range(3):
        t0 = time.perf_counter()
        response = worker.handle_request(payload, engine)
        values.append((time.perf_counter() - t0) * 1000)
        text = response["text"]
    engine.rec_pool.close()

    print(f"e2e median {statistics.median(values):.0f}ms, lines {response['line_count']}")
    print("--- text head ---")
    print(text[:900])

    markers = ["검출입력캡1536", "캡처PNG", "워크로드", "가설 판정 증거"]
    for marker in markers:
        print(f"marker {'OK ' if marker in text else 'MISSING'}: {marker}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
