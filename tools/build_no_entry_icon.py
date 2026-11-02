"""Draw the one-way "no entry" marker: a crossed circle like the reference sign.

Black outline and slash on a light disc, so it tints like the locked-door icon
(the world badge multiplies the light channel by the tint colour).
Run: python3 tools/build_no_entry_icon.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "interface" / "icon" / "no_entry.png"
SIZE = 256
SS = 4  # supersampling factor

OUTLINE = (0, 0, 0, 255)
FILL = (255, 255, 255, 255)
CENTER = 128
OUTER = 122
RING = 14
SLASH = 30


def s(value: float) -> float:
    return value * SS


def main() -> None:
    image = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    c = s(CENTER)
    draw.ellipse((c - s(OUTER), c - s(OUTER), c + s(OUTER), c + s(OUTER)), fill=OUTLINE)
    inner = OUTER - RING
    draw.ellipse((c - s(inner), c - s(inner), c + s(inner), c + s(inner)), fill=FILL)
    # Diagonal bar from upper right to lower left, cut short of the ring.
    reach = inner - 6
    dx = dy = reach / 2 ** 0.5
    draw.line(
        (c + s(dx), c - s(dy), c - s(dx), c + s(dy)),
        fill=OUTLINE,
        width=int(s(SLASH)),
    )
    image = image.resize((SIZE, SIZE), Image.LANCZOS)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT)
    print(f"wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
