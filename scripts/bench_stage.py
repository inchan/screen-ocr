#!/usr/bin/env python3
"""Stage-level benchmark for the *production* OCR worker path.

The legacy `run_ocr_fixture_benchmark.py` measures the monolithic `recognize_image`
path, which the worker no longer uses — the worker serves requests through
`handle_request` → `recognize_image_parallel` (split detect → crop → pooled
recognition). This benchmark measures that real path:

  * e2e   — `worker.handle_request` latency, the number that matters. All
            hypothesis proofs compare this metric.
  * diag  — a stage decomposition (preprocess / imread / detect / crop /
            recognize / assemble) used only to locate where time goes.

It also snapshots the recognized text per fixture so any optimization can be
checked for accuracy regressions (text must stay identical to the baseline).

Usage:
  .venv-ocr/bin/python scripts/bench_stage.py [--repeats 5] [--label baseline]
"""
from __future__ import annotations

import argparse
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

FIXTURE_DIR = ROOT / "fixtures" / "stage-bench"
ARTIFACT_DIR = ROOT / "artifacts" / "stage-bench"
FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"

# Deterministic, screenshot-like fixtures. The dense one models the worst case the
# stage toast was built for (a full-screen retina capture dense with text); the
# medium one models a typical window crop; the strip models a single wide line.
KO = [
    "화면을 캡처하면 텍스트가 자동으로 클립보드에 복사됩니다.",
    "설정 창에서 단축키를 변경할 수 있으며 기본값은 Cmd+Shift+2 입니다.",
    "전처리 단계는 배경을 제거하고 텍스트 영역만 잘라냅니다.",
    "인식 결과는 사람이 읽는 순서대로 정렬되어 반환됩니다.",
    "워커 프로세스는 앱이 시작될 때 한 번만 초기화됩니다.",
]
EN = [
    "The quick brown fox jumps over the lazy dog 1234567890.",
    "Performance budgets: capture 40ms, encode 120ms, recognize 2400ms.",
    "def handle_request(payload, ocr, on_progress=None):",
    "RecognizerPool fans independent line crops across spawned processes.",
    "Median of five warm repeats; first run is discarded as warmup.",
]


def _render(path: Path, width: int, height: int, lines: list[str], size: int) -> None:
    from PIL import Image, ImageDraw, ImageFont

    image = Image.new("RGB", (width, height), "#ffffff")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(FONT, size)
    y = size
    for line in lines:
        draw.text((size, y), line, fill="#111111", font=font)
        y += int(size * 1.8)
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


def ensure_fixtures() -> dict[str, Path]:
    dense = FIXTURE_DIR / "dense-doc.png"
    medium = FIXTURE_DIR / "medium-window.png"
    strip = FIXTURE_DIR / "single-strip.png"
    if not dense.exists():
        lines = []
        for i in range(20):
            lines.append(f"{i + 1:02d}. {KO[i % len(KO)]}")
            lines.append(f"    {EN[i % len(EN)]}")
        _render(dense, 2560, 1440, lines[:38], 34)
    if not medium.exists():
        lines = [f"{KO[i % len(KO)]}" if i % 2 == 0 else f"{EN[i % len(EN)]}" for i in range(12)]
        _render(medium, 1200, 800, lines, 30)
    if not strip.exists():
        _render(strip, 2200, 130, ["복사 완료: Performance is a feature — 측정 없이 개선 없다."], 48)
    return {"dense-doc": dense, "medium-window": medium, "single-strip": strip}


def diag_run(image_path: Path, engine) -> dict[str, float]:
    """Stage decomposition mirroring recognize_image_parallel. Diagnosis only."""
    import cv2
    import numpy as np
    from paddlex.inference.pipelines.components.common.crop_image_regions import CropByPolys

    from screen_ocr_sidecar.ocr import _det_options
    from screen_ocr_sidecar.preprocess import preprocess_image_for_ocr

    timings: dict[str, float] = {}
    t0 = time.perf_counter()
    pre = preprocess_image_for_ocr(str(image_path))
    timings["preprocess"] = time.perf_counter() - t0

    t0 = time.perf_counter()
    image = cv2.imread(pre.ocr_image_path)
    timings["imread"] = time.perf_counter() - t0

    det_kwargs = _det_options(None)
    with contextlib.redirect_stdout(sys.stderr):
        t0 = time.perf_counter()
        det_result = list(engine.detector.predict(image, **det_kwargs))
        timings["detect"] = time.perf_counter() - t0
        data = det_result[0].json.get("res", det_result[0].json)
        polys = list(data.get("dt_polys", []))
        t0 = time.perf_counter()
        crops = list(CropByPolys(det_box_type="quad")(image, np.array(polys)))
        timings["crop"] = time.perf_counter() - t0

    t0 = time.perf_counter()
    engine.rec_pool.recognize(crops)
    timings["recognize"] = time.perf_counter() - t0
    timings["crop_count"] = len(crops)
    return timings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--label", default="run")
    parser.add_argument("--skip-diag", action="store_true")
    args = parser.parse_args()

    from screen_ocr_sidecar import worker

    fixtures = ensure_fixtures()

    t0 = time.perf_counter()
    engine = worker.load_ocr()
    init_s = time.perf_counter() - t0

    report: dict = {"label": args.label, "repeats": args.repeats, "init_s": round(init_s, 3), "fixtures": {}}

    for name, path in fixtures.items():
        payload = {"id": f"bench-{name}", "image_path": str(path)}
        # Warmup (also clears first-touch page faults / model graph effects).
        worker.handle_request(payload, engine)

        e2e: list[float] = []
        text = ""
        line_count = 0
        for _ in range(args.repeats):
            t0 = time.perf_counter()
            response = worker.handle_request(payload, engine)
            e2e.append(time.perf_counter() - t0)
            if not response.get("ok"):
                print(f"FAIL {name}: {response.get('error')}", file=sys.stderr)
                return 1
            text = response["text"]
            line_count = response["line_count"]

        entry: dict = {
            "e2e_median_ms": round(statistics.median(e2e) * 1000, 1),
            "e2e_all_ms": [round(v * 1000, 1) for v in e2e],
            "line_count": line_count,
            "text": text,
        }

        if not args.skip_diag:
            diags = [diag_run(path, engine) for _ in range(args.repeats)]
            entry["diag_median_ms"] = {
                key: round(statistics.median(d[key] for d in diags) * 1000, 1)
                for key in diags[0]
                if key != "crop_count"
            }
            entry["crop_count"] = int(diags[0]["crop_count"])

        report["fixtures"][name] = entry

    engine.rec_pool.close()

    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    out = ARTIFACT_DIR / f"{args.label}.json"
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"\n=== stage bench [{args.label}] repeats={args.repeats} init={init_s:.1f}s ===")
    for name, entry in report["fixtures"].items():
        print(f"\n{name}: e2e median {entry['e2e_median_ms']}ms  (all: {entry['e2e_all_ms']})")
        if "diag_median_ms" in entry:
            total = sum(entry["diag_median_ms"].values())
            for key, value in entry["diag_median_ms"].items():
                print(f"  {key:<10} {value:>8.1f}ms  ({value / total * 100:4.1f}%)")
            print(f"  crops={entry['crop_count']} lines={entry['line_count']}")
    print(f"\nsaved -> {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
