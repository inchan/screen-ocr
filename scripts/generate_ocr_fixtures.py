#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VENV_PYTHON = ROOT / ".venv-ocr" / "bin" / "python"

if VENV_PYTHON.exists() and Path(sys.executable).resolve() != VENV_PYTHON.resolve():
    os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), *sys.argv])

from PIL import Image, ImageDraw, ImageFont

MANIFEST_PATH = ROOT / "fixtures" / "ocr" / "manifest.json"


def main() -> int:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    for fixture in manifest["fixtures"]:
        image_path = ROOT / fixture["path"]
        image_path.parent.mkdir(parents=True, exist_ok=True)
        render_fixture(fixture, image_path)
        print(f"generated {image_path.relative_to(ROOT)}")

    return 0


def render_fixture(fixture: dict, image_path: Path) -> None:
    image = Image.new(
        "RGB",
        (fixture["width"], fixture["height"]),
        fixture["background"],
    )
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(fixture["font_path"], fixture["font_size"])

    x = 48
    y = 44
    line_spacing = int(fixture["font_size"] * 1.35)
    for line in fixture["expected_text"].splitlines():
        draw.text((x, y), line, font=font, fill=fixture["foreground"])
        y += line_spacing

    image.save(image_path)


if __name__ == "__main__":
    raise SystemExit(main())
