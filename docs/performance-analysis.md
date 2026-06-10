# OCR Performance Analysis

Last updated: 2026-06-05.

## Evaluation Contract

Primary evaluator:

```sh
SCREEN_OCR_BENCHMARK_REPEATS=7 scripts/run_ocr_fixture_benchmark.py && scripts/run_python_tests.sh && scripts/agent_gate.sh
```

Pass condition for this optimization cycle:
- controlled OCR fixture benchmark keeps 20/20 fixtures passing,
- character error rate stays within fixture thresholds,
- corpus median warm OCR latency improves numerically against the fresh baseline,
- prewarmed app worker hotkey smoke reports region-selection-complete to clipboard under 700 ms on the controlled two-line fixture,
- Python sidecar tests and `scripts/agent_gate.sh` pass,
- `docs/validation-report.md` records the evidence.

Fresh baseline captured before optimization:
- artifact: `artifacts/ocr/baseline-ocr-latency-20260605T060041Z.json`
- created at: 2026-06-05T06:00:41Z
- fixtures: 20/20 passed
- initialization elapsed: 3928.75 ms
- repeat count: 7
- corpus median warm OCR elapsed: 299.21 ms
- median CER: 0.0
- mean CER: 0.0094
- max CER: 0.0588

## Minimal Work Units

1. Hotkey dispatch: global shortcut registration and event delivery.
2. Selection UI: overlay creation, drag tracking, coordinate normalization.
3. Region capture: ScreenCaptureKit crop creation and image file availability.
4. OCR initialization: PaddleOCR model construction and cache loading.
5. OCR image inference: detection and recognition for the captured crop.
6. OCR normalization: PaddleOCR result conversion into stable text/line JSON.
7. Clipboard write: recognized text pasteboard update.
8. Diagnostics/status: failure events and menu bar status surface.
9. Packaging/runtime: bundled sidecar, Python runtime, and model availability.

## Bottleneck Check

Current fixture evidence isolates the OCR sidecar:
- initialization is seconds-scale at 3928.75 ms and matters for cold first use,
- warm image inference is hundreds-of-milliseconds scale at 299.21 ms median,
- normalization and CER calculation are simple Python list/string work and are not the dominant current bottleneck,
- end-to-end hotkey reliability remains dominated by UI/capture/OCR orchestration at roughly seconds-scale, but the most directly measurable local optimization surface is warm OCR inference.

Instrumented hotkey smoke evidence now records app-internal stage timings in `artifacts/app/latest-status.json`, `artifacts/debug-runs/latest-pair.json`, and `artifacts/hotkey/latest-hotkey-smoke.json`.

Three hotkey-to-clipboard samples on 2026-06-05:

| Sample | Smoke elapsed ms | App total ms | Capture ms | OCR subprocess ms | Clipboard ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 6654 | 5714 | 1079 | 4634 | 0 |
| 2 | 6727 | 5017 | 1072 | 3945 | 0 |
| 3 | 6669 | 5701 | 1083 | 4617 | 0 |

Stage median:
- smoke harness elapsed: 6669 ms,
- app internal total: 5701 ms,
- capture/selection/image availability: 1079 ms,
- OCR subprocess: 4617 ms,
- clipboard write: 0 ms.

Conclusion for the 1-second target: not reachable by tuning warm OCR alone. The current median already spends about 4.6 seconds in the OCR subprocess, dominated by launching Python and constructing PaddleOCR for each request. Reaching sub-second end-to-end requires a persistent OCR worker or equivalent preloaded model process, and likely capture-path trimming after that.

## Hypothesis Loop

### H1: Limit detection side length for small screen crops

Hypothesis: The controlled screen crops are only 640-900 px wide and 180-220 px tall, so the OCR detector can use `text_det_limit_side_len=736` with `text_det_limit_type="max"` to reduce detector work while preserving fixture quality.

Source basis: PaddleOCR 3.x `predict()` exposes `text_det_limit_side_len` and `text_det_limit_type`; the current project already disables document orientation, document unwarping, and textline orientation.

Pre-implementation probe, 3 repeats per fixture with one cached OCR instance:

| Variant | Passed | Median Warm ms | Mean CER | Max CER | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| default | 20/20 | 294.26 | 0.0094 | 0.0588 | baseline probe |
| max_900 | 20/20 | 293.74 | 0.0094 | 0.0588 | negligible speedup |
| max_736 | 20/20 | 282.41 | 0.0072 | 0.0588 | accepted candidate |
| max_640 | 20/20 | 271.59 | 0.0136 | 0.0870 | rejected for quality regression risk |
| max_512 | 20/20 | 252.53 | 0.0137 | 0.1200 | rejected for quality regression risk |

Decision: implement `max_736` as the default warm inference setting because it gives a measurable latency reduction without worsening observed quality.

Final evaluator benchmark, 7 repeats per fixture:
- artifact: `artifacts/ocr/final-evaluator-benchmark-20260605T061018Z.json`
- created at: 2026-06-05T06:10:18Z
- fixtures: 20/20 passed
- initialization elapsed: 4391.28 ms
- corpus median warm OCR elapsed: 281.285 ms
- median CER: 0.0
- mean CER: 0.0072
- max CER: 0.0588
- improvement: 17.925 ms faster than the fresh baseline, a 5.991% median warm OCR reduction

Status: accepted. The next optimization target should be cold-start/process lifetime, because the remaining seconds-scale cost is PaddleOCR initialization and Swift currently launches the Python sidecar per OCR request. The final evaluator showed warm inference improved but initialization regressed from 3928.75 ms to 4391.28 ms, so this change must be treated as a warm-inference win only.

### H2: Lower detector limit below 736

Hypothesis: Lower values between 640 and 736 may preserve quality while improving latency more than H1.

Follow-up probe, 3 repeats per fixture:

| Variant | Passed | Median Warm ms | Mean CER | Max CER | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| max_736 | 20/20 | 284.89 | 0.0072 | 0.0588 | retained |
| max_704 | 20/20 | 279.75 | 0.0159 | 0.1200 | rejected |
| max_672 | 20/20 | 270.31 | 0.0134 | 0.1200 | rejected |
| max_640 | 20/20 | 269.40 | 0.0136 | 0.0870 | rejected |

Decision: keep `736` as the default. Lower values are faster, but they create unacceptable default quality risk on code and terminal-style fixtures.

### H3: Keep PaddleOCR loaded in a persistent worker

Hypothesis: The current end-to-end delay is dominated by per-request Python/PaddleOCR startup. A long-lived local Python worker that constructs PaddleOCR once and then accepts image paths over a simple request protocol should move the OCR stage from one-shot cold latency to warm latency.

Research measurements on 2026-06-05:

| Probe | Median / Value | Notes |
| --- | ---: | --- |
| One-shot Python sidecar CLI | 3641.83 ms | 3 runs of `.venv-ocr/bin/python -m screen_ocr_sidecar.ocr <fixture>` |
| Persistent JSONL worker ready | 4801.60 ms | one-time startup/model load before serving requests |
| Persistent JSONL worker request roundtrip | 268.77 ms | 7 requests after ready, includes JSON stdin/stdout overhead |
| Persistent worker OCR internal time | 268.65 ms | same 7 requests, inside worker |
| Persistent worker RSS after ready | 854.0 MB | measured with `ps -o rss` |
| ScreenCaptureKit capture + PNG write | 26 ms | 5 noninteractive samples, median |

Expected impact:
- OCR stage can plausibly move from the current hotkey-smoke median `4617 ms` to roughly `269 ms` after the worker is ready.
- App-internal median could move from `5701 ms` to approximately `1353 ms` if the current measured `1079 ms` capture/selection stage is unchanged.
- If measuring from mouse-up/selection completion rather than from hotkey dispatch and scripted drag delay, sub-second clipboard completion is plausible.

Constraints:
- Worker startup still costs several seconds and should happen at app launch, idle warm-up, or first-run prewarm.
- Resident memory cost is high at about 854 MB RSS with the current PaddleOCR runtime and models.
- The worker must have crash detection, restart, timeout, and request/response framing so a broken Python process does not hang the menu bar app.

Implementation measurements on 2026-06-05:

| Probe | Value | Notes |
| --- | ---: | --- |
| Worker ready elapsed | 4459 ms | app launch prewarm, excluded from capture-to-clipboard target |
| Worker init elapsed | 4409.577 ms | Python worker reported model-load time |
| Worker RSS after ready | 845.4 MB | `ps` RSS copied into hotkey smoke |
| Selection UI elapsed | 1028 ms | scripted hotkey smoke includes intentional wait/drag |
| ScreenCaptureKit capture | 50 ms | after region selection completed |
| PNG write | 7 ms | after ScreenCaptureKit image returned |
| Image capture available | 57 ms | capture plus PNG write after selection |
| OCR stage | 353 ms | persistent worker request through Swift app |
| Clipboard write | 0 ms | pasteboard update |
| Region-selection-complete to clipboard | 410 ms | image capture available + OCR + clipboard |

Measured impact:
- OCR stage improved from the previous hotkey-smoke median `4617 ms` to `353 ms`, a 4264 ms / 92.4% reduction.
- App internal total improved from the previous median `5701 ms` to `1438 ms`, while still including scripted selection time.
- The user-facing target measured after region selection is now `410 ms`, which is below the 700 ms acceptance threshold for the controlled two-line fixture.

Status: accepted and implemented for the app startup prewarm path. Remaining reliability work is a hard request timeout and representative real-screen crop validation.

### H4: Enable PaddleOCR HPI / CPU tuning

Hypothesis: PaddleOCR high-performance inference or CPU thread tuning may improve warm request latency after the persistent worker removes startup cost.

Official docs expose `enable_hpi`, `enable_mkldnn`, `mkldnn_cache_capacity`, and `cpu_threads` as inference-related settings. Local probes:

| Variant | Init ms | Warm Median ms | Result |
| --- | ---: | ---: | --- |
| base | 2008.24 | 274.78 | baseline for this probe |
| `enable_hpi=True` | n/a | n/a | failed because `ultra-infer` is not installed |
| `cpu_threads=4` | 1492.93 | 267.74 | small improvement |
| `cpu_threads=2` | 1502.24 | 269.54 | small improvement |
| `text_recognition_batch_size=4` | 1505.04 | 269.93 | small improvement |

Decision: do not add HPI dependencies in the next slice. Test `cpu_threads=4` inside the persistent-worker spike as a low-risk runtime option, but treat it as secondary because the major win comes from process/model reuse.

### H5: Auto-trim mostly empty large captures before OCR

Hypothesis: When a user selects a large region that contains only a small amount of text, PaddleOCR spends unnecessary text-detection work on empty margins. A conservative PNG preprocessing step between screenshot save and OCR can crop mostly-empty margins and reduce worker request latency without changing engines.

Implementation:
- `screen_ocr_sidecar.preprocess.preprocess_image_for_ocr` estimates the border background color, builds a foreground mask, pads the foreground bbox by 64 px, and writes `<capture>.preprocessed.png`.
- The worker runs OCR against the preprocessed path only when the original image area is at least 500,000 px and the crop removes at least 25% of the area.
- Small or unsafe images fall back to the original path and still report preprocessing diagnostics.

Large mostly-empty benchmark on 2026-06-05:

| Metric | No preprocessing | Auto-trim preprocessing |
| --- | ---: | ---: |
| Input dimensions | 2400x1600 | 331x222 |
| Median request latency | 397.901 ms | 267.591 ms |
| OCR text | `OCR테스트\nHello 123` | `OCR테스트\nHello 123` |

Measured impact:
- median latency improved by 130.31 ms / 32.749% on the synthetic large-empty two-line region,
- preprocessing itself cost 28 ms in the latest benchmark,
- crop dimensions reduced from 3,840,000 px to 73,482 px, a 98.1% pixel-area reduction.

Small controlled hotkey smoke after this change:
- preprocessing status: `skipped_small`,
- preprocess elapsed: 15 ms,
- post-selection-to-clipboard: 483 ms,
- OCR text: `OCR테스트\nHello 123`.

Status: accepted for mostly-empty large selections. Real-world large screenshots still need a representative corpus because non-uniform backgrounds may correctly fall back instead of trimming.

### H6: First-request pool-warm penalty + dead-worker cold start (2026-06-10)

User-reported 17s (app-reported `ocr_elapsed_ms` 14,584) for a 2504x2186 half-screen
capture with 51 lines, while the warm production path runs the same image in ~4.8s.
Decomposition of the gap (`scripts/bench_real_capture.py` on the original TIFF):

| Window | Measured |
| --- | ---: |
| worker init (`load_ocr`) | 4.7-5.1 s |
| first request immediately after init | 10,279 ms |
| warm e2e median | 4,832 ms (recognize 4,485 ms = 84%) |

Two compounding causes:
1. `mp.Pool` returns before its children finish importing paddlex and loading the
   recognizer, but the worker printed `ready` right away — so the *first* request
   silently absorbed the children's model loads (~5.5s on top of the warm path).
2. The launch-prewarmed worker had died unobserved (cause unknown; nothing respawned
   it), so the user's request also paid the full worker spawn.

Fixes:
- `parallel_rec.py`: per-child init-completion counter (`mp.Value` via initargs) and
  `RecognizerPool.wait_until_warm()`; `worker.load_ocr` spawns the pool first so the
  children's model loads overlap the parent's detector construction, then blocks until
  every child is warm. "ready" now means actually warm.
- `main.swift`: a 10s worker-liveness watchdog re-prewarms whenever the worker process
  is gone, so a hotkey press always finds a live, warm worker (verified by SIGKILLing
  the worker: auto-respawned and ready within ~25s, no orphaned children).

Validator (`.omx/specs/autoresearch-ocr-7s-real/validate.py`, gate <7,000 ms with
identical accuracy on the real capture):

| Metric | Before | After |
| --- | ---: | ---: |
| cold-exposed first request | 10,279 ms | 5,135 ms |
| warm median | 4,832 ms | 4,340 ms |
| line count / anchor tokens | 51 / 100% | 51 / 100% |

Status: accepted. Worker init grew 4.7s -> ~5.7-6.9s (it now includes child warm-up),
but that cost is paid at app launch / watchdog respawn, never by a user request.
