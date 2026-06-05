from __future__ import annotations

import argparse
import contextlib
import json
import sys
import time
from collections.abc import Mapping
from typing import Any, TextIO

from screen_ocr_sidecar.ocr import create_default_ocr, recognize_image
from screen_ocr_sidecar.preprocess import preprocess_image_for_ocr, skip_preprocessing


def load_ocr() -> Any:
    with contextlib.redirect_stdout(sys.stderr):
        return create_default_ocr()


def handle_request(
    payload: Mapping[str, Any],
    ocr: Any,
) -> dict[str, Any]:
    request_id = str(payload.get("id", ""))
    image_path = payload.get("image_path")
    if not image_path:
        return {
            "id": request_id,
            "ok": False,
            "error": "Worker request is missing image_path",
        }

    started = time.perf_counter()
    with contextlib.redirect_stdout(sys.stderr):
        if payload.get("preprocess", True) is False:
            preprocess_result = skip_preprocessing(str(image_path))
        else:
            preprocess_result = preprocess_image_for_ocr(str(image_path))
        document = recognize_image(preprocess_result.ocr_image_path, ocr_factory=lambda: ocr)

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
                response = handle_request(payload, ocr)
            else:
                response = {
                    "id": request_id,
                    "ok": False,
                    "error": "Worker request must be a JSON object",
                }
        except Exception as error:  # noqa: BLE001 - worker must return structured errors.
            response = {
                "id": request_id,
                "ok": False,
                "error": str(error),
            }

        print(json.dumps(response, ensure_ascii=False), file=stdout, flush=True)

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a persistent local PaddleOCR JSONL worker.")
    parser.parse_args()

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
    return serve(sys.stdin, sys.stdout, ocr)


if __name__ == "__main__":
    raise SystemExit(main())
