"""Bake authored GIFs into Web-compatible PNG atlases without losing frame timing.
Run from the repository root with Pillow installed. Original assets stay untouched.
"""
import json
import math
from pathlib import Path
from PIL import Image, ImageSequence

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'models/objects/textures/logo'
OUTPUT = SOURCE / 'runtime'
FRAME_SIZE = (320, 180)


def build():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name in ('intro', 'sequence', 'symbol_rotation'):
        source = SOURCE / ('VECTRION_' + name + '.gif')
        with Image.open(source) as gif:
            columns = math.ceil(math.sqrt(gif.n_frames))
            rows = math.ceil(gif.n_frames / columns)
            # One-pixel gutters avoid neighboring frames leaking during filtering.
            cell = (FRAME_SIZE[0] + 2, FRAME_SIZE[1] + 2)
            atlas = Image.new('RGB', (columns * cell[0], rows * cell[1]))
            durations = []
            last_tile = None
            repaired_frames = []
            for i, frame in enumerate(ImageSequence.Iterator(gif)):
                try:
                    tile = frame.convert('RGB').resize(FRAME_SIZE, Image.Resampling.LANCZOS)
                except OSError:
                    if name != 'symbol_rotation' or i != gif.n_frames - 1 or last_tile is None:
                        raise
                    # Authored rotation GIF ends with an incomplete last LZW frame.
                    tile = last_tile.copy()
                    repaired_frames.append(i)
                last_tile = tile
                x, y = (i % columns) * cell[0], (i // columns) * cell[1]
                atlas.paste(tile, (x + 1, y + 1))
                atlas.paste(tile.crop((0, 0, 1, 180)), (x, y + 1))
                atlas.paste(tile.crop((319, 0, 320, 180)), (x + 321, y + 1))
                atlas.paste(tile.crop((0, 0, 320, 1)), (x + 1, y))
                atlas.paste(tile.crop((0, 179, 320, 180)), (x + 1, y + 181))
                for dx, dy, tx, ty in [(0, 0, 0, 0), (321, 0, 319, 0),
                                      (0, 181, 0, 179), (321, 181, 319, 179)]:
                    atlas.putpixel((x + dx, y + dy), tile.getpixel((tx, ty)))
                durations.append(max(10, frame.info.get('duration', 50)) / 1000.0)
            atlas.save(OUTPUT / (name + '.png'), optimize=True)
            metadata = {'version': 1, 'columns': columns, 'rows': rows,
                        'frame_size': list(FRAME_SIZE), 'cell_size': list(cell),
                        'durations': durations, 'source': source.name, 'held_frames': repaired_frames}
            (OUTPUT / (name + '.json')).write_text(json.dumps(metadata, indent=2) + '\n')
            print(name, len(durations), round(sum(durations), 2), atlas.size)


if __name__ == '__main__':
    build()
