#!/usr/bin/env python3
"""Install the Play Console icon-512.png as the canonical Android
launcher icon across every density bucket + the adaptive-icon
foreground. Replaces the prior vector-drawable foreground (which
rendered the XOXO marks tighter / with more padding than the
Play Console version, so the home-screen icon never visually
matched the listing).

Output paths:
  android/app/src/main/res/mipmap-{m,h,xh,xxh,xxxh}dpi/
    - ic_launcher.png        (full icon, opaque black bg)
    - ic_launcher_round.png  (same icon with circular alpha mask)
    - ic_launcher_foreground.png  (transparent bg, marks scaled to
      land inside the 66% adaptive-icon safe zone — so circular
      crops in modern launchers don't clip the X corners)

Then updates the adaptive-icon XML to reference the new bitmap
foreground instead of the old vector.

Deps: pip install pillow
Run:  python3 tools/play-assets/install-icon.py
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("ERROR: Pillow not installed. Run: pip install pillow", file=sys.stderr)
    sys.exit(1)


REPO_ROOT  = Path(__file__).resolve().parent.parent.parent
SRC_ICON   = REPO_ROOT / "tools" / "play-assets" / "out" / "icon-512.png"
RES_DIR    = REPO_ROOT / "android" / "app" / "src" / "main" / "res"

# Android density bucket → (folder, square px). Square icons are sized
# per Material spec: 48dp logical × density multiplier.
BUCKETS = [
    ("mipmap-mdpi",    48),
    ("mipmap-hdpi",    72),
    ("mipmap-xhdpi",   96),
    ("mipmap-xxhdpi",  144),
    ("mipmap-xxxhdpi", 192),
]

# Adaptive-icon foreground sizes per Android spec (108dp viewport,
# rendered into the same density buckets). Foreground PNG dims are
# 108dp × density multiplier.
FOREGROUND_BUCKETS = [
    ("mipmap-mdpi",    108),
    ("mipmap-hdpi",    162),
    ("mipmap-xhdpi",   216),
    ("mipmap-xxhdpi",  324),
    ("mipmap-xxxhdpi", 432),
]
# Adaptive icon safe-zone fraction. Marks should fit within this
# central region so a launcher's circular / pill / squircle crop
# doesn't clip them. Spec says safe zone is 72dp out of the 108dp
# viewport (= 66.7%); we use 70% to give a hair of breathing room.
SAFE_ZONE_FRAC = 0.70


def circular_mask(size: int) -> Image.Image:
    """Build an L-mode alpha mask that's a full-bleed circle."""
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    return mask


def chromakey_black(img: Image.Image, threshold: int = 12) -> Image.Image:
    """Replace black pixels (sum of RGB ≤ threshold) with transparent.
    The Play Console icon has a solid black background; we want a
    transparent-bg version for the adaptive-icon foreground so the
    ic_launcher_background drawable shows through cleanly."""
    img = img.convert("RGBA")
    pixels = list(img.getdata())
    new = []
    for r, g, b, a in pixels:
        if r + g + b <= threshold * 3:
            new.append((0, 0, 0, 0))
        else:
            # Keep the orange but at full alpha
            new.append((r, g, b, 255))
    out = Image.new("RGBA", img.size)
    out.putdata(new)
    return out


def main():
    if not SRC_ICON.exists():
        print(f"ERROR: source icon not found at {SRC_ICON}", file=sys.stderr)
        sys.exit(1)

    src = Image.open(SRC_ICON).convert("RGBA")
    print(f"Source: {SRC_ICON.relative_to(REPO_ROOT)}  ({src.width}x{src.height})")

    # Transparent-bg version for the adaptive-icon foreground.
    src_marks_only = chromakey_black(src)

    # --- ic_launcher.png + ic_launcher_round.png at every bucket ---
    print("\nLauncher PNGs (legacy / non-adaptive fallback):")
    for folder, size in BUCKETS:
        out_dir = RES_DIR / folder
        out_dir.mkdir(parents=True, exist_ok=True)

        # Square icon — full Play Console icon as-is
        sq = src.resize((size, size), Image.Resampling.LANCZOS)
        sq.save(out_dir / "ic_launcher.png", "PNG", optimize=True)

        # Round icon — same with circular alpha mask
        rd = sq.copy()
        rd.putalpha(circular_mask(size))
        rd.save(out_dir / "ic_launcher_round.png", "PNG", optimize=True)

        print(f"  ✓ {folder}/  ({size}x{size})")

    # --- ic_launcher_foreground.png at every density (transparent bg,
    # marks centered inside 70% safe zone) ---
    print("\nAdaptive-icon foreground (transparent bg, safe-zone scaled):")
    for folder, size in FOREGROUND_BUCKETS:
        out_dir = RES_DIR / folder
        out_dir.mkdir(parents=True, exist_ok=True)

        # Canvas is `size` px; marks should fit in `size * SAFE_ZONE_FRAC`
        inner = round(size * SAFE_ZONE_FRAC)
        scaled = src_marks_only.resize((inner, inner), Image.Resampling.LANCZOS)

        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        offset = (size - inner) // 2
        canvas.paste(scaled, (offset, offset), scaled)
        canvas.save(out_dir / "ic_launcher_foreground.png", "PNG", optimize=True)
        print(f"  ✓ {folder}/  ({size}x{size}, inner {inner})")

    # --- Update adaptive-icon XML to reference the new bitmap foreground.
    adaptive_xml = RES_DIR / "mipmap-anydpi-v26" / "ic_launcher.xml"
    adaptive_round_xml = RES_DIR / "mipmap-anydpi-v26" / "ic_launcher_round.xml"
    new_content = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
"""
    adaptive_xml.write_text(new_content)
    adaptive_round_xml.write_text(new_content)
    print(f"\nUpdated adaptive-icon XML:")
    print(f"  ✓ {adaptive_xml.relative_to(REPO_ROOT)}")
    print(f"  ✓ {adaptive_round_xml.relative_to(REPO_ROOT)}")

    # The legacy ic_launcher_foreground.xml vector drawable is now
    # unused. Remove it so it doesn't get picked up by any lingering
    # @drawable/ic_launcher_foreground reference.
    legacy = RES_DIR / "drawable" / "ic_launcher_foreground.xml"
    if legacy.exists():
        legacy.unlink()
        print(f"  ✓ removed legacy {legacy.relative_to(REPO_ROOT)}")

    print("\nDone. Rebuild + reinstall the APK to see the new icon.")


if __name__ == "__main__":
    main()
