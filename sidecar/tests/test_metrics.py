import unittest

from screen_ocr_sidecar.metrics import character_error_rate


class MetricsTests(unittest.TestCase):
    def test_character_error_rate_is_zero_for_exact_match(self):
        self.assertEqual(character_error_rate("OCR 테스트", "OCR 테스트"), 0.0)

    def test_character_error_rate_counts_insertions_deletions_and_substitutions(self):
        self.assertAlmostEqual(character_error_rate("kitten", "sitting"), 3 / 7)

    def test_character_error_rate_handles_empty_expected_text(self):
        self.assertEqual(character_error_rate("", ""), 0.0)
        self.assertEqual(character_error_rate("", "extra"), 1.0)


if __name__ == "__main__":
    unittest.main()

