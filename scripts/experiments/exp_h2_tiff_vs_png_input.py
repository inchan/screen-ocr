#!/usr/bin/env python3
"""H-S1 sidecar half: does an uncompressed-TIFF capture make worker.handle_request
faster than the equivalent PNG, with byte-identical recognized text? (The Swift
half — encode 89ms -> 8.5ms — is measured by
scripts/experiments/bench_image_encode.swift.)
"""
from __future__ import annotations

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


def main() -> int:
    from PIL import Image

    from screen_ocr_sidecar import worker

    paths: dict[str, tuple[str, str]] = {}
    for name in ("dense-doc", "medium-window", "single-strip"):
        src = ROOT / "fixtures" / "stage-bench" / f"{name}.png"
        dst = Path(f"/tmp/bench-{name}.tiff")
        image = Image.open(src)
        image.load()
        image.save(dst, compression=None)
        paths[name] = (str(src), str(dst))

    engine = worker.load_ocr()
    out: dict = {}
    for name, (png, tiff) in paths.items():
        entry: dict = {}
        for kind, path in (("png", png), ("tiff", tiff)):
            payload = {"id": f"{name}-{kind}", "image_path": path}
            worker.handle_request(payload, engine)  # warmup
            values, text = [], ""
            for _ in range(5):
                t0 = time.perf_counter()
                response = worker.handle_request(payload, engine)
                values.append((time.perf_counter() - t0) * 1000)
                text = response["text"]
            entry[kind] = {"median_ms": round(statistics.median(values), 1), "text": text}
        entry["text_equal"] = entry["png"]["text"] == entry["tiff"]["text"]
        del entry["png"]["text"], entry["tiff"]["text"]
        out[name] = entry
    engine.rec_pool.close()
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
