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

import atexit
import contextlib
import multiprocessing as mp
import os
import sys
import threading
import time
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
    # cpu-2 leaves headroom for the detector process and the app. Measured on a 10-core
    # M2 Pro (6P+4E, dense 23-line capture): 4 workers 2372ms e2e, 6 -> 1919ms, 8 -> 1789ms,
    # 10 -> no further gain. The earlier "4 is best" result did not hold up under the
    # production-path benchmark (scripts/experiments/bench_stage.py);
    # efficiency cores still help
    # because the LPT width split keeps the long crops on the fast workers.
    # Capped at 6, not 8: each recognizer process holds ~508MB RSS of Paddle runtime, so
    # 8 -> 6 returns ~1GB while only the dense case slows (~7%); medium/strip measured equal.
    cpu = os.cpu_count() or 4
    return max(1, min(6, cpu - 2))


def create_detector(device: str = "cpu") -> Any:
    from paddlex import create_model

    with contextlib.redirect_stdout(sys.stderr):
        return create_model(DET_MODEL_NAME, device=device)


# --- recognition worker process globals ---
_REC: Any = None


def _watch_parent(initial_ppid: int) -> None:
    """Exits this recognizer process when its parent (the worker) dies.

    Pool children block on the task queue, and every sibling holds the queue's write end,
    so a dead parent never surfaces as EOF — without this watchdog, any worker death that
    skips pool cleanup (SIGTERM's default handler, SIGKILL, a hard crash) strands all the
    recognizer processes forever. That is exactly how "dozens of idle pythons" piled up in
    Activity Monitor after repeated app restarts.
    """
    while True:
        time.sleep(2.0)
        if os.getppid() != initial_ppid:
            os._exit(0)


def _rec_init(device: str, warm_counter: Any = None) -> None:
    # Pin each recognizer process to a single math thread; the parallelism is across
    # processes, and intra-op threads only add contention here (measured slower).
    os.environ["OMP_NUM_THREADS"] = "1"
    threading.Thread(target=_watch_parent, args=(os.getppid(),), daemon=True).start()
    # Exit instantly on the *normal* path too. Letting the interpreter finalize while the
    # watchdog daemon thread sleeps in native code segfaulted (SIGSEGV in pythread teardown,
    # observed as a macOS "Python quit unexpectedly" dialog on every app quit). atexit runs
    # LIFO, so this fires before multiprocessing's own exit work; a throwaway compute child
    # has nothing worth finalizing.
    atexit.register(os._exit, 0)
    global _REC
    from paddlex import create_model

    with contextlib.redirect_stdout(sys.stderr):
        _REC = create_model(REC_MODEL_NAME, device=device)
        # Warm the graph with a tiny dummy so the first real request pays no JIT cost.
        _REC.predict([np.zeros((48, 96, 3), dtype=np.uint8)])
    if warm_counter is not None:
        with warm_counter.get_lock():
            warm_counter.value += 1


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
        self._warm_counter: Any = None
        self._pool = self._spawn_pool()

    def _spawn_pool(self) -> Any:
        ctx = mp.get_context("spawn")
        # ctx.Pool returns as soon as the children are forked; each child then spends seconds
        # importing paddlex and loading the recognizer. The counter lets wait_until_warm tell
        # when every child finished _rec_init, so "worker ready" can mean "actually warm" —
        # without it the first real request silently absorbed the children's model load
        # (~5s extra on top of the warm path, measured 10.3s vs 4.8s on a dense capture).
        self._warm_counter = ctx.Value("i", 0)
        pool = ctx.Pool(
            processes=self._workers,
            initializer=_rec_init,
            initargs=(self._device, self._warm_counter),
        )
        return pool

    def wait_until_warm(self, timeout: float = 20.0) -> bool:
        """Blocks until every recognizer child finished loading its model (bounded).

        Best-effort: on timeout (e.g. a child crashed mid-init) we proceed anyway —
        requests then behave exactly as before this barrier existed.
        """
        counter = self._warm_counter
        if counter is None:
            return True
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            with counter.get_lock():
                if counter.value >= self._workers:
                    return True
            time.sleep(0.05)
        return False

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

    def shutdown(self) -> None:
        """Hard-stop for worker exit (including SIGTERM): terminate children immediately
        instead of draining outstanding work — the process is going away either way.

        Bounded, because mp.Pool.terminate can deadlock against idle workers (observed: a
        worker wedged here for >18s on the stdin-EOF quit path, which kept the children's
        parent alive and therefore their parent-watchdogs silent). If termination doesn't
        finish in time we simply return — once this process exits, every child reaps itself
        within ~2s via its watchdog."""

        def _stop() -> None:
            try:
                self._pool.terminate()
                self._pool.join()
            except Exception:  # noqa: BLE001 - exit path must never raise.
                pass

        stopper = threading.Thread(target=_stop, daemon=True)
        stopper.start()
        stopper.join(timeout=3.0)
