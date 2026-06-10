from __future__ import annotations

import argparse
import contextlib
import json
import re
import sys
from collections.abc import Callable, Iterable, Mapping
from pathlib import Path
from typing import Any


Line = dict[str, Any]
Document = dict[str, Any]
# Cap the longest side at 1536 (downscale only — never upscale). The previous 736 cap
# shrank wide single-line crops (e.g. 2540x132) until their text was ~38px tall and the
# detector found nothing; 1536 keeps such a strip at ~80px tall so the text stays legible,
# while still bounding cost for large/full-screen captures (a "min" strategy instead blows
# up wide strips to multi-megapixel and pushes a normal crop past the request timeout).
DEFAULT_PREDICT_OPTIONS: Mapping[str, Any] = {
    "text_det_limit_side_len": 1536,
    "text_det_limit_type": "max",
}


# Single source of truth for the model names; parallel_rec.py imports these so the detector and
# recognizer stay in sync with the monolithic PaddleOCR path.
DET_MODEL_NAME = "PP-OCRv5_mobile_det"
REC_MODEL_NAME = "korean_PP-OCRv5_mobile_rec"


def create_default_ocr() -> Any:
    from paddleocr import PaddleOCR

    return PaddleOCR(
        text_detection_model_name=DET_MODEL_NAME,
        text_recognition_model_name=REC_MODEL_NAME,
        use_doc_orientation_classify=False,
        use_doc_unwarping=False,
        use_textline_orientation=False,
        device="cpu",
    )


def recognize_image(
    image_path: Path | str,
    ocr_factory: Callable[[], Any] | None = None,
    predict_options: Mapping[str, Any] | None = None,
    min_score: float = 0.0,
) -> Document:
    path = Path(image_path)
    factory = ocr_factory or create_default_ocr
    ocr = factory()
    options = dict(DEFAULT_PREDICT_OPTIONS if predict_options is None else predict_options)
    raw = ocr.predict(str(path), **options)
    return _build_document(path, normalize_predict_result(raw), min_score)


def _build_document(image_path: Path, lines: list[Line], min_score: float) -> Document:
    """Apply the optional low-confidence filter and assemble the wire Document. Shared by the
    monolithic and split recognition paths so the filter/layout stays defined in one place."""
    if min_score > 0.0:
        lines = [line for line in lines if _coerce_score(line.get("score")) >= min_score]
    return {
        "image_path": str(image_path),
        "text": recognized_text(lines),
        "line_count": len(lines),
        "lines": lines,
    }


def _reading_order_key(line: Line) -> tuple[float, float]:
    """Sort key that orders lines top-to-bottom then left-to-right; geometry-less lines sink to
    the end. `list.sort` is stable, so detection order breaks ties without an explicit index."""
    metrics = _box_metrics(line.get("box"))
    if metrics is None:
        return (float("inf"), float("inf"))
    return (metrics["y_center"], metrics["x_left"])


def _det_options(predict_options: Mapping[str, Any] | None) -> dict[str, Any]:
    """Translate the PaddleOCR-style det knobs into paddlex detector predict kwargs."""
    options = dict(DEFAULT_PREDICT_OPTIONS if predict_options is None else predict_options)
    mapped: dict[str, Any] = {}
    if "text_det_limit_side_len" in options:
        mapped["limit_side_len"] = options["text_det_limit_side_len"]
    if "text_det_limit_type" in options:
        mapped["limit_type"] = options["text_det_limit_type"]
    return mapped


def recognize_image_parallel(
    image_path: Path | str,
    detector: Any,
    rec_pool: Any,
    predict_options: Mapping[str, Any] | None = None,
    min_score: float = 0.0,
) -> Document:
    """Split detect→crop→recognize pipeline that fans recognition across processes.

    Produces the same Document shape as recognize_image so the worker wire format and
    the layout/normalization logic are unchanged; only recognition is parallelized.
    """
    # cv2 / paddlex are heavy, paddlex-only deps; import lazily so importing this module (e.g.
    # for the monolithic path or tests) does not require them.
    import cv2
    import numpy as np
    from paddlex.inference.pipelines.components.common.crop_image_regions import CropByPolys

    path = Path(image_path)
    image = cv2.imread(str(path))
    if image is None:
        return _build_document(path, [], min_score)

    det_kwargs = _det_options(predict_options)
    with contextlib.redirect_stdout(sys.stderr):
        det_result = list(detector.predict(image, **det_kwargs))
        polys: list[Any] = []
        if det_result:
            data = det_result[0].json.get("res", det_result[0].json)
            polys = list(data.get("dt_polys", []))
        if not polys:
            return _build_document(path, [], min_score)
        crops = CropByPolys(det_box_type="quad")(image, np.array(polys))

    recognized = rec_pool.recognize(list(crops))

    lines: list[Line] = []
    for poly, (text, score) in zip(polys, recognized):
        clean = str(text).strip()
        if not clean:
            continue
        lines.append({"text": clean, "score": _coerce_score(score), "box": _coerce_box(poly)})

    # The detector returns boxes in its own order (often bottom-to-top); the Swift client joins
    # `lines` verbatim, so sort into human reading order to match the monolithic PaddleOCR path.
    lines.sort(key=_reading_order_key)
    return _build_document(path, lines, min_score)


def recognized_text(lines: Iterable[Mapping[str, Any]]) -> str:
    items: list[tuple[str, dict[str, float] | None]] = []
    for line in lines:
        text = str(line.get("text", "")).strip()
        if not text:
            continue
        items.append((text, _box_metrics(line.get("box"))))

    if not items:
        return ""

    if all(metrics is None for _, metrics in items):
        return "\n".join(normalize_korean_spacing(text) for text, _ in items)

    return _layout_text(items)


def _layout_text(items: list[tuple[str, dict[str, float] | None]]) -> str:
    heights = sorted(metrics["height"] for _, metrics in items if metrics)
    median_height = heights[len(heights) // 2] if heights else 1.0
    # Two boxes belong to the same row when their vertical centers are closer than
    # a fraction of the typical text height; adjacent lines sit at least one text
    # height apart, so this keeps real lines separate while merging fragments.
    row_threshold = max(median_height * 0.6, 1.0)

    ordered = []
    for index, (text, metrics) in enumerate(items):
        if metrics is None:
            # No geometry: sink to the bottom while preserving detection order.
            ordered.append((float("inf"), float("inf"), index, text))
        else:
            ordered.append((metrics["y_center"], metrics["x_left"], index, text))
    ordered.sort(key=lambda entry: (entry[0], entry[1], entry[2]))

    rows: list[list[tuple[float, int, str]]] = []
    row_reference_y: float | None = None
    for y_center, x_left, index, text in ordered:
        same_row = (
            bool(rows)
            and row_reference_y is not None
            and y_center != float("inf")
            and abs(y_center - row_reference_y) <= row_threshold
        )
        if same_row:
            rows[-1].append((x_left, index, text))
        else:
            rows.append([(x_left, index, text)])
            row_reference_y = None if y_center == float("inf") else y_center

    output_lines = []
    for row in rows:
        row.sort(key=lambda entry: (entry[0], entry[1]))
        output_lines.append(" ".join(text for _, _, text in row))

    return "\n".join(normalize_korean_spacing(line) for line in output_lines)


# The Korean recognizer frequently drops spaces next to punctuation (e.g. "보세요.이제",
# "원하시면(예", a leading "-캡처가"). We can only restore the spaces that Korean typography
# makes unambiguous, so every rule below is anchored on a Hangul syllable — Latin/digit
# boundaries are left untouched so code, paths, versions and numbers ("3.9.1", "screen-ocr",
# "/Users/x", "f(x)", "1,000") are never corrupted.
_HANGUL = "가-힣"
_SPACING_RULES: tuple[tuple[re.Pattern[str], str], ...] = (
    # sentence/clause punctuation immediately followed by Hangul -> add a space after it
    (re.compile(rf"([.,!?;:])([{_HANGUL}])"), r"\1 \2"),
    # punctuation immediately followed by an opening bracket -> "복사.(내" => "복사. (내"
    (re.compile(r"([.,!?;:])([(\[])"), r"\1 \2"),
    # Hangul or digit immediately followed by an opening bracket -> "면(" / "132(" => "면 (" / "132 ("
    (re.compile(rf"([{_HANGUL}0-9])([(\[])"), r"\1 \2"),
    # closing bracket immediately followed by Hangul -> ")이제" => ") 이제"
    (re.compile(rf"([)\]])([{_HANGUL}])"), r"\1 \2"),
)
# A line that starts with a bullet glyph stuck to its text -> "-캡처가" => "- 캡처가"
_LEADING_BULLET = re.compile(r"^([-*•])(\S)")


def normalize_korean_spacing(line: str) -> str:
    result = _LEADING_BULLET.sub(r"\1 \2", line)
    for pattern, replacement in _SPACING_RULES:
        result = pattern.sub(replacement, result)
    return result


def _is_number(value: Any) -> bool:
    return isinstance(value, int | float) and not isinstance(value, bool)


def _box_points(box: Any) -> list[tuple[float, float]]:
    if not isinstance(box, list | tuple) or not box:
        return []

    if all(
        isinstance(point, list | tuple)
        and len(point) >= 2
        and _is_number(point[0])
        and _is_number(point[1])
        for point in box
    ):
        return [(float(point[0]), float(point[1])) for point in box]

    flat = [float(value) for value in box if _is_number(value)]
    if len(flat) >= 4 and len(flat) % 2 == 0:
        return [(flat[i], flat[i + 1]) for i in range(0, len(flat), 2)]

    if len(box) == 1 and isinstance(box[0], list | tuple):
        return _box_points(box[0])

    return []


def _box_metrics(box: Any) -> dict[str, float] | None:
    points = _box_points(box)
    if not points:
        return None

    xs = [x for x, _ in points]
    ys = [y for _, y in points]
    y_top = min(ys)
    y_bottom = max(ys)
    return {
        "x_left": min(xs),
        "y_center": (y_top + y_bottom) / 2.0,
        "height": max(1.0, y_bottom - y_top),
    }


def normalize_predict_result(raw: Any) -> list[Line]:
    lines: list[Line] = []

    for page in _iter_pages(raw):
        mapping = _as_mapping(page)
        if mapping is None:
            continue

        texts = _as_list(mapping.get("rec_texts"))
        scores = _as_list(mapping.get("rec_scores"))
        boxes = _as_list(_first_present(mapping, "rec_polys", "rec_boxes", "dt_polys", "boxes"))

        if texts:
            for index, text in enumerate(texts):
                clean_text = str(text).strip()
                if not clean_text:
                    continue

                lines.append(
                    {
                        "text": clean_text,
                        "score": _score_at(scores, index),
                        "box": _box_at(boxes, index),
                    }
                )
            continue

        text = str(mapping.get("text", "")).strip()
        if text:
            lines.append(
                {
                    "text": text,
                    "score": _coerce_score(mapping.get("score")),
                    "box": _coerce_box(mapping.get("box") or mapping.get("poly") or []),
                }
            )

    return lines


def _iter_pages(raw: Any) -> Iterable[Any]:
    if isinstance(raw, list | tuple):
        return raw

    return [raw]


def _as_mapping(value: Any) -> Mapping[str, Any] | None:
    if isinstance(value, Mapping):
        return value

    for attribute in ("to_dict", "dict", "json"):
        method = getattr(value, attribute, None)
        if callable(method):
            converted = method()
            if isinstance(converted, str):
                converted = json.loads(converted)
            if isinstance(converted, Mapping):
                return converted

    return None


def _as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    tolist = getattr(value, "tolist", None)
    if callable(tolist):
        return _as_list(tolist())
    if isinstance(value, list):
        return value
    if isinstance(value, tuple):
        return list(value)

    return [value]


def _score_at(scores: list[Any], index: int) -> float:
    if index >= len(scores):
        return 0.0

    return _coerce_score(scores[index])


def _coerce_score(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _box_at(boxes: list[Any], index: int) -> Any:
    if index >= len(boxes):
        return []

    return _coerce_box(boxes[index])


def _coerce_box(value: Any) -> Any:
    if value is None:
        return []
    tolist = getattr(value, "tolist", None)
    if callable(tolist):
        return _coerce_box(tolist())
    if isinstance(value, tuple):
        return [_coerce_box(item) for item in value]
    if isinstance(value, list):
        return [_coerce_box(item) for item in value]
    if isinstance(value, int | float):
        return value

    return value


def _first_present(mapping: Mapping[str, Any], *keys: str) -> Any:
    for key in keys:
        value = mapping.get(key)
        if value is not None:
            return value

    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Run local PaddleOCR and print normalized JSON.")
    parser.add_argument("image_path", type=Path)
    args = parser.parse_args()

    document = recognize_image(args.image_path)
    print(json.dumps(document, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
