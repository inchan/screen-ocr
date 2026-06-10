from __future__ import annotations

import argparse
import contextlib
import json
import os
import signal
import sys
import time
from collections.abc import Callable, Mapping
from typing import Any, TextIO

from screen_ocr_sidecar.ocr import recognize_image_parallel
from screen_ocr_sidecar.parallel_rec import RecognizerPool, create_detector
from screen_ocr_sidecar.preprocess import preprocess_image_for_ocr, skip_preprocessing


class OCREngine:
    """Holds the single-process detector and the warmed recognition process pool."""

    def __init__(self, detector: Any, rec_pool: Any) -> None:
        self.detector = detector
        self.rec_pool = rec_pool

    def recognize(self, image_path: str, min_score: float = 0.0) -> dict[str, Any]:
        return recognize_image_parallel(
            image_path,
            detector=self.detector,
            rec_pool=self.rec_pool,
            min_score=min_score,
        )


def load_ocr() -> OCREngine:
    with contextlib.redirect_stdout(sys.stderr):
        detector = create_detector()
        rec_pool = RecognizerPool()
    return OCREngine(detector, rec_pool)


def _min_line_score() -> float:
    """Opt-in low-confidence line filter; unset/invalid keeps current behavior (no filter)."""
    raw = os.environ.get("SCREEN_OCR_MIN_LINE_SCORE")
    if not raw:
        return 0.0
    try:
        return float(raw)
    except ValueError:
        return 0.0


def handle_request(
    payload: Mapping[str, Any],
    ocr: Any,
    on_progress: Callable[[str], None] | None = None,
) -> dict[str, Any]:
    request_id = str(payload.get("id", ""))
    image_path = payload.get("image_path")
    if not image_path:
        return {
            "id": request_id,
            "ok": False,
            "error": "Worker request is missing image_path",
            "stage": "validate",
        }

    def emit(stage: str) -> None:
        if on_progress is not None:
            on_progress(stage)

    # Track which pipeline stage is active so a failure is attributable (not just "OCR failed").
    stage = "preprocess"
    started = time.perf_counter()
    try:
        with contextlib.redirect_stdout(sys.stderr):
            emit("preprocess")
            if payload.get("preprocess", True) is False:
                preprocess_result = skip_preprocessing(str(image_path))
            else:
                preprocess_result = preprocess_image_for_ocr(str(image_path))
            stage = "recognize"
            emit("recognize")
            document = ocr.recognize(
                preprocess_result.ocr_image_path,
                min_score=_min_line_score(),
            )
    except Exception as error:  # noqa: BLE001 - failures must be attributable + reproducible.
        import traceback

        return {
            "id": request_id,
            "ok": False,
            "error": str(error) or error.__class__.__name__,
            "stage": stage,
            "image_path": str(image_path),
            "traceback": traceback.format_exc(),
        }

    # The Swift client only consumes text + score; drop box polygons to slim the wire payload.
    document["lines"] = [
        {"text": line["text"], "score": line["score"]}
        for line in document.get("lines", [])
    ]
    document.update(
        {
            "id": request_id,
            "ok": True,
            "request_elapsed_ms": round((time.perf_counter() - started) * 1000, 3),
            "diagnostics": preprocess_result.diagnostics(),
            "metadata": preprocess_result.metadata(),
        }
    )
    return document


def serve(
    stdin: TextIO,
    stdout: TextIO,
    ocr: Any,
) -> int:
    for raw_line in stdin:
        line = raw_line.strip()
        if not line:
            continue

        request_id = ""
        try:
            payload = json.loads(line)
            if isinstance(payload, Mapping):
                request_id = str(payload.get("id", ""))

                def emit_progress(stage: str, _id: str = request_id) -> None:
                    print(
                        json.dumps(
                            {"id": _id, "event": "progress", "stage": stage},
                            ensure_ascii=False,
                        ),
                        file=stdout,
                        flush=True,
                    )

                response = handle_request(payload, ocr, on_progress=emit_progress)
            else:
                response = {
                    "id": request_id,
                    "ok": False,
                    "error": "Worker request must be a JSON object",
                }
        except Exception as error:  # noqa: BLE001 - worker must return structured errors.
            import traceback

            response = {
                "id": request_id,
                "ok": False,
                "error": str(error) or error.__class__.__name__,
                "stage": "request",
                "traceback": traceback.format_exc(),
            }

        print(json.dumps(response, ensure_ascii=False), file=stdout, flush=True)

    return 0


def _install_signal_handlers() -> None:
    """Turn SIGTERM/SIGINT into SystemExit so `finally` blocks run. Python's default SIGTERM
    action kills the interpreter without atexit/multiprocessing cleanup, which strands the
    recognizer pool's spawned children — the Swift client stops the worker with exactly that
    signal (Process.terminate) on every timeout, error, restart, and shutdown."""

    def _terminate(signum: int, _frame: Any) -> None:
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, _terminate)
    signal.signal(signal.SIGINT, _terminate)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a persistent local PaddleOCR JSONL worker.")
    parser.parse_args()

    _install_signal_handlers()
    started = time.perf_counter()
    try:
        ocr = load_ocr()
    except Exception as error:  # noqa: BLE001 - startup must be machine-readable.
        print(
            json.dumps(
                {
                    "event": "ready",
                    "ok": False,
                    "error": str(error),
                    "init_elapsed_ms": round((time.perf_counter() - started) * 1000, 3),
                },
                ensure_ascii=False,
            ),
            flush=True,
        )
        return 1

    print(
        json.dumps(
            {
                "event": "ready",
                "ok": True,
                "init_elapsed_ms": round((time.perf_counter() - started) * 1000, 3),
            },
            ensure_ascii=False,
        ),
        flush=True,
    )
    try:
        return serve(sys.stdin, sys.stdout, ocr)
    finally:
        # Runs on stdin EOF (client exited), SIGTERM/SIGINT (via the handlers above), and
        # any crash — the recognizer children must never outlive the worker.
        ocr.rec_pool.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
