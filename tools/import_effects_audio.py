#!/usr/bin/env python3
"""Import the owner's second 2026-10-26 batch (destruction, elevator, medkit, blast, spray).

Same flow as import_weapon_audio.py: mono Vorbis next to the event, old variants and the
verified WAV deleted, receipt appended to assets/audio/audio_refresh_processing.json.
Run from tools/: python import_effects_audio.py
"""
import hashlib
import json
import subprocess

from build_added_audio import ROOT, convert
from import_weapon_audio import SFX, unlink


def unlink_wav(stem):
    for suffix in ('.wav', '.wav.import'):
        (SFX / (stem + suffix)).unlink(missing_ok=True)

IMPORTS = {
    'break_electronics/break_electr_1': 'break_electronics/break_electronics_1',
    'break_electronics/break_electr_2': 'break_electronics/break_electronics_2',
    'break_lamp/break_lamp': 'break_lamp/break_lamp_1',
    'break_metal/break_metal_3': 'break_metal/break_metal_3',
    'elevator_open/elevator_open_ring': 'elevator_open/elevator_open_1',
    'elevator_close/elevator_close_ring': 'elevator_close/elevator_close_1',
    'medkit_pickup/medkit_pickup': 'medkit_pickup/medkit_pickup_1',
    'medkit_use/bandage_use': 'medkit_use/medkit_use_1',
    'grenade_explode/grenade_explode': 'grenade_explode/grenade_explode_1',
    'extinguisher_spray/extinguisher_spray': 'extinguisher_spray/extinguisher_spray_1',
}
DELETE = ['break_electronics/break_electronics_3', 'break_lamp/break_lamp_2',
          'grenade_explode/grenade_explode_2', 'extinguisher_spray/extinguisher_spray_2']


def main():
    receipt_path = ROOT / 'assets/audio/audio_refresh_processing.json'
    receipt = json.loads(receipt_path.read_text())
    outputs = {'assets/audio/sfx/' + stem + '.ogg' for stem in IMPORTS.values()}
    receipt['records'] = [r for r in receipt['records'] if r['output'] not in outputs]
    for source, stem in IMPORTS.items():
        wav, target = SFX / (source + '.wav'), SFX / (stem + '.ogg')
        record = convert(wav, target, mono=True)
        record['source_sha256'] = hashlib.sha256(wav.read_bytes()).hexdigest()
        record['output_sha256'] = hashlib.sha256(target.read_bytes()).hexdigest()
        subprocess.run(['ffmpeg', '-v', 'error', '-i', str(target), '-f', 'null', '-'], check=True)
        receipt['records'].append(record)
        unlink_wav(source)
    for stem in DELETE:
        unlink(stem)
    receipt_path.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + '\n')
    print(f'Converted {len(IMPORTS)} recordings, removed {len(DELETE)} old variants.')


if __name__ == '__main__':
    main()
