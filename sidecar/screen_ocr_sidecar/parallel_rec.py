"""Parallel text-recognition pool for the persistent worker.

Recognition (not detection) dominates the OCR round trip: a dense screen capture
spends ~7s in the Korean recognizer while detection takes <0.7s. The recognizer is
single-core bound — MKLDNN, cpu_threads and OMP threads do not scale it — so the
only loss-free way to cut the wall-clock is to fan the independent line crops across
several worker processes. Crops are split with a longest-processing-time heuristic
keyed on crop width (recognition cost is ~linear in the height-48-normalized width),
which keeps the widest full-screen-width lines from piling onto one worker.
"""
from __future__ import annotations

import contextlib
import multiprocessing as mp
import os
import sys
from typing import Any

import numpy as np

from screen_ocr_sidecar.ocr import DET_MODEL_NAME, REC_MODEL_NAME


def _default_workers() -> int:
    raw = os.environ.get("SCREEN_OCR_REC_WORKERS")
    if raw:
        try:
            value = int(raw)
            if value > 0:
                return value
        except ValueError:
            pass
    # 4 measured best on a 6-perf-core machine; extra workers regressed (scheduling).
    cpu = os.cpu_count() or 4
    return max(1, min(4, cpu - 2))


def create_detector(device: str = "cpu") -> Any:
    from paddlex import create_model

    with contextlib.redirect_stdout(sys.stderr):
        return create_model(DET_MODEL_NAME, device=device)


# --- recognition worker process globals ---
_REC: Any = None


def _rec_init(device: str) -> None:
    # Pin each recognizer process to a single math thread; the parallelism is across
    # processes, and intra-op threads only add contention here (measured slower).
    os.environ["OMP_NUM_THREADS"] = "1"
    global _REC
    from paddlex import create_model

    with contextlib.redirect_stdout(sys.stderr):
        _REC = create_model(REC_MODEL_NAME, device=device)
        # Warm the graph with a tiny dummy so the first real request pays no JIT cost.
        _REC.predict([np.zeros((48, 96, 3), dtype=np.uint8)])


def _rec_chunk(chunk: list[tuple[int, np.ndarray]]) -> list[tuple[int, str, float]]:
    if not chunk:
        return []
    crops = [crop for _, crop in chunk]
    with contextlib.redirect_stdout(sys.stderr):
        outputs = list(_REC.predict(crops))
    results: list[tuple[int, str, float]] = []
    for (index, _), output in zip(chunk, outputs):
        data = output.json.get("res", output.json) if hasattr(output, "json") else output
        results.append((index, str(data.get("rec_text", "")), float(data.get("rec_score", 0.0))))
    return results


def _lpt_split(crops: list[np.ndarray], workers: int) -> list[list[tuple[int, np.ndarray]]]:
    """Longest-processing-time bin packing keyed on crop width."""
    order = sorted(range(len(crops)), key=lambda i: -int(crops[i].shape[1]))
    bins: list[list[tuple[int, np.ndarray]]] = [[] for _ in range(workers)]
    load = [0] * workers
    for i in order:
        target = min(range(workers), key=load.__getitem__)
        bins[target].append((i, crops[i]))
        load[target] += int(crops[i].shape[1])
    return bins


def _rec_timeout() -> float:
    raw = os.environ.get("SCREEN_OCR_REC_TIMEOUT_S")
    if raw:
        try:
            value = float(raw)
            if value > 0:
                return value
        except ValueError:
            pass
    # Normal dense capture recognizes in ~3s; 20s is a generous ceiling that still turns a
    # hung recognizer process into a fast, surfaced error instead of an indefinite stall.
    return 20.0


class RecognizerPool:
    """A warmed pool of recognizer processes. Lives for the worker's lifetime."""

    def __init__(self, device: str = "cpu", workers: int | None = None) -> None:
        self._device = device
        self._workers = workers or _default_workers()
        self._pool = self._spawn_pool()

    def _spawn_pool(self) -> Any:
        ctx = mp.get_context("spawn")
        pool = ctx.Pool(
            processes=self._workers,
            initializer=_rec_init,
            initargs=(self._device,),
        )
        # Each process warms itself in _rec_init (a dummy predict), so no extra warm pass here.
        return pool

    def _restart(self) -> None:
        # A timed-out or broken pool leaves workers in an unknown state; tear it down hard and
        # bring up a fresh one so the *next* request is healthy.
        try:
            self._pool.terminate()
            self._pool.join()
        except Exception:  # noqa: BLE001 - best-effort teardown, never mask the original failure.
            pass
        self._pool = self._spawn_pool()

    @property
    def workers(self) -> int:
        return self._workers

    def recognize(self, crops: list[np.ndarray]) -> list[tuple[str, float]]:
        if not crops:
            return []
        # One bin per worker (width-balanced) when it pays off, otherwise a single bin. Both
        # go through map_async so the result shape and timeout handling stay uniform.
        if len(crops) > 1 and self._workers > 1:
            bins = _lpt_split(crops, self._workers)
        else:
            bins = [list(enumerate(crops))]

        timeout = _rec_timeout()
        try:
            raw = self._pool.map_async(_rec_chunk, bins).get(timeout=timeout)
        except mp.TimeoutError:
            self._restart()
            raise RuntimeError(
                f"recognition timed out after {timeout:.0f}s "
                f"({len(crops)} crops / {len(bins)} workers); recognizer pool restarted"
            ) from None
        except Exception:
            # A crashed worker (BrokenProcessPool, pickling failure, …) poisons the pool.
            self._restart()
            raise

        flat = sorted((item for part in raw for item in part), key=lambda entry: entry[0])
        return [(text, score) for _, text, score in flat]

    def close(self) -> None:
        self._pool.close()
        self._pool.join()
