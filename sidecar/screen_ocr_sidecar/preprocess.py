from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path
from statistics import median
from typing import Any

from PIL import Image, ImageChops


@dataclass(frozen=True)
class PreprocessResult:
    original_image_path: str
    ocr_image_path: str
    preprocessed_image_path: str | None
    status: str
    elapsed_ms: float
    original_width: int
    original_height: int
    preprocessed_width: int
    preprocessed_height: int
    crop_box: tuple[int, int, int, int] | None

    @property
    def applied(self) -> bool:
        return self.status == "applied"

    def diagnostics(self) -> dict[str, int]:
        payload = {
            "preprocess_elapsed_ms": int(round(self.elapsed_ms)),
            "preprocess_original_width": self.original_width,
            "preprocess_original_height": self.original_height,
            "preprocess_width": self.preprocessed_width,
            "preprocess_height": self.preprocessed_height,
            "preprocess_applied": 1 if self.applied else 0,
        }
        if self.crop_box is not None:
            left, top, right, bottom = self.crop_box
            payload.update(
                {
                    "preprocess_crop_left": left,
                    "preprocess_crop_top": top,
                    "preprocess_crop_right": right,
                    "preprocess_crop_bottom": bottom,
                }
            )
        return payload

    def metadata(self) -> dict[str, str]:
        payload = {
            "preprocess_status": self.status,
            "original_image_path": self.original_image_path,
            "ocr_image_path": self.ocr_image_path,
        }
        if self.preprocessed_image_path is not None:
            payload["preprocessed_image_path"] = self.preprocessed_image_path
        return payload


def preprocess_image_for_ocr(
    image_path: Path | str,
    output_dir: Path | str | None = None,
    *,
    min_original_area: int = 500_000,
    min_area_reduction: float = 0.25,
    padding: int = 64,
    background_threshold: int = 14,
    min_dimension: int = 24,
) -> PreprocessResult:
    started = time.perf_counter()
    source_path = Path(image_path)

    with Image.open(source_path) as image:
        original_width, original_height = image.size
        original_area = original_width * original_height

        if original_area < min_original_area:
            return _result(
                source_path,
                source_path,
                None,
                "skipped_small",
                started,
                original_width,
                original_height,
                original_width,
                original_height,
                None,
            )

        rgb = image.convert("RGB")
        background = _estimate_background(rgb)
        difference = ImageChops.difference(rgb, Image.new("RGB", rgb.size, background)).convert("L")
        mask = difference.point(lambda value: 255 if value > background_threshold else 0)
        bbox = mask.getbbox()
        if bbox is None:
            return _result(
                source_path,
                source_path,
                None,
                "skipped_empty",
                started,
                original_width,
                original_height,
                original_width,
                original_height,
                None,
            )

        crop_box = _pad_box(bbox, original_width, original_height, padding)
        crop_width = crop_box[2] - crop_box[0]
        crop_height = crop_box[3] - crop_box[1]
        if crop_width < min_dimension or crop_height < min_dimension:
            return _result(
                source_path,
                source_path,
                None,
                "skipped_too_small",
                started,
                original_width,
                original_height,
                original_width,
                original_height,
                None,
            )

        crop_area = crop_width * crop_height
        if crop_area >= original_area * (1 - min_area_reduction):
            return _result(
                source_path,
                source_path,
                None,
                "skipped_low_reduction",
                started,
                original_width,
                original_height,
                original_width,
                original_height,
                None,
            )

        target_dir = Path(output_dir) if output_dir is not None else source_path.parent
        target_dir.mkdir(parents=True, exist_ok=True)
        target_path = target_dir / f"{source_path.stem}.preprocessed{source_path.suffix}"
        rgb.crop(crop_box).save(target_path)
        return _result(
            source_path,
            target_path,
            target_path,
            "applied",
            started,
            original_width,
            original_height,
            crop_width,
            crop_height,
            crop_box,
        )


def skip_preprocessing(image_path: Path | str, status: str = "disabled") -> PreprocessResult:
    started = time.perf_counter()
    source_path = Path(image_path)
    with Image.open(source_path) as image:
        width, height = image.size

    return _result(
        source_path,
        source_path,
        None,
        status,
        started,
        width,
        height,
        width,
        height,
        None,
    )


def _estimate_background(image: Image.Image) -> tuple[int, int, int]:
    width, height = image.size
    points = [
        (0, 0),
        (width - 1, 0),
        (0, height - 1),
        (width - 1, height - 1),
        (width // 2, 0),
        (width // 2, height - 1),
        (0, height // 2),
        (width - 1, height // 2),
    ]
    samples = [image.getpixel(point) for point in points]
    return tuple(int(median(sample[index] for sample in samples)) for index in range(3))


def _pad_box(
    box: tuple[int, int, int, int],
    width: int,
    height: int,
    padding: int,
) -> tuple[int, int, int, int]:
    left, top, right, bottom = box
    return (
        max(0, left - padding),
        max(0, top - padding),
        min(width, right + padding),
        min(height, bottom + padding),
    )


def _result(
    source_path: Path,
    ocr_path: Path,
    preprocessed_path: Path | None,
    status: str,
    started: float,
    original_width: int,
    original_height: int,
    preprocessed_width: int,
    preprocessed_height: int,
    crop_box: tuple[int, int, int, int] | None,
) -> PreprocessResult:
    return PreprocessResult(
        original_image_path=str(source_path),
        ocr_image_path=str(ocr_path),
        preprocessed_image_path=str(preprocessed_path) if preprocessed_path is not None else None,
        status=status,
        elapsed_ms=(time.perf_counter() - started) * 1000,
        original_width=original_width,
        original_height=original_height,
        preprocessed_width=preprocessed_width,
        preprocessed_height=preprocessed_height,
        crop_box=crop_box,
    )


def result_to_json(result: PreprocessResult) -> dict[str, Any]:
    return {
        **result.metadata(),
        **result.diagnostics(),
    }
