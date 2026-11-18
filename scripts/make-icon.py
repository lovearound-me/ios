#!/usr/bin/env python3
"""Draws the app's icon: the warm gradient of the Mac and Linux icons up to
the edges (watchOS cuts it to a circle, iOS rounds the corners) and the same
white heart. One picture for the watch and the iPhone.

    python3 scripts/make-icon.py    # writes {Watch,Phone}/Assets.xcassets/AppIcon.appiconset/AppIcon.png

Needs pycairo and Pillow. The heart is linux/lovearound/icons.py's.
"""
import io
import os

import cairo
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTS = [os.path.join(ROOT, app, "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png") for app in ("Watch", "Phone")]
PX = 1024


def heart_path(cr, cx, cy, size):
    """A heart centered on (cx, cy), `size` wide."""
    s = size / 2
    cr.move_to(cx, cy + s * 0.85)
    cr.curve_to(cx - s * 0.2, cy + s * 0.65, cx - s, cy + s * 0.15, cx - s, cy - s * 0.3)
    cr.curve_to(cx - s, cy - s * 0.8, cx - s * 0.45, cy - s * 0.95, cx, cy - s * 0.5)
    cr.curve_to(cx + s * 0.45, cy - s * 0.95, cx + s, cy - s * 0.8, cx + s, cy - s * 0.3)
    cr.curve_to(cx + s, cy + s * 0.15, cx + s * 0.2, cy + s * 0.65, cx, cy + s * 0.85)
    cr.close_path()


surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, PX, PX)
cr = cairo.Context(surface)
gradient = cairo.LinearGradient(0, 0, 0, PX)
gradient.add_color_stop_rgb(0, 0.96, 0.52, 0.47)
gradient.add_color_stop_rgb(1, 0.85, 0.30, 0.43)
cr.set_source(gradient)
cr.paint()
heart_path(cr, PX / 2, PX / 2 + PX * 0.02, PX * 0.52)
cr.set_source_rgb(1, 0.98, 0.96)
cr.fill()

# The App Store refuses an icon with an alpha channel.
png = io.BytesIO()
surface.write_to_png(png)
png.seek(0)
icon = Image.open(png).convert("RGB")
for out in OUTS:
    os.makedirs(os.path.dirname(out), exist_ok=True)
    icon.save(out)
    print(out)
