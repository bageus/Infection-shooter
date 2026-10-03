"""Bundle the supplied body font so the project theme loads before first import."""
import base64
from pathlib import Path

root = Path(__file__).resolve().parents[1]
font = root / 'assets/interface/fonts/body.ttf'
data = base64.b64encode(font.read_bytes()).decode('ascii')
(root / 'assets/interface/game_theme.tres').write_text(
    '[gd_resource type="Theme" load_steps=2 format=3]\n\n'
    '[sub_resource type="FontFile" id="body"]\n'
    f'data = PackedByteArray("{data}")\n\n'
    '[resource]\n'
    'default_font = SubResource("body")\n'
    'default_font_size = 16\n'
)
