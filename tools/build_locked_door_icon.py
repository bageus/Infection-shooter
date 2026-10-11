"""Draw the locked-door marker icon in the style of assets/icon_interface.png.

Thick black outline, flat cyan fill, darker cyan shading on the lower-right
edges and black detail lines, so it tints like the atlas weapon and key icons.
Run: python3 tools/build_locked_door_icon.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "interface" / "icon" / "locked_door.png"
SIZE = 256
SS = 4  # supersampling factor

OUTLINE = (0, 0, 0, 255)
FILL = (113, 234, 252, 255)
SHADE = (52, 168, 196, 255)
LIGHT = (196, 248, 255, 255)
DARK = (10, 40, 52, 255)


def s(*values: float) -> list[float]:
    return [v * SS for v in values]


def rounded(draw: ImageDraw.ImageDraw, box, radius, fill, outline=None, width=0):
    draw.rounded_rectangle(s(*box), radius * SS, fill=fill, outline=outline, width=width * SS)


def main() -> None:
    image = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    stroke = 9

    # Door frame and slab.
    rounded(draw, (40, 14, 192, 244), 10, OUTLINE)
    rounded(draw, (40 + stroke, 14 + stroke, 192 - stroke, 244 - stroke), 5, SHADE)
    rounded(draw, (60, 32, 172, 236), 6, OUTLINE)
    rounded(draw, (60 + stroke - 2, 32 + stroke - 2, 172 - stroke + 2, 236 - stroke + 2), 4, FILL)
    # Shading on the slab's right and bottom edges, highlight on the left.
    draw.rectangle(s(152, 40, 163, 228), fill=SHADE)
    draw.rectangle(s(68, 216, 163, 228), fill=SHADE)
    draw.rectangle(s(68, 42, 74, 206), fill=LIGHT)
    # Inset panels as black detail lines.
    for top, bottom in ((54, 120), (136, 198)):
        rounded(draw, (80, top, 144, bottom), 4, None, OUTLINE, 6)
    # Handle.
    draw.ellipse(s(148, 128, 162, 142), fill=OUTLINE)

    # Padlock over the lower right corner.
    shackle_box = (150, 112, 222, 186)
    draw.arc(s(*shackle_box), 180, 360, fill=OUTLINE, width=26 * SS)
    draw.arc(s(shackle_box[0] + 8, shackle_box[1] + 8, shackle_box[2] - 8, shackle_box[3] - 8), 180, 360, fill=FILL, width=10 * SS)
    draw.rectangle(s(150, 148, 176, 168), fill=OUTLINE)
    draw.rectangle(s(196, 148, 222, 168), fill=OUTLINE)
    draw.rectangle(s(158, 148, 168, 166), fill=FILL)
    draw.rectangle(s(204, 148, 214, 166), fill=FILL)
    rounded(draw, (132, 158, 240, 246), 12, OUTLINE)
    rounded(draw, (132 + stroke, 158 + stroke, 240 - stroke, 246 - stroke), 6, FILL)
    draw.rectangle(s(216, 170, 228, 234), fill=SHADE)
    draw.rectangle(s(144, 224, 228, 234), fill=SHADE)
    draw.rectangle(s(144, 170, 150, 218), fill=LIGHT)
    # Keyhole.
    draw.ellipse(s(176, 182, 196, 202), fill=DARK)
    draw.polygon(s(181, 196, 191, 196, 195, 222, 177, 222), fill=DARK)

    image = image.resize((SIZE, SIZE), Image.LANCZOS)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT)
    print(f"wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
