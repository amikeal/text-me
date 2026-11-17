#!/usr/bin/env python3
"""Regenerates Cubby/Resources/Assets.xcassets: the color sets and the placeholder app icon.

Run from the repository root:  python3 Tools/make_assets.py
Needs Pillow for the icon (pip install pillow).
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Cubby" / "Resources" / "Assets.xcassets"

# name: (light, dark)
COLORS = {
    "AccentColor": ("#2F5BD9", "#8AA8FF"),
    "OnAccent": ("#FFFFFF", "#0E0F11"),
    "Ground": ("#F1F2F4", "#0E0F11"),
    "Card": ("#FFFFFF", "#1C1D21"),
    "DeadlineBackground": ("#FCE9D9", "#4A2A12"),
    "DeadlineForeground": ("#8A3B00", "#FFC89A"),
}

INFO = {"author": "xcode", "version": 1}


def components(hex_color: str) -> dict:
    value = hex_color.lstrip("#")
    return {
        "color-space": "srgb",
        "components": {
            "red": f"0x{value[0:2].upper()}",
            "green": f"0x{value[2:4].upper()}",
            "blue": f"0x{value[4:6].upper()}",
            "alpha": "1.000",
        },
    }


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def make_colors() -> None:
    for name, (light, dark) in COLORS.items():
        write_json(
            ASSETS / f"{name}.colorset" / "Contents.json",
            {
                "colors": [
                    {"idiom": "universal", "color": components(light)},
                    {
                        "idiom": "universal",
                        "appearances": [{"appearance": "luminosity", "value": "dark"}],
                        "color": components(dark),
                    },
                ],
                "info": INFO,
            },
        )


def make_icon() -> None:
    from PIL import Image, ImageDraw

    size = 1024
    scale = 4  # draw large, then shrink, for smooth edges
    canvas = size * scale
    background = (47, 91, 217)
    white = (255, 255, 255)

    image = Image.new("RGB", (canvas, canvas), background)
    draw = ImageDraw.Draw(image)

    def box(x0, y0, x1, y1):
        return [x0 * scale, y0 * scale, x1 * scale, y1 * scale]

    # An open-topped cubby...
    draw.rounded_rectangle(box(262, 330, 762, 800), radius=96 * scale, outline=white, width=64 * scale)
    draw.rectangle(box(230, 300, 794, 470), fill=background)
    # ...with rounded rim ends, and one thing dropping in.
    draw.rounded_rectangle(box(262, 438, 326, 502), radius=32 * scale, fill=white)
    draw.rounded_rectangle(box(698, 438, 762, 502), radius=32 * scale, fill=white)
    draw.ellipse(box(432, 250, 592, 410), fill=white)

    icon_dir = ASSETS / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.LANCZOS).save(icon_dir / "AppIcon.png")
    write_json(
        icon_dir / "Contents.json",
        {
            "images": [
                {"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
            ],
            "info": INFO,
        },
    )


if __name__ == "__main__":
    write_json(ASSETS / "Contents.json", {"info": INFO})
    make_colors()
    make_icon()
    print(f"Wrote {ASSETS.relative_to(ROOT)}")
