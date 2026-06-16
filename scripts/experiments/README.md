# Experiment Harnesses

This directory keeps historical OCR performance and reliability experiments.
These scripts are useful for reproducing past research, but they are not part of
the supported product automation path or the normal release gate.

Use these when a new performance or reliability investigation needs a reference
point. Before trusting a result, check each script's inputs: some expect generated
stage-bench fixtures, some expect a real capture image, and some intentionally
exercise failure or process-shutdown paths.

If an experiment becomes supported automation, move it back to `scripts/`,
document it from `docs/`, and add gate coverage.

## Inventory

- `bench_stage.py`: production worker stage benchmark with deterministic
  stage-bench fixtures.
- `bench_real_capture.py`: production worker benchmark for a real capture image.
- `bench_image_encode.swift`: ImageIO encode micro-benchmark for PNG, TIFF, JPEG,
  and HEIC capture outputs.
- `check_accuracy_guard.py`: production worker fixture CER guard for performance
  candidates.
- `run_preprocess_benchmark.py`: large mostly-empty capture preprocessing
  benchmark.
- `exp_h1_rec_batch_det_threads.py`: recognition batch size and detector CPU
  thread probe.
- `exp_h2_tiff_vs_png_input.py`: TIFF-vs-PNG worker input probe.
- `exp_h3_adaptive_validate.py`: adaptive detector-cap validation for a real
  dense capture.
- `exp_h3_layout_debug.py`: layout-order debugging dump for detector-cap
  comparisons.
- `exp_h4_worker_orphans.sh`: worker child-process orphan reproduction.
- `exp_h5_quit_crash.sh`: worker quit/crash-report reproduction.
