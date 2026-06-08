from __future__ import annotations

import argparse
import json
from collections.abc import Callable, Iterable, Mapping
from pathlib import Path
from typing import Any


Line = dict[str, Any]
Document = dict[str, Any]
DEFAULT_PREDICT_OPTIONS: Mapping[str, Any] = {
    "text_det_limit_side_len": 736,
    "text_det_limit_type": "max",
}


def create_default_ocr() -> Any:
    from paddleocr import PaddleOCR

    return PaddleOCR(
        text_detection_model_name="PP-OCRv5_mobile_det",
        text_recognition_model_name="korean_PP-OCRv5_mobile_rec",
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
    lines = normalize_predict_result(raw)
    if min_score > 0.0:
        lines = [line for line in lines if _coerce_score(line.get("score")) >= min_score]

    return {
        "image_path": str(path),
        "text": recognized_text(lines),
        "line_count": len(lines),
        "lines": lines,
    }


def recognized_text(lines: Iterable[Mapping[str, Any]]) -> str:
    text_lines = []
    for line in lines:
        text = str(line.get("text", "")).strip()
        if text:
            text_lines.append(text)

    return "\n".join(text_lines)


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
