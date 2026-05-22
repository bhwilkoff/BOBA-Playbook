#!/usr/bin/env python3
"""Wrap raw 1280x2856 Play Store screenshots in the phone-bezel mockup.

Reads each tools/play-assets/out/screenshot-N-*.png, composites it into
the screen-area cutout of tools/screenshots/public/mockup.png (the same
asset the Next.js marketing-screenshot generator uses), and writes the
framed result to tools/play-assets/out/framed/.

Why both raw + framed?
- Google Play Console accepts either. Some apps prefer the raw screens
  (pixel-perfect, no chrome); some prefer the bezel-wrapped versions
  (read as device-on-the-page in the listing carousel).
- Bezel-wrapped versions are also useful for TestFlight invites,
  release notes, social posts, the BoBA Discord, etc.

Output is upscaled so the screen area inside the mockup matches the
native 1280-px capture width. The mockup itself ends up around
1424x2902, well above Play Console's 1080-px short-edge minimum.

Deps: pip install pillow
Run:  python3 tools/play-assets/frame-screens.py
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("ERROR: Pillow not installed. Run: pip install pillow", file=sys.stderr)
    sys.exit(1)


REPO_ROOT = Path(__file__).resolve().parent.parent.parent
MOCKUP = REPO_ROOT / "tools" / "screenshots" / "public" / "mockup.png"
RAW_DIR = REPO_ROOT / "tools" / "play-assets" / "out"
FRAMED_DIR = RAW_DIR / "framed"

# Mockup screen-area constants — match
# tools/screenshots/src/app/ScreenshotsClient.tsx (MK_W / SC_L / etc.).
# These describe where the transparent screen window sits inside the
# 1022x2082 bezel PNG, plus the corner radius for rounded-corner masking.
MK_W, MK_H = 1022, 2082
SC_L, SC_T = 52, 46
SC_W, SC_H = 918, 1990
SC_CORNER_RADIUS = 126  # both x + y radii in mockup px


def rounded_corner_mask(size: tuple[int, int], radius: int) -> Image.Image:
    """Build an L-mode alpha mask with rounded corners. Used to clip
    the screenshot to the same corner shape as the bezel's screen
    cutout."""
    w, h = size
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)
    return mask


def frame_one(screenshot_path: Path, output_path: Path) -> None:
    mockup = Image.open(MOCKUP).convert("RGBA")
    shot = Image.open(screenshot_path).convert("RGBA")

    # Upscale the mockup so the screen-area width matches the
    # screenshot's native width — preserves the capture's full
    # resolution. Scale = shot.width / SC_W.
    scale = shot.width / SC_W
    mk_w = round(MK_W * scale)
    mk_h = round(MK_H * scale)
    sc_l = round(SC_L * scale)
    sc_t = round(SC_T * scale)
    sc_w = round(SC_W * scale)
    sc_h = round(SC_H * scale)
    sc_rad = round(SC_CORNER_RADIUS * scale)

    mockup_scaled = mockup.resize((mk_w, mk_h), Image.Resampling.LANCZOS)

    # Resize screenshot to exactly fill the screen area. Aspect
    # difference between Pixel 9 Pro (1280:2856 ≈ 0.4483) and the
    # mockup screen (918:1990 ≈ 0.4613) is ~3% — visually invisible.
    shot_resized = shot.resize((sc_w, sc_h), Image.Resampling.LANCZOS)

    # Clip the screenshot to the bezel's corner radius.
    mask = rounded_corner_mask((sc_w, sc_h), sc_rad)
    shot_resized.putalpha(mask)

    # Composite: mockup as base layer → paste screenshot ON TOP at
    # the screen-window position. The mockup PNG has a solid (not
    # transparent) black screen area, so the screenshot must be
    # painted over it. The screenshot is rounded-corner masked so
    # it doesn't bleed onto the bezel chrome at the corners.
    # Mirrors the original Next.js Phone component (which used
    # z-index + absolute positioning to stack screenshot over the
    # mockup `<img>`).
    canvas = mockup_scaled.copy()
    canvas.paste(shot_resized, (sc_l, sc_t), shot_resized)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output_path, "PNG", optimize=True)
    size_kb = output_path.stat().st_size / 1024
    print(f"  ✓ {output_path.name}  ({size_kb:.0f} KB, {canvas.width}x{canvas.height})")


def main():
    if not MOCKUP.exists():
        print(f"ERROR: mockup.png not found at {MOCKUP}", file=sys.stderr)
        sys.exit(1)

    raw_shots = sorted(RAW_DIR.glob("screenshot-[0-9]-*.png"))
    if not raw_shots:
        print(f"ERROR: no screenshot-N-*.png files in {RAW_DIR}", file=sys.stderr)
        sys.exit(1)

    print(f"Framing {len(raw_shots)} screenshots via {MOCKUP.name}...")
    for shot in raw_shots:
        out = FRAMED_DIR / shot.name
        frame_one(shot, out)

    print(f"\nDone. Output in {FRAMED_DIR.relative_to(REPO_ROOT)}/")


if __name__ == "__main__":
    main()
