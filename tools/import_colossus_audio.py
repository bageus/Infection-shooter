#!/usr/bin/env python3
"""Import the owner's colossus_slam recording (2026-10-26); same flow as import_effects_audio.py."""
import hashlib
import json
import subprocess

from build_added_audio import ROOT, convert
from import_effects_audio import unlink_wav
from import_weapon_audio import SFX, unlink


def main():
    receipt_path = ROOT / 'assets/audio/audio_refresh_processing.json'
    receipt = json.loads(receipt_path.read_text())
    out = 'assets/audio/sfx/colossus_slam/colossus_slam_1.ogg'
    receipt['records'] = [r for r in receipt['records'] if r['output'] != out]
    wav, target = SFX / 'colossus_slam/colossus_slam.wav', SFX / 'colossus_slam/colossus_slam_1.ogg'
    record = convert(wav, target, mono=True)
    record['source_sha256'] = hashlib.sha256(wav.read_bytes()).hexdigest()
    record['output_sha256'] = hashlib.sha256(target.read_bytes()).hexdigest()
    subprocess.run(['ffmpeg', '-v', 'error', '-i', str(target), '-f', 'null', '-'], check=True)
    receipt['records'].append(record)
    unlink_wav('colossus_slam/colossus_slam')
    unlink('colossus_slam/colossus_slam_2')
    receipt_path.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
