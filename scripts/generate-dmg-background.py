#!/usr/bin/env python3
"""Generate branded DMG background images for Look Ma No Hands installer.

Produces:
  Resources/dmg-background@2x.png  (1320x800, Retina)
  Resources/dmg-background.png     (660x400, standard)

Uses the app's navy→teal gradient palette and draws a curved arrow
guiding users to drag the app icon to the Applications folder.
"""

import math
import os
from PIL import Image, ImageDraw, ImageFont

# --- Dimensions (2x Retina) ---
W, H = 1320, 800

# --- Colors (from app icon palette) ---
NAVY = (13, 27, 62)       # #0D1B3E
TEAL = (14, 77, 110)      # #0E4D6E
WHITE = (255, 255, 255)
ARROW_COLOR = (*WHITE, 102)  # ~40% opacity

# --- Icon positions at 2x (matching AppleScript 1x: 170,200 and 490,200) ---
APP_CENTER_X, APP_CENTER_Y = 340, 400
APPS_CENTER_X, APPS_CENTER_Y = 980, 400

# --- Font ---
FONT_PATH = "/System/Library/Fonts/SFNSRounded.ttf"


def lerp_color(c1, c2, t):
    """Linear interpolation between two RGB tuples."""
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def draw_gradient(img, color_top, color_bottom):
    """Draw a vertical gradient on an RGB image."""
    draw = ImageDraw.Draw(img)
    for y in range(img.height):
        t = y / (img.height - 1)
        color = lerp_color(color_top, color_bottom, t)
        draw.line([(0, y), (img.width, y)], fill=color)


def draw_curved_arrow(overlay):
    """Draw a curved arrow from left icon zone to right icon zone."""
    draw = ImageDraw.Draw(overlay)

    # Arc parameters — arrow curves upward between icon zones
    num_points = 200
    points = []

    start_x = APP_CENTER_X + 100  # start right of app icon
    end_x = APPS_CENTER_X - 100   # end left of Applications icon
    arc_height = 120               # how high the arc rises

    for i in range(num_points):
        t = i / (num_points - 1)
        x = start_x + (end_x - start_x) * t
        # Parabolic arc: highest at center, level at endpoints
        y = APP_CENTER_Y - arc_height * 4 * t * (1 - t)
        points.append((x, y))

    # Draw the arc as a thick line
    for i in range(len(points) - 1):
        draw.line([points[i], points[i + 1]], fill=ARROW_COLOR, width=6)

    # Arrowhead at the end
    tip_x, tip_y = points[-1]
    # Get direction from second-to-last point
    prev_x, prev_y = points[-4]
    angle = math.atan2(tip_y - prev_y, tip_x - prev_x)
    head_len = 36
    head_angle = math.radians(28)

    for sign in (-1, 1):
        bx = tip_x - head_len * math.cos(angle + sign * head_angle)
        by = tip_y - head_len * math.sin(angle + sign * head_angle)
        draw.line([(tip_x, tip_y), (bx, by)], fill=ARROW_COLOR, width=6)


def draw_text(overlay):
    """Draw app name and 'Drag to install' label."""
    draw = ImageDraw.Draw(overlay)

    # App name near top
    try:
        font_title = ImageFont.truetype(FONT_PATH, 52)
        font_subtitle = ImageFont.truetype(FONT_PATH, 28)
    except OSError:
        font_title = ImageFont.load_default()
        font_subtitle = ImageFont.load_default()

    # Title
    title = "Look Ma No Hands"
    bbox = draw.textbbox((0, 0), title, font=font_title)
    tw = bbox[2] - bbox[0]
    draw.text(
        ((W - tw) / 2, 60),
        title,
        fill=(*WHITE, 230),
        font=font_title,
    )

    # Subtitle — centered below the arrow arc
    subtitle = "Drag to Applications to install"
    bbox2 = draw.textbbox((0, 0), subtitle, font=font_subtitle)
    sw = bbox2[2] - bbox2[0]
    draw.text(
        ((W - sw) / 2, 560),
        subtitle,
        fill=(*WHITE, 153),  # ~60% opacity
        font=font_subtitle,
    )


def add_subtle_glow(overlay):
    """Add a subtle radial glow behind the arrow area for depth."""
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    cx, cy = W // 2, 370
    radius = 300
    for r in range(radius, 0, -2):
        alpha = int(18 * (1 - r / radius))
        draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=(100, 200, 255, alpha),
        )
    composited = Image.alpha_composite(overlay, glow)
    overlay.paste(composited, mask=composited)


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    resources_dir = os.path.join(repo_root, "Resources")

    # 1. Gradient background (RGB)
    bg = Image.new("RGB", (W, H))
    draw_gradient(bg, NAVY, TEAL)

    # 2. Overlay layer (RGBA) for arrow + text with transparency
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    add_subtle_glow(overlay)
    draw_curved_arrow(overlay)
    draw_text(overlay)

    # 3. Composite
    result = Image.alpha_composite(bg.convert("RGBA"), overlay)
    final = result.convert("RGB")

    # 4. Save 2x
    path_2x = os.path.join(resources_dir, "dmg-background@2x.png")
    final.save(path_2x, "PNG")
    print(f"Created: {path_2x}")

    # 5. Save 1x (downscaled)
    path_1x = os.path.join(resources_dir, "dmg-background.png")
    final_1x = final.resize((660, 400), Image.LANCZOS)
    final_1x.save(path_1x, "PNG")
    print(f"Created: {path_1x}")


if __name__ == "__main__":
    main()
