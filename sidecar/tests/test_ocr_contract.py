import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

from PIL import Image, ImageDraw

from screen_ocr_sidecar.ocr import (
    normalize_korean_spacing,
    normalize_predict_result,
    recognize_image,
    recognized_text,
)
from screen_ocr_sidecar.preprocess import preprocess_image_for_ocr
from screen_ocr_sidecar.worker import handle_request


class OCRContractTests(unittest.TestCase):
    def test_normalizes_paddle_v3_mapping_result(self):
        raw = [
            {
                "rec_texts": ["OCR 테스트", "Hello 123"],
                "rec_scores": [0.97, 0.95],
                "rec_polys": [
                    [[0, 0], [90, 0], [90, 20], [0, 20]],
                    [[0, 30], [100, 30], [100, 50], [0, 50]],
                ],
            }
        ]

        lines = normalize_predict_result(raw)

        self.assertEqual(
            lines,
            [
                {
                    "text": "OCR 테스트",
                    "score": 0.97,
                    "box": [[0, 0], [90, 0], [90, 20], [0, 20]],
                },
                {
                    "text": "Hello 123",
                    "score": 0.95,
                    "box": [[0, 30], [100, 30], [100, 50], [0, 50]],
                },
            ],
        )

    def test_recognize_image_uses_injected_ocr_factory(self):
        image_path = Path("fixtures/ocr/mixed-ko-en-simple.png")

        document = recognize_image(image_path, ocr_factory=lambda: FakeOCR())

        self.assertEqual(document["image_path"], str(image_path))
        self.assertEqual(document["text"], "OCR 테스트\nHello 123")
        self.assertEqual(document["line_count"], 2)
        self.assertEqual(document["lines"][0]["score"], 0.97)

    def test_recognize_image_limits_detector_input_for_screen_crops(self):
        image_path = Path("fixtures/ocr/mixed-ko-en.png")
        ocr = FakeOCR()

        recognize_image(image_path, ocr_factory=lambda: ocr)

        self.assertEqual(
            ocr.predict_options,
            {
                "text_det_limit_side_len": 1536,
                "text_det_limit_type": "max",
            },
        )

    def test_recognized_text_skips_empty_lines(self):
        lines = [
            {"text": " OCR 테스트 ", "score": 0.9, "box": []},
            {"text": "  ", "score": 0.1, "box": []},
            {"text": "Hello", "score": 0.8, "box": []},
        ]

        self.assertEqual(recognized_text(lines), "OCR 테스트\nHello")

    def test_recognized_text_reconstructs_rows_and_reading_order_from_boxes(self):
        # Detection order is scrambled and a single visual line is split across two
        # boxes; layout reconstruction must merge same-row fragments left-to-right
        # with a space and keep the lower line separate.
        lines = [
            {"text": "world", "score": 0.9, "box": [[120, 0], [200, 0], [200, 20], [120, 20]]},
            {"text": "다음 줄", "score": 0.9, "box": [[0, 40], [100, 40], [100, 60], [0, 60]]},
            {"text": "Hello", "score": 0.9, "box": [[0, 2], [80, 2], [80, 22], [0, 22]]},
        ]

        self.assertEqual(recognized_text(lines), "Hello world\n다음 줄")

    def test_recognized_text_supports_flat_rect_boxes(self):
        lines = [
            {"text": "right", "score": 0.9, "box": [120, 0, 200, 20]},
            {"text": "left", "score": 0.9, "box": [0, 0, 80, 20]},
        ]

        self.assertEqual(recognized_text(lines), "left right")

    def test_normalize_korean_spacing_restores_spaces_next_to_punctuation(self):
        cases = {
            "보세요.이제 줄": "보세요. 이제 줄",
            "합니다.추가로": "합니다. 추가로",
            "원하시면(예:": "원하시면 (예:",
            "2540×132(한": "2540×132 (한",
            "복사.(내": "복사. (내",
            "확인)이제": "확인) 이제",
            "-캡처가": "- 캡처가",
        }
        for raw, expected in cases.items():
            self.assertEqual(normalize_korean_spacing(raw), expected, raw)

    def test_normalize_korean_spacing_leaves_code_and_numbers_intact(self):
        # Latin/digit boundaries must be untouched so code, paths, versions and numbers
        # are never corrupted by the heuristic.
        unchanged = [
            "3.9.1",
            "screen-ocr",
            "/Users/chans/workspace",
            "f(x)",
            "1,000",
            "Cmd+Shift+0",
            "https://example.com/path",
            "예: 한국어",  # already spaced
        ]
        for text in unchanged:
            self.assertEqual(normalize_korean_spacing(text), text, text)

    def test_normalizes_array_like_boxes_to_json_values(self):
        raw = [
            {
                "rec_texts": ["Hello"],
                "rec_scores": [0.99],
                "rec_boxes": ArrayLike([[[1, 2], [3, 4]]]),
            }
        ]

        lines = normalize_predict_result(raw)

        self.assertEqual(lines[0]["box"], [[1, 2], [3, 4]])

    def test_worker_request_reuses_loaded_ocr_instance(self):
        ocr = FakeOCR()

        response = handle_request(
            {"id": "req-1", "image_path": "fixtures/ocr/mixed-ko-en-simple.png"},
            ocr,
        )

        self.assertTrue(response["ok"])
        self.assertEqual(response["id"], "req-1")
        self.assertEqual(response["text"], "OCR 테스트\nHello 123")
        self.assertEqual(response["line_count"], 2)
        self.assertEqual(ocr.predict_call_count, 1)
        self.assertEqual(response["diagnostics"]["preprocess_applied"], 0)
        self.assertEqual(response["metadata"]["preprocess_status"], "skipped_small")
        self.assertGreaterEqual(response["request_elapsed_ms"], 0)

    def test_recognize_image_filters_lines_below_min_score(self):
        image_path = Path("fixtures/ocr/mixed-ko-en-simple.png")

        document = recognize_image(image_path, ocr_factory=lambda: LowScoreOCR(), min_score=0.5)

        self.assertEqual(document["line_count"], 1)
        self.assertEqual(document["text"], "OCR 테스트")

    def test_recognize_image_keeps_all_lines_when_min_score_is_default(self):
        image_path = Path("fixtures/ocr/mixed-ko-en-simple.png")

        document = recognize_image(image_path, ocr_factory=lambda: LowScoreOCR())

        self.assertEqual(document["line_count"], 2)
        self.assertEqual(document["text"], "OCR 테스트\nnoise")

    def test_worker_response_lines_omit_box_payload(self):
        response = handle_request(
            {"id": "req-slim", "image_path": "fixtures/ocr/mixed-ko-en-simple.png"},
            FakeOCR(),
        )

        self.assertTrue(response["ok"])
        self.assertEqual(response["line_count"], 2)
        self.assertTrue(response["lines"])
        for line in response["lines"]:
            self.assertEqual(set(line.keys()), {"text", "score"})

    def test_worker_honors_min_line_score_env(self):
        with mock.patch.dict(os.environ, {"SCREEN_OCR_MIN_LINE_SCORE": "0.5"}):
            response = handle_request(
                {"id": "req-filter", "image_path": "fixtures/ocr/mixed-ko-en-simple.png"},
                LowScoreOCR(),
            )

        self.assertTrue(response["ok"])
        self.assertEqual(response["line_count"], 1)
        self.assertEqual(response["text"], "OCR 테스트")

    def test_worker_ignores_invalid_min_line_score_env(self):
        with mock.patch.dict(os.environ, {"SCREEN_OCR_MIN_LINE_SCORE": "not-a-number"}):
            response = handle_request(
                {"id": "req-bad-env", "image_path": "fixtures/ocr/mixed-ko-en-simple.png"},
                LowScoreOCR(),
            )

        self.assertTrue(response["ok"])
        self.assertEqual(response["line_count"], 2)

    def test_worker_request_reports_missing_image_path(self):
        response = handle_request({"id": "req-2"}, FakeOCR())

        self.assertFalse(response["ok"])
        self.assertEqual(response["id"], "req-2")
        self.assertIn("image_path", response["error"])

    def test_worker_request_can_disable_preprocessing_for_benchmark_baseline(self):
        response = handle_request(
            {
                "id": "req-3",
                "image_path": "fixtures/ocr/mixed-ko-en-simple.png",
                "preprocess": False,
            },
            FakeOCR(),
        )

        self.assertTrue(response["ok"])
        self.assertEqual(response["metadata"]["preprocess_status"], "disabled")
        self.assertEqual(response["diagnostics"]["preprocess_applied"], 0)

    def test_preprocess_trims_large_mostly_empty_image(self):
        with TemporaryDirectory() as directory:
            source = Path(directory) / "large-empty.png"
            image = Image.new("RGB", (1600, 1000), "white")
            draw = ImageDraw.Draw(image)
            draw.rectangle((720, 430, 890, 470), fill="black")
            draw.rectangle((720, 500, 980, 540), fill="black")
            image.save(source)

            result = preprocess_image_for_ocr(source)

            self.assertTrue(result.applied)
            self.assertEqual(result.original_width, 1600)
            self.assertEqual(result.original_height, 1000)
            self.assertLess(result.preprocessed_width, 400)
            self.assertLess(result.preprocessed_height, 300)
            self.assertTrue(Path(result.ocr_image_path).exists())
            self.assertIn(".preprocessed", result.ocr_image_path)

    def test_preprocess_keeps_small_image_path(self):
        with TemporaryDirectory() as directory:
            source = Path(directory) / "small.png"
            Image.new("RGB", (320, 120), "white").save(source)

            result = preprocess_image_for_ocr(source)

            self.assertFalse(result.applied)
            self.assertEqual(result.status, "skipped_small")
            self.assertEqual(result.ocr_image_path, str(source))


class FakeOCR:
    def __init__(self):
        self.predict_options = None
        self.predict_call_count = 0

    def predict(self, image_path, **kwargs):
        self.predict_call_count += 1
        self.predict_options = kwargs
        return [
            {
                "rec_texts": ["OCR 테스트", "Hello 123"],
                "rec_scores": [0.97, 0.95],
                "rec_boxes": [
                    [0, 0, 90, 20],
                    [0, 30, 100, 50],
                ],
            }
        ]


class LowScoreOCR:
    def __init__(self):
        self.predict_call_count = 0

    def predict(self, image_path, **kwargs):
        self.predict_call_count += 1
        return [
            {
                "rec_texts": ["OCR 테스트", "noise"],
                "rec_scores": [0.97, 0.40],
                "rec_boxes": [
                    [0, 0, 90, 20],
                    [0, 30, 100, 50],
                ],
            }
        ]


class ArrayLike:
    def __init__(self, value):
        self.value = value

    def tolist(self):
        return self.value


if __name__ == "__main__":
    unittest.main()
