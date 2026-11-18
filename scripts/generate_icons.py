#!/usr/bin/env python3
"""Generates all required iOS & iPadOS AppIcon PNGs + Contents.json using macOS sips."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPICON_DIR = ROOT / "App" / "Assets.xcassets" / "AppIcon.appiconset"
ACCENT_DIR = ROOT / "App" / "Assets.xcassets" / "AccentColor.colorset"
MASTER = APPICON_DIR / "icon-1024.png"

# Standard iOS + iPadOS + Single-size 1024 entries
ICON_SPECS = [
    ("20x20", "iphone", "2x", 40, "icon-20@2x.png"),
    ("20x20", "iphone", "3x", 60, "icon-20@3x.png"),
    ("29x29", "iphone", "2x", 58, "icon-29@2x.png"),
    ("29x29", "iphone", "3x", 87, "icon-29@3x.png"),
    ("40x40", "iphone", "2x", 80, "icon-40@2x.png"),
    ("40x40", "iphone", "3x", 120, "icon-40@3x.png"),
    ("60x60", "iphone", "2x", 120, "icon-60@2x.png"),
    ("60x60", "iphone", "3x", 180, "icon-60@3x.png"),
    ("20x20", "ipad", "1x", 20, "icon-ipad-20@1x.png"),
    ("20x20", "ipad", "2x", 40, "icon-ipad-20@2x.png"),
    ("29x29", "ipad", "1x", 29, "icon-ipad-29@1x.png"),
    ("29x29", "ipad", "2x", 58, "icon-ipad-29@2x.png"),
    ("40x40", "ipad", "1x", 40, "icon-ipad-40@1x.png"),
    ("40x40", "ipad", "2x", 80, "icon-ipad-40@2x.png"),
    ("76x76", "ipad", "1x", 76, "icon-ipad-76@1x.png"),
    ("76x76", "ipad", "2x", 152, "icon-ipad-76@2x.png"),
    ("83.5x83.5", "ipad", "2x", 167, "icon-ipad-83.5@2x.png"),
    ("1024x1024", "ios-marketing", "1x", 1024, "icon-1024.png"),
]


def main() -> None:
    if not MASTER.exists():
        raise FileNotFoundError(f"Master icon missing: {MASTER}")
    APPICON_DIR.mkdir(parents=True, exist_ok=True)
    ACCENT_DIR.mkdir(parents=True, exist_ok=True)

    images = []
    generated_files = set()
    for size, idiom, scale, px, filename in ICON_SPECS:
        dest = APPICON_DIR / filename
        if filename not in generated_files and dest != MASTER:
            subprocess.run(
                ["sips", "-z", str(px), str(px), str(MASTER), "--out", str(dest)],
                check=True,
                stdout=subprocess.DEVNULL,
            )
            generated_files.add(filename)
        images.append({
            "filename": filename,
            "idiom": idiom,
            "scale": scale,
            "size": size,
        })

    (APPICON_DIR / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
        encoding="utf-8",
    )

    (APPICON_DIR.parent / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
        encoding="utf-8",
    )

    (ACCENT_DIR / "Contents.json").write_text(
        json.dumps({
            "colors": [
                {
                    "color": {
                        "color-space": "srgb",
                        "components": {"alpha": "1.000", "blue": "0.067", "green": "0.067", "red": "0.067"},
                    },
                    "idiom": "universal",
                },
                {
                    "appearances": [
                        {"appearance": "luminosity", "value": "dark"}
                    ],
                    "color": {
                        "color-space": "srgb",
                        "components": {"alpha": "1.000", "blue": "0.929", "green": "0.953", "red": "0.957"},
                    },
                    "idiom": "universal",
                },
            ],
            "info": {"author": "xcode", "version": 1},
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Generated {len(ICON_SPECS)} icon entries in {APPICON_DIR}")


if __name__ == "__main__":
    main()
